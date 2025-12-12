#!/usr/bin/env bash

create_meshdir() {
    local image="${1}"
    local tag="${2}"

    # Start Mesh Directory
    run_quietly_if_ci echo "Starting Mesh Directory..."

    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="meshdir.docker" \
        -e HOST="meshdir" \
        "${image}:${tag}" || error_exit "Failed to start meshdir."

    # Wait for EFSS port to open
    run_quietly_if_ci wait_for_port "meshdir.docker" 443
}

delete_meshdir() {
    local md="meshdir.docker"

    run_quietly_if_ci echo "Deleting Meshdir instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${md}"; then
        run_quietly_if_ci echo "Meshdir container ${md} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${md}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${md}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${md}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Meshdir removed."
}
