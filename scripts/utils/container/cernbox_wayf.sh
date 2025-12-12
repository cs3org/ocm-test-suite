#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# CERNBox WAYF Container Creation Utilities
#
# This module owns container orchestration for CERNBox v2 WAYF scenarios.
# It intentionally does NOT map user-facing versions to image tags; callers pass
# explicit image + tag arguments (mirrors nextcloud_wayf.sh pattern).
# ------------------------------------------------------------------------------

_cernbox_wayf_require_nonempty() {
    local value="${1:-}"
    local name="${2:-"(unknown)"}"

    if [[ -z "${value}" ]]; then
        error_exit "Missing required argument: ${name}"
    fi
}

_cernbox_wayf_container_exists() {
    local name="${1}"
    if docker ps -a --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_cernbox_wayf_container_is_running() {
    local name="${1}"
    if docker ps --format '{{.Names}}' | grep -qx "${name}"; then
        return 0
    fi
    return 1
}

_cernbox_wayf_reva_json_volume() {
    local number="${1}"
    echo "cernbox${number}-wayf-reva-jsons"
}

_cernbox_wayf_revad_container_name() {
    local number="${1}"
    local mode="${2}"
    echo "cernbox${number}-wayf-revad-${mode}.docker"
}

_cernbox_wayf_revad_grpc_port_for_mode() {
    local mode="${1}"
    case "${mode}" in
    gateway) echo "9142" ;;
    dataprovider-localhome) echo "9143" ;;
    shareproviders) echo "9144" ;;
    groupuserproviders) echo "9145" ;;
    dataprovider-ocm) echo "9146" ;;
    dataprovider-sciencemesh) echo "9147" ;;
    authprovider-oidc) echo "9158" ;;
    authprovider-publicshares) echo "9160" ;;
    authprovider-machine) echo "9166" ;;
    authprovider-ocmshares) echo "9278" ;;
    *) error_exit "Unknown REVAD_CONTAINER_MODE: ${mode}" ;;
    esac
}

_cernbox_wayf_default_idp_domain() {
    # The domain Reva uses for OIDC discovery and redirects.
    echo "${CERNBOX_WAYF_IDP_DOMAIN:-idp.docker}"
}

_cernbox_wayf_default_idp_url() {
    # Allow full override when debugging (for example including ports).
    if [[ -n "${CERNBOX_WAYF_IDP_URL:-}" ]]; then
        echo "${CERNBOX_WAYF_IDP_URL}"
        return 0
    fi

    local idp_domain
    idp_domain="$(_cernbox_wayf_default_idp_domain)"
    echo "https://${idp_domain}"
}

_cernbox_wayf_default_ocm_directory_service_urls() {
    # Match examples/cernbox/env default.
    echo "${CERNBOX_WAYF_OCM_DIRECTORY_SERVICE_URLS:-https://surfdrive.surf.nl/index.php/s/d0bE1k3P1WHReTq/download}"
}

_create_cernbox_wayf_revad() {
    local number="${1}"
    local mode="${2}"
    local image="${3}"
    local tag="${4}"
    local json_volume="${5}"
    shift 5

    local name
    name="$(_cernbox_wayf_revad_container_name "${number}" "${mode}")"
    local grpc_port
    grpc_port="$(_cernbox_wayf_revad_grpc_port_for_mode "${mode}")"

    run_quietly_if_ci echo "Creating CERNBox WAYF Reva service: ${name} (mode: ${mode})"

    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="${name}" \
        -e "REVAD_CONTAINER_MODE=${mode}" \
        -v "${json_volume}:/var/tmp/reva" \
        "$@" \
        "${image}:${tag}" || error_exit "Failed to start CERNBox WAYF Reva service ${name}."

    wait_for_port "${name}" "${grpc_port}"
}

_cernbox_wayf_web_container_name() {
    local number="${1}"
    echo "cernbox${number}-wayf.docker"
}

