#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Test Nextcloud to OCM-Go OCM share-with flow tests.
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------
# Description:
#   This script automates the setup and testing of EFSS (Enterprise File Synchronization and Sharing) platforms
#   such as Nextcloud and OCM-Go, using Cypress, and Docker containers.
#   It supports both development and CI environments, with optional browser support.

# Usage:
#   ./nextcloud-ocmgo.sh [EFSS_PLATFORM_1_VERSION] [EFSS_PLATFORM_2_VERSION] [SCRIPT_MODE] [BROWSER_PLATFORM]

# Arguments:
#   EFSS_PLATFORM_1_VERSION : Version of the first EFSS platform (default: "v27.1.11").
#   EFSS_PLATFORM_2_VERSION : Version of the second EFSS platform (default: "v1.0.0").
#   SCRIPT_MODE             : Script mode (default: "dev"). Options: dev, ci.
#   BROWSER_PLATFORM        : Browser platform (default: "electron"). Options: chrome, edge, firefox, electron.

# Requirements:
#   - Docker and required images must be installed.
#   - Test scripts and configurations must be located in the expected directories.
#   - Ensure that the necessary scripts (e.g., init scripts) and configurations exist.

# Example:
#   ./nextcloud-ocmgo.sh v27.1.11 v1.0.0 ci electron

# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -euo pipefail

# -----------------------------------------------------------------------------------
# Constants and Default Values
# -----------------------------------------------------------------------------------

# Default versions
DEFAULT_EFSS_1_VERSION="v27.1.11"
DEFAULT_EFSS_2_VERSION="v1.0.0"

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
        source "${ENV_ROOT}/scripts/utils.sh" "${DEFAULT_EFSS_1_VERSION}" "${DEFAULT_EFSS_2_VERSION}"
    else
        printf "Error: %s\n" "Could not source '${ENV_ROOT}/scripts/utils.sh' (file not found)." >&2 && exit 1
    fi
}

# -----------------------------------------------------------------------------------
# Main Execution
# Purpose : 
#   1) Initialize the environment
#   2) Parse CLI arguments and validate necessary files
#   3) Prepare environment (clean up, create Docker network, etc.)
#   4) Create EFSS containers
#   5) Run dev or CI mode depending on SCRIPT_MODE
#
# Arguments:
#   All command line arguments are passed to parse_arguments.
#
# Returns : None - the script will exit upon errors (via error_exit) or complete normally.
# -----------------------------------------------------------------------------------
main() {
    # Initialize environment and parse arguments
    initialize_environment "../../.."
    setup "$@"

    if [ "${CI_ENVIRONMENT:-}" = "true" ]; then
        # Create EFSS containers (CI mode: nextcloud uses source-mounted DockyPody image)
        #                   # id   # username    # password
        create_nextcloud_ci 1      "einstein"    "relativity"
        #              # id   # username   # password        # image              # tag
        create_ocmgo   1      "marie"      "radioactivity"   "ghcr.io/mahdibaghbani/containers/opencloudmesh-go"     "${EFSS_PLATFORM_2_VERSION}"
    else
        # Create EFSS containers (dev mode with prebuilt images)
        #                # id   # username    # password       # image                 # tag
        create_nextcloud 1      "einstein"    "relativity"     pondersource/nextcloud  "${EFSS_PLATFORM_1_VERSION}"
        create_ocmgo     1      "marie"       "radioactivity"  "ghcr.io/mahdibaghbani/containers/opencloudmesh-go"        "${EFSS_PLATFORM_2_VERSION}"
    fi

    if [ "${SCRIPT_MODE}" = "dev" ]; then
        run_dev \
            "https://nextcloud1.docker (username: einstein, password: relativity)" \
            "https://ocm-go1.docker (username: marie, password: radioactivity)"
    else
        run_ci "${TEST_SCENARIO}" "${EFSS_PLATFORM_1}" "${EFSS_PLATFORM_2}"
    fi
}

# -----------------------------------------------------------------------------------
# Execute the main function with passed arguments
# -----------------------------------------------------------------------------------
main "$@"
