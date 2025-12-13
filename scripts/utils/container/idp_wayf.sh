#!/usr/bin/env bash

_idp_wayf_require_nonempty() {
    local value="${1:-}"
    local name="${2:-"(unknown)"}"

    if [[ -z "${value}" ]]; then
        error_exit "Missing required argument: ${name}"
    fi
}

_idp_wayf_container_exists() {
    local name="${1}"
    if docker ps -a --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_idp_wayf_container_is_running() {
    local name="${1}"
    if docker ps --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_idp_wayf_default_url() {
    if [[ -n "${IDP_URL:-}" ]]; then
        echo "${IDP_URL}"
        return 0
    fi
    if [[ -n "${CERNBOX_WAYF_IDP_URL:-}" ]]; then
        echo "${CERNBOX_WAYF_IDP_URL}"
        return 0
    fi
    echo "https://idp.docker"
}

_idp_wayf_default_domain() {
    if [[ -n "${IDP_DOMAIN:-}" ]]; then
        echo "${IDP_DOMAIN}"
        return 0
    fi
    if [[ -n "${CERNBOX_WAYF_IDP_DOMAIN:-}" ]]; then
        echo "${CERNBOX_WAYF_IDP_DOMAIN}"
        return 0
    fi
    echo "idp.docker"
}

create_idp_wayf() {
    local image="${1:-}"
    local tag="${2:-}"

    _idp_wayf_require_nonempty "${image}" "idp_image"
    _idp_wayf_require_nonempty "${tag}" "idp_tag"

    local idp="idp.docker"
    local idp_url
    idp_url="$(_idp_wayf_default_url)"
    local idp_domain
    idp_domain="$(_idp_wayf_default_domain)"

    if _idp_wayf_container_exists "${idp}"; then
        if ! _idp_wayf_container_is_running "${idp}"; then
            run_quietly_if_ci docker start "${idp}" || true
        fi
        docker network connect "${DOCKER_NETWORK}" "${idp}" >/dev/null 2>&1 || true
        return 0
    fi

    run_quietly_if_ci echo "Creating WAYF IdP instance: ${idp}"

    # IdP is reachable on testnet only.
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
