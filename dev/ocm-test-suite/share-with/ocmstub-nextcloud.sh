#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Test OcmStub to Nextcloud OCM share-with flow tests.
# Authors:
#   1. Michiel B. de Jong <michiel@pondersource.com>
#   2. Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------
# Description:
#   This script automates the setup and testing of EFSS (Enterprise File Synchronization and Sharing) platforms
#   such as Nextcloud, OcmStub, using Cypress, and Docker containers.
#   It supports both development and CI environments, with optional browser support.

# Usage:
#   ./ocmstub-nextcloud.sh [EFSS_PLATFORM_1_VERSION] [EFSS_PLATFORM_2_VERSION] [SCRIPT_MODE] [BROWSER_PLATFORM]

# Arguments:
#   EFSS_PLATFORM_1_VERSION : Version of the first EFSS platform (default: "v1.0.0").
#   EFSS_PLATFORM_2_VERSION : Version of the second EFSS platform (default: "v27.1.11").
#   SCRIPT_MODE             : Script mode (default: "dev"). Options: dev, ci.
#   BROWSER_PLATFORM        : Browser platform (default: "electron"). Options: chrome, edge, firefox, electron.

# Requirements:
#   - Docker and required images must be installed.
#   - Test scripts and configurations must be located in the expected directories.
#   - Ensure that the necessary scripts (e.g., init scripts) and configurations exist.

# Example:
#   ./ocmstub-nextcloud.sh v1.0.0 v28.0.14 ci electron

# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -euo pipefail

# -----------------------------------------------------------------------------------
# Constants and Default Values
# -----------------------------------------------------------------------------------

# Default versions
DEFAULT_EFSS_1_VERSION="v1.0.0"
DEFAULT_EFSS_2_VERSION="v28.0.14"

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
        # Create EFSS containers using DockyPody image with source mount
        # NEXTCLOUD_SOURCE_DIR must be set to the host path of the checked-out Nextcloud repo
        create_ocmstub      1                                     pondersource/ocmstub    "${EFSS_PLATFORM_1_VERSION}"
        #                   # id   # username    # password
        create_nextcloud_ci 1      "einstein"    "relativity"
    else
        # Create EFSS containers (dev mode with prebuilt images)
        #                # id   # username    # password       # image                 # tag
        create_ocmstub   1                                     pondersource/ocmstub    "${EFSS_PLATFORM_1_VERSION}"
        create_nextcloud 1      "einstein"    "relativity"     pondersource/nextcloud  "${EFSS_PLATFORM_2_VERSION}"
    fi

    if [ "${SCRIPT_MODE}" = "dev" ]; then
        run_dev \
            "https://ocmstub1.docker/? (just click 'Log in')" \
            "https://nextcloud1.docker (username: einstein, password: relativity)"
    else
        run_ci "${TEST_SCENARIO}" "${EFSS_PLATFORM_1}" "${EFSS_PLATFORM_2}"
    fi
}

# -----------------------------------------------------------------------------------
# Execute the main function with passed arguments
# -----------------------------------------------------------------------------------
main "$@"
