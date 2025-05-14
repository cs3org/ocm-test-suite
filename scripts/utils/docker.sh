#!/usr/bin/env bash

# Run a Docker container with provided arguments
run_docker_container() {
    run_quietly_if_ci docker run "$@" || error_exit "Failed to start Docker container: $*"
}

# Prepare Docker environment (network, cleanup)
prepare_environment() {
    # Prepare temporary directories and copy necessary files
    remove_directory "${TEMP_DIR}"
    mkdir -p "${TEMP_DIR}"

    # Skip cleanup when NO_CLEANING=true
    if [[ "${NO_CLEANING}" != "true" ]]; then
        # Clean up previous resources (if the cleanup script is available)
        # WARNING: this is probably going to make real mess of your system and 
        # cause tremendous pain on ci jobs based on docker, since it will NUKE
        # everything related to docker and WIPE it clean.
        # I (@MahdiBaghbani) should delete this, but the use of it is really needed on gitpod,
        # or in isolated dev envs, so there are env variables to disable this functionality.

        # Build argument list for the new clean.sh
        local clean_args=("no" "cypress" "meshdir" "firefox" "vnc" "idp" "${EFSS_PLATFORM_1}")
        if [[ "${TEST_SCENARIO}" != "login" ]]; then
            clean_args+=("reva${EFSS_PLATFORM_1}" "${EFSS_PLATFORM_2}" reva"${EFSS_PLATFORM_2}")
        fi

        if [ -x "${ENV_ROOT}/scripts/clean.sh" ]; then
            "${ENV_ROOT}/scripts/clean.sh" "${clean_args[@]}"
        else
            print_error "Cleanup script not found or not executable at '${ENV_ROOT}/scripts/clean.sh'. Continuing without cleanup."
        fi
    else
        run_quietly_if_ci echo "Skipping cleanup because NO_CLEANING is set to true."
    fi

    # Ensure Docker network exists
    if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
        docker network create "${DOCKER_NETWORK}" >/dev/null 2>&1 ||
            error_exit "Failed to create Docker network '${DOCKER_NETWORK}'."
    fi
}
