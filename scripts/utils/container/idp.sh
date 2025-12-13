#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Function: delete_idp
# Purpose : Stop and remove singleton IdP container
#
# Example:
#   delete_idp
#
# Notes:
#   • Anonymous volumes are removed automatically with `docker rm -v`.
#   • Named volumes are detected via `docker inspect` and removed explicitly.
#   • Bind-mounts on the host are intentionally not touched.
# ------------------------------------------------------------------------------
delete_idp() {
    local idp="idp.docker"

    run_quietly_if_ci echo "Deleting IdP instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${idp}"; then
        run_quietly_if_ci echo "IdP container ${idp} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${idp}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${idp}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${idp}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} >/dev/null || true
    fi

    run_quietly_if_ci echo "IdP removed."
}
