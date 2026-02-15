#!/usr/bin/env bash

# Create an OCM-Go container
create_ocmgo() {
    local number="${1}"
    local user="${2}"
    local password="${3}"
    local image="${4}"
    local tag="${5}"

    run_quietly_if_ci echo "Creating EFSS instance: ocmgo ${number}"

    # Container name (ocmgoN.docker) differs from the TLS hostname (ocm-goN.docker),
    # so we need an explicit network alias for TLS SAN resolution.
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="ocmgo${number}.docker" \
        --network-alias="ocm-go${number}.docker" \
        -e HOST="ocm-go${number}" \
        -e OCM_GO_ADMIN_USER="${user}" \
        -e OCM_GO_ADMIN_PASSWORD="${password}" \
        -v "${TLS_CERT_DIR}:/certificates" \
        -v "${TLS_CA_DIR}:/certificate-authority" \
        "${image}:${tag}" || error_exit "Failed to start EFSS container for ocmgo ${number}."

    # Wait for EFSS port to open
    run_quietly_if_ci wait_for_port "ocmgo${number}.docker" 443
}

delete_ocmgo() {
    local number="${1}"
    local os="ocmgo${number}.docker"

    run_quietly_if_ci echo "Deleting OCM-Go instance ${number} …"

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${os}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${os}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${os}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "OCM-Go instance ${number} removed."
}
