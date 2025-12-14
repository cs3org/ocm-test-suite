#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Function: create_reva
# Purpose: Create a Reva container for the specified EFSS platform and instance.
# Arguments:
#   $1 - EFSS platform (e.g., nextcloud).
#   $2 - Instance number.
#   $3 - Reva image.
#   $4 - Reva tag.
#   $5 - Disabled configs (optional, space-separated list of config files to disable).
# -----------------------------------------------------------------------------------
create_reva() {
    local platform="${1}"
    local number="${2}"
    local image="${3}"
    local tag="${4}"
    local disabled_configs="${5:-}"

    run_quietly_if_ci echo "Creating Reva ScienceMesh instance: ${platform} ${number}"

    # Reva Versions
    # The first element in this array is considered the "latest".
    reva_versions=("v1.29.0" "v1.28.0")

    # Always append version-based config files to DISABLED_CONFIGS
    # Resolve the active version
    local current_ver
    if [[ "${tag}" == "latest" ]]; then
        # first element is the latest
        current_ver="${reva_versions[0]}"
    else
        current_ver="${tag}"
    fi

    # Build the list of version-specific .toml files to disable
    local extra_disables=""
    local ver_suffix
    for ver in "${reva_versions[@]}"; do
        # skip the active version
        [[ "${ver}" == "${current_ver}" ]] && continue
        # drop “.patch” from the major.minor.patch versions
        ver_suffix="${ver%.*}"                                  
        extra_disables+="sciencemesh-${ver_suffix}.toml "
    done

    # Merge caller-supplied and auto-generated lists, trimming dups
    disabled_configs="$(
        printf '%s\n' ${disabled_configs} ${extra_disables} \
        | awk 'NF&&!seen[$0]++' \
        | xargs echo
    )"

    run_quietly_if_ci echo "Reva ScienceMesh active version is: ${current_ver}, all other version configs has been disabled"
    run_quietly_if_ci echo "disabled configs are: ${disabled_configs}"

    # Start Reva container
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="reva${platform}${number}.docker" \
        -e HOST="reva${platform}${number}" \
        -e DISABLED_CONFIGS="${disabled_configs}" \
        "${image}:${tag}" || error_exit "Failed to start Reva ScienceMesh container for ${platform} ${number}."

    # Wait for Reva port to open (assuming Reva uses port 19000)
    wait_for_port "reva${platform}${number}.docker" 19000
}

delete_reva() {
    local platform="${1}"
    local number="${2}"
    local reva="reva${platform}${number}.docker"

    run_quietly_if_ci echo "Deleting Reva ScienceMesh reva${platform} instance ${number} …"

    # If the container does not exist, skip Docker operations and log softly.
    if ! docker ps -a --format '{{.Names}}' | grep -qx "${reva}"; then
        run_quietly_if_ci echo "Reva ScienceMesh ${reva} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${reva}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${reva}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${reva}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Reva ScienceMesh reva${platform} instance ${number} removed."
}
