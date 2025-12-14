#!/usr/bin/env bash

# CERNBox v2 IdP Container Management
#
# This module provides the canonical IdP helpers for CERNBox v2
# using Keycloak with the cernbox realm preconfigured.

_idp_require_nonempty() {
    local value="${1:-}"
    local name="${2:-"(unknown)"}"

    if [[ -z "${value}" ]]; then
        error_exit "Missing required argument: ${name}"
    fi
}

_idp_container_exists() {
    local name="${1}"
    if docker ps -a --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_idp_container_is_running() {
    local name="${1}"
    if docker ps --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_idp_default_url() {
    if [[ -n "${IDP_URL:-}" ]]; then
        echo "${IDP_URL}"
        return 0
    fi
    if [[ -n "${CERNBOX_IDP_URL:-}" ]]; then
        echo "${CERNBOX_IDP_URL}"
        return 0
    fi
    echo "https://idp.docker"
}

_idp_default_domain() {
    if [[ -n "${IDP_DOMAIN:-}" ]]; then
        echo "${IDP_DOMAIN}"
        return 0
    fi
    if [[ -n "${CERNBOX_IDP_DOMAIN:-}" ]]; then
        echo "${CERNBOX_IDP_DOMAIN}"
        return 0
    fi
    echo "idp.docker"
}

# Create the v2 IdP (Keycloak with cernbox realm)
create_idp() {
    local image="${1:-}"
    local tag="${2:-}"

    _idp_require_nonempty "${image}" "idp_image"
    _idp_require_nonempty "${tag}" "idp_tag"

    local idp="idp.docker"
    local idp_url
    idp_url="$(_idp_default_url)"
    local idp_domain
    idp_domain="$(_idp_default_domain)"

    if _idp_container_exists "${idp}"; then
        if ! _idp_container_is_running "${idp}"; then
            run_quietly_if_ci docker start "${idp}" || true
        fi
        docker network connect "${DOCKER_NETWORK}" "${idp}" >/dev/null 2>&1 || true
        return 0
    fi

    run_quietly_if_ci echo "Creating IdP instance: ${idp}"

    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="${idp}" \
        --cap-add=NET_BIND_SERVICE \
        -e KC_PROXY_HEADERS="${KC_PROXY_HEADERS:-xforwarded}" \
        -e KC_HTTP_ENABLED="${KC_HTTP_ENABLED:-true}" \
        -e KC_HOSTNAME="${KC_HOSTNAME:-${idp_url}}" \
        -e KC_HOSTNAME_ADMIN="${KC_HOSTNAME_ADMIN:-${idp_url}}" \
        -e KC_BOOTSTRAP_ADMIN_USERNAME="${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}" \
        -e KC_BOOTSTRAP_ADMIN_PASSWORD="${KC_BOOTSTRAP_ADMIN_PASSWORD:-admin}" \
        -e KC_HTTPS_CERTIFICATE_FILE="${KC_HTTPS_CERTIFICATE_FILE:-/tls/idp.crt}" \
        -e KC_HTTPS_CERTIFICATE_KEY_FILE="${KC_HTTPS_CERTIFICATE_KEY_FILE:-/tls/idp.key}" \
        -e KC_HTTPS_PORT="${KC_HTTPS_PORT:-443}" \
        -e IDP_DOMAIN="${idp_domain}" \
        -e IDP_URL="${idp_url}" \
        "${image}:${tag}" || error_exit "Failed to start Keycloak container for ${idp}."

    # Keycloak has long warm up time
    sleep 15
}

delete_idp() {
    local idp="idp.docker"

    run_quietly_if_ci echo "Deleting IdP instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${idp}"; then
        run_quietly_if_ci echo "IdP container ${idp} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${idp}" || true

    # Collect any named volumes attached to the container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${idp}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove container (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${idp}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} >/dev/null || true
    fi

    run_quietly_if_ci echo "IdP removed."
}
