#!/usr/bin/env bash

# Run a Docker container with provided arguments
run_docker_container() {
    run_quietly_if_ci docker run "$@" || error_exit "Failed to start Docker container: $*"
}

# Build argument list for clean.sh based on scenario and platforms.
# This helper uses TEST_SCENARIO, EFSS_PLATFORM_1, EFSS_PLATFORM_2 and their
# versions to construct the high level cleanup tokens that scripts/clean.sh
# understands. Only nextcloud and owncloud (including -sm variants) get
# ScienceMesh Reva sidecars; CERNBox, OCIS, and OpenCloud never receive
# reva<platform> tokens.
build_clean_args() {
    # Baseline tokens: no terminal clear, and singleton support containers.
    CLEAN_ARGS=("no" "cypress" "meshdir" "firefox" "vnc")

    local uses_wayf_containers="false"
    if [[ "${TEST_SCENARIO}" == "wayf" ]]; then
        uses_wayf_containers="true"
    elif [[ "${TEST_SCENARIO}" == "login" ]]; then
        # Login v33 (nextcloud) and v2 (cernbox) use WAYF style containers.
        if [[ "${EFSS_PLATFORM_1}" == "nextcloud" && "${EFSS_PLATFORM_1_VERSION}" == "v33" ]]; then
            uses_wayf_containers="true"
        elif [[ "${EFSS_PLATFORM_1}" == "cernbox" && "${EFSS_PLATFORM_1_VERSION}" == "v2" ]]; then
            uses_wayf_containers="true"
        fi
    fi

    if [[ "${uses_wayf_containers}" == "true" ]]; then
        CLEAN_ARGS+=("idp")

        # ocmgo has no WAYF-specific container or delete helper;
        # always use the plain platform token.
        local p1_token="${EFSS_PLATFORM_1}-wayf"
        [[ "${EFSS_PLATFORM_1}" == "ocmgo" ]] && p1_token="${EFSS_PLATFORM_1}"

        if [[ "${TEST_SCENARIO}" == "login" ]]; then
            CLEAN_ARGS+=("${p1_token}")
        else
            local p2_token="${EFSS_PLATFORM_2}-wayf"
            [[ "${EFSS_PLATFORM_2}" == "ocmgo" ]] && p2_token="${EFSS_PLATFORM_2}"
            CLEAN_ARGS+=("${p1_token}")
            CLEAN_ARGS+=("${p2_token}")
        fi
        return 0
    fi

    # Non WAYF scenarios: use canonical platform tokens and Reva sidecars
    # only for nextcloud/owncloud (including -sm variants).
    CLEAN_ARGS+=("idp" "${EFSS_PLATFORM_1}")

    if [[ "${TEST_SCENARIO}" != "login" ]]; then
        CLEAN_ARGS+=("${EFSS_PLATFORM_2}")

        local base1="${EFSS_PLATFORM_1%%-sm*}"
        local base2="${EFSS_PLATFORM_2%%-sm*}"

        if [[ "${base1}" == "nextcloud" || "${base1}" == "owncloud" ]]; then
            CLEAN_ARGS+=("reva${EFSS_PLATFORM_1}")
        fi

        if [[ "${base2}" == "nextcloud" || "${base2}" == "owncloud" ]]; then
            CLEAN_ARGS+=("reva${EFSS_PLATFORM_2}")
        fi
    fi
}

# Prepare Docker environment (network, cleanup)
prepare_environment() {
    # Prepare temporary directories
    remove_directory "${TEMP_DIR}"
    mkdir -p "${TEMP_DIR}"

    # Skip cleanup when NO_CLEANING=true
    if [[ "${NO_CLEANING}" != "true" ]]; then
        # Clean up previous resources (if the cleanup script is available).
        build_clean_args

        if [ -x "${ENV_ROOT}/scripts/clean.sh" ]; then
            "${ENV_ROOT}/scripts/clean.sh" "${CLEAN_ARGS[@]}"
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
