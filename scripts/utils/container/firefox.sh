#!/usr/bin/env bash

# Create Firefox container
create_firefox() {
    run_quietly_if_ci echo "Starting Firefox container..."

    run_docker_container --detach \
        --network="${DOCKER_NETWORK}" \
        --name="firefox.docker" \
        -p 5800:5800 \
        --shm-size=2g \
        -e USER_ID="$(id -u)" \
        -e GROUP_ID="$(id -g)" \
        -e DARK_MODE=1 \
        -v "${ENV_ROOT}/docker/tls/browsers/firefox/cert9.db:/config/profile/cert9.db:rw" \
        -v "${ENV_ROOT}/docker/tls/browsers/firefox/cert_override.txt:/config/profile/cert_override.txt:rw" \
        "${FIREFOX_REPO}:${FIREFOX_TAG}" || error_exit "Failed to start Firefox."
}

delete_firefox() {
    local ff="firefox.docker"

    run_quietly_if_ci echo "Deleting Firefox instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${ff}"; then
        run_quietly_if_ci echo "Firefox container ${ff} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${ff}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${ff}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${ff}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Firefox removed."
}