create_cernbox_wayf_web() {
    local number="${1:-}"
    local image="${2:-}"
    local tag="${3:-}"

    _cernbox_wayf_require_nonempty "${number}" "number"
    _cernbox_wayf_require_nonempty "${image}" "web_image"
    _cernbox_wayf_require_nonempty "${tag}" "web_tag"

    local domain="cernbox${number}.docker"
    local web_container
    web_container="$(_cernbox_wayf_web_container_name "${number}")"
    local gateway_host
    gateway_host="$(_cernbox_wayf_revad_container_name "${number}" "gateway")"

    local idp_domain
    idp_domain="$(_cernbox_wayf_default_idp_domain)"
    local idp_url
    idp_url="$(_cernbox_wayf_default_idp_url)"

    # Always use the DockyPody-baked TLS certs from the image.
    # Do NOT mount the legacy OCM test-suite TLS directory into /tls, as that would mask the baked certs.
    local tls_crt="${CERNBOX_WAYF_WEB_TLS_CRT:-/tls/cernbox.crt}"
    local tls_key="${CERNBOX_WAYF_WEB_TLS_KEY:-/tls/cernbox.key}"

    if _cernbox_wayf_container_exists "${web_container}"; then
        if ! _cernbox_wayf_container_is_running "${web_container}"; then
            run_quietly_if_ci docker start "${web_container}" || true
        fi
        docker network connect --alias "${domain}" "${DOCKER_NETWORK}" "${web_container}" >/dev/null 2>&1 || true
        return 0
    fi

    run_quietly_if_ci echo "Creating CERNBox WAYF web frontend: ${web_container} (hostname: ${domain})"

    run_docker_container --detach \
        --name="${web_container}" \
        --hostname="${domain}" \
        --user 0:0 \
        -e "CERNBOX_WEB_HOSTNAME=${domain}" \
        -e "WEB_DOMAIN=${domain}" \
        -e "WEB_PROTOCOL=https" \
        -e "WEB_TLS_ENABLED=true" \
        -e "REVAD_TLS_ENABLED=false" \
        -e "REVAD_PROTOCOL=http" \
        -e "REVAD_PORT=80" \
        -e "REVAD_GATEWAY_HOST=${gateway_host}" \
        -e "REVAD_GATEWAY_PORT=80" \
        -e "IDP_DOMAIN=${idp_domain}" \
        -e "IDP_URL=${idp_url}" \
        -e "TLS_CRT=${tls_crt}" \
        -e "TLS_KEY=${tls_key}" \
        "${image}:${tag}" || error_exit "Failed to start CERNBox WAYF web container ${web_container}."

    if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
        error_exit "Docker network '${DOCKER_NETWORK}' not found. Did you run setup/prepare_environment?"
    fi
    docker network connect --alias "${domain}" "${DOCKER_NETWORK}" "${web_container}" >/dev/null 2>&1 || error_exit "Failed to connect ${web_container} to ${DOCKER_NETWORK} with alias ${domain}."

    # Nginx starts quickly; keep a short delay for config generation.
    sleep 2
}

