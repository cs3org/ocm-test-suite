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
    # @MahdiBaghbani This is a safeguard agains the unfortunate event of running the CI Action with
    # bahdotsh/wrkflw or nektos/act which are actually docker container runners themselves :)
    # I don't expect it to be effective since it prevents nuking the dev-stock container, RIGHT!
    # but the act/wrkflw master container gets nuked anyway and halts the ci run
    # this is only very helpfull in the actuall GitHub CI when the master action runner isn't
    # a container itself and is a (I suspect) an LXD container bor bare-metal host machine or VPS
    # 1. Stop running containers whose *image* or *name* is NOT dev-stock
    docker ps --format '{{.ID}} {{.Image}} {{.Names}}' |
        { grep -vE '[[:space:]]dev-stock(:|$)|(^|[[:space:]])dev-stock($|[[:space:]])' || true; } |
        awk '{print $1}' |
        xargs -r docker stop

    # 2. Remove all exited/stopped containers except the dev-stock ones
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
# Usage: clean.sh [yes|no] [platform1 [platform2 …]]
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

        # Big Hammer for Nuking the system to the oblivion
        stop_and_remove_docker_containers
        docker_cleanup

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
