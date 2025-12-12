#!/usr/bin/env bash

# Create VNC container
create_vnc() {
    run_quietly_if_ci echo "Starting VNC Server..."

    # Define path to the X11 socket directory
    X11_SOCKET="${TEMP_DIR}/.X11-unix"
    export X11_SOCKET="${X11_SOCKET}"

    # Clean up any previous socket files and create a new directory
    remove_directory "${X11_SOCKET}"
    mkdir -p "${X11_SOCKET}"

    # Launch the VNC server container
    run_docker_container --detach \
        --network="${DOCKER_NETWORK}" \
        --name="vnc.docker" \
        -p 5700:8080 \
        -e RUN_XTERM=no \
        -e DISPLAY_WIDTH=1920 \
        -e DISPLAY_HEIGHT=1080 \
        -v "${X11_SOCKET}:/tmp/.X11-unix" \
        "${VNC_REPO}:${VNC_TAG}" || error_exit "Failed to start VNC Server."
}
 
 delete_vnc() {
    local vnc="vnc.docker"

    run_quietly_if_ci echo "Deleting VNC instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${vnc}"; then
        run_quietly_if_ci echo "VNC container ${vnc} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${vnc}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${vnc}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${vnc}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "VNC removed."
}