create_cernbox_wayf() {
    local number="${1:-}"
    local revad_image="${2:-}"
    local revad_tag="${3:-}"
    local web_image="${4:-}"
    local web_tag="${5:-}"

    _cernbox_wayf_require_nonempty "${number}" "number"
    _cernbox_wayf_require_nonempty "${revad_image}" "revad_image"
    _cernbox_wayf_require_nonempty "${revad_tag}" "revad_tag"
    _cernbox_wayf_require_nonempty "${web_image}" "web_image"
    _cernbox_wayf_require_nonempty "${web_tag}" "web_tag"

    local domain="cernbox${number}.docker"

    local idp_domain
    idp_domain="$(_cernbox_wayf_default_idp_domain)"
    local idp_url
    idp_url="$(_cernbox_wayf_default_idp_url)"

    local ocm_directory_service_urls
    ocm_directory_service_urls="$(_cernbox_wayf_default_ocm_directory_service_urls)"

    local meshdir_domain="meshdir.docker"
    local meshdir_url=""
    local rclone_endpoint="http://rclone.docker"

    local json_volume
    json_volume="$(_cernbox_wayf_reva_json_volume "${number}")"

    # Reva service names (stable DNS names on testnet)
    local gateway_host
    gateway_host="$(_cernbox_wayf_revad_container_name "${number}" "gateway")"
    local authprovider_oidc_host
    authprovider_oidc_host="$(_cernbox_wayf_revad_container_name "${number}" "authprovider-oidc")"
    local authprovider_machine_host
    authprovider_machine_host="$(_cernbox_wayf_revad_container_name "${number}" "authprovider-machine")"
    local authprovider_ocmshares_host
    authprovider_ocmshares_host="$(_cernbox_wayf_revad_container_name "${number}" "authprovider-ocmshares")"
    local authprovider_publicshares_host
    authprovider_publicshares_host="$(_cernbox_wayf_revad_container_name "${number}" "authprovider-publicshares")"
    local shareproviders_host
    shareproviders_host="$(_cernbox_wayf_revad_container_name "${number}" "shareproviders")"
    local groupuserproviders_host
    groupuserproviders_host="$(_cernbox_wayf_revad_container_name "${number}" "groupuserproviders")"
    local dataprovider_localhome_host
    dataprovider_localhome_host="$(_cernbox_wayf_revad_container_name "${number}" "dataprovider-localhome")"
    local dataprovider_ocm_host
    dataprovider_ocm_host="$(_cernbox_wayf_revad_container_name "${number}" "dataprovider-ocm")"
    local dataprovider_sciencemesh_host
    dataprovider_sciencemesh_host="$(_cernbox_wayf_revad_container_name "${number}" "dataprovider-sciencemesh")"

    local -a revad_env_common=(
        -e "DOMAIN=${domain}"
        -e "REVAD_TLS_ENABLED=false"
        -e "REVAD_PROTOCOL=http"
        -e "REVAD_PORT=80"
        -e "REVAD_CONFIG_DIR=/etc/revad"
        -e "REVAD_LOG_LEVEL=debug"
        -e "REVAD_LOG_OUTPUT=/var/log/revad.log"
        -e "REVAD_JWT_SECRET=reva-secret"
        -e "REVAD_OCMSHARES_JSON_FILE=/var/tmp/reva/shares.json"
        -e "REVAD_GATEWAY_HOST=${gateway_host}"
        -e "REVAD_GATEWAY_PORT=80"
        -e "REVAD_GATEWAY_PROTOCOL=http"
        -e "REVAD_GATEWAY_GRPC_PORT=9142"
        -e "REVAD_AUTHPROVIDER_OIDC_HOST=${authprovider_oidc_host}"
        -e "REVAD_AUTHPROVIDER_OIDC_GRPC_PORT=9158"
        -e "REVAD_AUTHPROVIDER_MACHINE_HOST=${authprovider_machine_host}"
        -e "REVAD_AUTHPROVIDER_MACHINE_GRPC_PORT=9166"
        -e "REVAD_AUTHPROVIDER_OCMSHARES_HOST=${authprovider_ocmshares_host}"
        -e "REVAD_AUTHPROVIDER_OCMSHARES_GRPC_PORT=9278"
        -e "REVAD_AUTHPROVIDER_PUBLICSHARES_HOST=${authprovider_publicshares_host}"
        -e "REVAD_AUTHPROVIDER_PUBLICSHARES_GRPC_PORT=9160"
        -e "REVAD_SHAREPROVIDERS_HOST=${shareproviders_host}"
        -e "REVAD_SHAREPROVIDERS_GRPC_PORT=9144"
        -e "REVAD_GROUPUSERPROVIDERS_HOST=${groupuserproviders_host}"
        -e "REVAD_GROUPUSERPROVIDERS_GRPC_PORT=9145"
        -e "REVAD_DATAPROVIDER_LOCALHOME_HOST=${dataprovider_localhome_host}"
        -e "REVAD_DATAPROVIDER_LOCALHOME_PORT=80"
        -e "REVAD_DATAPROVIDER_LOCALHOME_PROTOCOL=http"
        -e "REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT=9143"
        -e "REVAD_DATAPROVIDER_OCM_HOST=${dataprovider_ocm_host}"
        -e "REVAD_DATAPROVIDER_OCM_PORT=80"
        -e "REVAD_DATAPROVIDER_OCM_PROTOCOL=http"
        -e "REVAD_DATAPROVIDER_OCM_GRPC_PORT=9146"
        -e "REVAD_DATAPROVIDER_SCIENCEMESH_HOST=${dataprovider_sciencemesh_host}"
        -e "REVAD_DATAPROVIDER_SCIENCEMESH_PORT=80"
        -e "REVAD_DATAPROVIDER_SCIENCEMESH_PROTOCOL=http"
        -e "REVAD_DATAPROVIDER_SCIENCEMESH_GRPC_PORT=9147"
    )

    local -a gateway_env=(
        -e "WEB_DOMAIN=${domain}"
        -e "WEB_PROTOCOL=https"
        -e "IDP_DOMAIN=${idp_domain}"
        -e "IDP_URL=${idp_url}"
        -e "MESHDIR_DOMAIN=${meshdir_domain}"
        -e "MESHDIR_URL=${meshdir_url}"
        -e "OCM_DIRECTORY_SERVICE_URLS=${ocm_directory_service_urls}"
        -e "RCLONE_ENDPOINT=${rclone_endpoint}"
    )

    local -a shareproviders_env=(
        -e "WEB_DOMAIN=${domain}"
        -e "WEB_PROTOCOL=https"
    )

    local -a authprovider_oidc_env=(
        -e "IDP_DOMAIN=${idp_domain}"
        -e "IDP_URL=${idp_url}"
    )

    _create_cernbox_wayf_revad "${number}" "gateway" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}" "${gateway_env[@]}"

    _create_cernbox_wayf_revad "${number}" "authprovider-oidc" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}" "${authprovider_oidc_env[@]}"

    _create_cernbox_wayf_revad "${number}" "authprovider-machine" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "authprovider-ocmshares" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "authprovider-publicshares" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "shareproviders" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}" "${shareproviders_env[@]}"

    _create_cernbox_wayf_revad "${number}" "groupuserproviders" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "dataprovider-localhome" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "dataprovider-ocm" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    _create_cernbox_wayf_revad "${number}" "dataprovider-sciencemesh" "${revad_image}" "${revad_tag}" "${json_volume}" \
        "${revad_env_common[@]}"

    create_cernbox_wayf_web "${number}" "${web_image}" "${web_tag}"

    run_quietly_if_ci echo "CERNBox WAYF services started for ${domain}."
}

