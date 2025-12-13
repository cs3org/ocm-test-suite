#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Clean and Re-Initialize Docker Environment for Testing
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------
# Note: This script performs actions that can significantly alter your Docker 
# environment by removing all containers, networks, and unused data. Ensure that you
# have backups or that it's safe to perform these operations in your environment 
# before running the script.
# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -euo pipefail

# -----------------------------------------------------------------------------------
# Function: resolve_script_dir
# Purpose : Resolves the absolute path of the script's directory, handling symlinks.
# Returns : 
#   Exports SOURCE, SCRIPT_DIR
# Note    : This function relies on BASH_SOURCE, so it must be used in a Bash shell.
# -----------------------------------------------------------------------------------
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"

    # Follow symbolic links until we get the real file location
    while [ -L "${source}" ]; do
        # Get the directory path where the symlink is located
        dir="$(cd -P "$(dirname "${source}")" >/dev/null 2>&1 && pwd)"
        # Use readlink to get the target the symlink points to
        source="$(readlink "${source}")"
        # If the source was a relative symlink, convert it to an absolute path
        [[ "${source}" != /* ]] && source="${dir}/${source}"
    done

    # After resolving symlinks, retrieve the directory of the final source
    SCRIPT_DIR="$(cd -P "$(dirname "${source}")" >/dev/null 2>&1 && pwd)"

    # Exports
    export SOURCE="${source}"
    export SCRIPT_DIR="${SCRIPT_DIR}"
}

# -----------------------------------------------------------------------------------
# Function: initialize_environment
# Purpose :
#   1) Resolve the script's directory.
#   2) Change into that directory plus an optional subdirectory (if provided).
#   3) Export ENV_ROOT as the new working directory.
#   4) Source a utility script (`utils.sh`) with optional version parameters.
#
# Arguments:
#   1) $1 - Relative or absolute path to a subdirectory (optional).
#           If omitted or empty, defaults to '.' (the same directory as resolve_script_dir).
#
# Usage Example:
#   initialize_environment        # Uses the script's directory
#   initialize_environment "dev"  # Changes to script's directory + "/dev"
# -----------------------------------------------------------------------------------
initialize_environment() {
    # Resolve script's directory
    resolve_script_dir

    # Local variables
    local subdir
    # Check if a subdirectory argument was passed; default to '.' if not
    subdir="${1:-.}"

    # Attempt to change into the resolved directory + the subdirectory
    if cd "${SCRIPT_DIR}/${subdir}"; then
        ENV_ROOT="$(pwd)"
        export ENV_ROOT
    else
        printf "Error: %s\n" "Failed to change directory to '${SCRIPT_DIR}/${subdir}'." >&2 && exit 1
    fi

    # shellcheck source=/dev/null
    # Source utility script (assuming it exists and is required for subsequent commands)
    if [[ -f "${ENV_ROOT}/scripts/utils.sh" ]]; then
        source "${ENV_ROOT}/scripts/utils.sh" "${DEFAULT_EFSS_1_VERSION:-}" "${DEFAULT_EFSS_2_VERSION:-}"
    else
        printf "Error: %s\n" "Could not source '${ENV_ROOT}/scripts/utils.sh' (file not found)." >&2 && exit 1
    fi
}

# -----------------------------------------------------------------------------------
# Function: modify_cypress_config
# Purpose: Modifies the Cypress configuration file to set 'modifyObstructiveCode' to true.
# -----------------------------------------------------------------------------------
modify_cypress_config() {
    local config_file="${ENV_ROOT}/cypress/ocm-test-suite/cypress.config.js"
    if [[ -f "${config_file}" ]]; then
        sed -i 's/.*modifyObstructiveCode: false,.*/  modifyObstructiveCode: true,/' "${config_file}"
    else
        run_quietly_if_ci printf "Warning: Configuration file not found: %s\n" "${config_file}" >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------------
# Function: stop_and_remove_docker_containers
# Purpose: Stops and removes all Docker containers.
# -----------------------------------------------------------------------------------
stop_and_remove_docker_containers() {
    # This is a safeguard against the unfortunate event of running the CI Action with
    # bahdotsh/wrkflw or nektos/act which are actually docker container runners themselves.
    # It prevents nuking the dev-stock container, but the act/wrkflw master container
    # gets nuked anyway and halts the CI run. This is only helpful in the actual GitHub CI
    # when the master action runner isn't a container itself and is an LXD container
    # or bare-metal host machine or VPS.
    #
    # 1. Stop running containers whose image or name is NOT dev-stock
    docker ps --format '{{.ID}} {{.Image}} {{.Names}}' |
        { grep -vE '[[:space:]]dev-stock(:|$)|(^|[[:space:]])dev-stock($|[[:space:]])' || true; } |
        awk '{print $1}' |
        xargs -r docker stop

    # 2. Remove all exited or stopped containers except the dev-stock ones
    docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' |
        { grep -vE '[[:space:]]dev-stock(:|$)|(^|[[:space:]])dev-stock($|[[:space:]])' || true; } |
        awk '{print $1}' |
        xargs -r docker rm
}

# -----------------------------------------------------------------------------------
# Function: docker_cleanup
# Purpose: Cleans up unused Docker volumes and system resources.
# -----------------------------------------------------------------------------------
docker_cleanup() {
    # Prune unused Docker volumes without confirmation
    run_quietly_if_ci docker volume prune -f || true
    # Prune unused Docker system data without confirmation
    run_quietly_if_ci docker system prune -f || true
}

# -----------------------------------------------------------------------------------
# Function: recreate_docker_network
# Purpose: Removes and recreates a specified Docker network.
# Arguments:
#   $1 - Name of the Docker network to recreate
# -----------------------------------------------------------------------------------
recreate_docker_network() {
    local network_name="${1}"
    if [[ -z "${network_name}" ]]; then
        run_quietly_if_ci printf "Error: Network name is required.\n" >&2
        exit 1
    fi

    # Remove the Docker network if it exists
    if docker network inspect "${network_name}" >/dev/null 2>&1; then
        docker network rm "${network_name}" >/dev/null 2>&1 || {
            run_quietly_if_ci printf "Warning: Failed to remove Docker network: %s\n" "${network_name}" >&2
        }
    fi

    # Create the Docker network
    docker network create "${network_name}" >/dev/null 2>&1 || {
        run_quietly_if_ci printf "Error: Failed to create Docker network: %s\n" "${network_name}" >&2
        exit 1
    }
}

# -----------------------------------------------------------------------------------
# Function: main
# Usage: clean.sh [yes|no] [platform1 [platform2 ...]]
# -----------------------------------------------------------------------------------
main() {
    # Use existing value or default to "clean"
    : "${SCRIPT_MODE:=clean}"
    export SCRIPT_MODE
    # Initialize environment and parse arguments
    initialize_environment ".."

    modify_cypress_config

    # Args: leading yes|no toggles terminal clear, rest are platform names
    local clear_terminal="yes"
    if [[ $# -gt 0 && ( $1 == "yes" || $1 == "no" ) ]]; then
        clear_terminal="$1"
        shift
    fi

    local platforms=("$@")

    # list of singleton tokens (no numeric suffix)
    local -A SINGLETON=([cypress]=1 [meshdir]=1 [firefox]=1 [vnc]=1 [idp]=1)

    # fine-grained cleanup
    if [[ ${#platforms[@]} -gt 0 ]]; then
        declare -A COUNTER=()                  # per-base-token index
        for raw in "${platforms[@]}"; do
            # 1. Normalize token
            # Drop "-sm" plus trailing digits, e.g. owncloud-sm -> owncloud
            # Drop "-wayf" suffix for wayf containers, e.g. nextcloud-wayf -> nextcloud (but keep wayf flag)
            # revaowncloud-sm -> revaowncloud
            local token="${raw%%-sm*}"
            local is_wayf=false
            if [[ "${raw}" == *-wayf ]]; then
                token="${raw%%-wayf*}"
                is_wayf=true
            fi

            # Singleton containers do not have -wayf variants. If the caller passes something like
            # "idp-wayf", treat it as "idp".
            if [[ "${is_wayf}" == true && ${SINGLETON[$token]+yes} ]]; then
                is_wayf=false
            fi

            # CERNBox cleanup token mapping: both 'cernbox' and 'cernbox-wayf' use the same
            # canonical delete_cernbox helper (which handles v2 multi-Reva teardown).
            # This allows the v2 migration to remove the _wayf suffix from container helpers
            # while maintaining backwards compatibility with existing cleanup token flows.
            if [[ "${token}" == "cernbox" && "${is_wayf}" == true ]]; then
                is_wayf=false
            fi

            local idx="" cname=""

            if [[ ${SINGLETON[$token]+yes} ]]; then
                cname="${token}.docker"                # singleton
            else
                COUNTER["$token"]=$(( COUNTER["$token"] + 1 ))
                idx="${COUNTER[$token]}"
                cname="${token}${idx}.docker"          # numbered
            fi
            # 2. reva or plain delete
            if [[ "${token}" =~ ^reva(.+)$ ]]; then
                local inner_platform="${BASH_REMATCH[1]}"
                if declare -f delete_reva >/dev/null; then
                    delete_reva "${inner_platform}" "${idx:-1}"
                else
                    run_quietly_if_ci printf "Warning: delete_reva function not present - cleaning skipped.\n" >&2
                fi
            else
                # For wayf containers, use delete_${token}_wayf function
                local fn
                if [[ "${is_wayf}" == true ]]; then
                    fn="delete_${token}_wayf"
                else
                    fn="delete_${token}"
                fi
                if declare -f "${fn}" >/dev/null; then
                    [[ -n "${idx}" ]] && "${fn}" "${idx}" || "${fn}"
                else
                    run_quietly_if_ci printf "Warning: no %s function found - cleaning skipped.\n" "${fn}" >&2
                fi
            fi
        done
    else
        # Big Hammer for Nuking the system to the oblivion
        # WARNING: This removes ALL containers except dev-stock. For local testing,
        # always specify platform names: ./scripts/clean.sh nextcloud-wayf cernbox-wayf
        echo "WARNING: Running Big Hammer mode - this will remove ALL containers except dev-stock!" >&2
        echo "For safe local testing, use: ./scripts/clean.sh <platform1> [platform2 ...]" >&2
        stop_and_remove_docker_containers
        docker_cleanup
    fi

    # @MahdiBaghbani: Couldn't decide if this is necessary or not
    recreate_docker_network "testnet"

    # Clear the terminal if requested
    if [[ "${clear_terminal}" == "yes" ]]; then
        clear
    fi
}

# -----------------------------------------------------------------------------------
# Execute the main function with all script arguments
# -----------------------------------------------------------------------------------
# Skip cleanup when NO_CLEANING=true
if [[ "${NO_CLEANING:-}" != "true" ]]; then
    main "$@"
else
    run_quietly_if_ci echo "Skipping cleanup because NO_CLEANING is set to true."
fi