delete_cernbox_wayf() {
    local number="${1:-}"

    _cernbox_wayf_require_nonempty "${number}" "number"

    local web_container
    web_container="$(_cernbox_wayf_web_container_name "${number}")"
    local json_volume
    json_volume="$(_cernbox_wayf_reva_json_volume "${number}")"

    local -a modes=(
        "gateway"
        "authprovider-oidc"
        "authprovider-machine"
        "authprovider-ocmshares"
        "authprovider-publicshares"
        "shareproviders"
        "groupuserproviders"
        "dataprovider-localhome"
        "dataprovider-ocm"
        "dataprovider-sciencemesh"
    )

    run_quietly_if_ci echo "Deleting CERNBox WAYF instance ${number} ..."

    if _cernbox_wayf_container_exists "${web_container}"; then
        run_quietly_if_ci docker stop "${web_container}" || true
    fi
    for mode in "${modes[@]}"; do
        local name
        name="$(_cernbox_wayf_revad_container_name "${number}" "${mode}")"
        if _cernbox_wayf_container_exists "${name}"; then
            run_quietly_if_ci docker stop "${name}" || true
        fi
    done

    if _cernbox_wayf_container_exists "${web_container}"; then
        run_quietly_if_ci docker rm -fv "${web_container}" || true
    fi
    for mode in "${modes[@]}"; do
        local name
        name="$(_cernbox_wayf_revad_container_name "${number}" "${mode}")"
        if _cernbox_wayf_container_exists "${name}"; then
            run_quietly_if_ci docker rm -fv "${name}" || true
        fi
    done

    run_quietly_if_ci docker volume rm -f "${json_volume}" >/dev/null 2>&1 || true

    run_quietly_if_ci echo "CERNBox WAYF instance ${number} removed."
}
