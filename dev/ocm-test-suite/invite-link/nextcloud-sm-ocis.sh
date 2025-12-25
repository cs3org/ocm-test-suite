#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Test Nextcloud to oCIS OCM invite link flow tests.
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------
# Description:
#   This script automates the setup and testing of EFSS (Enterprise File Synchronization and Sharing) platforms
#   specifically Nextcloud and oCIS, using ScienceMesh integration and tools like Reva, Cypress, and Docker containers.
#   It supports both development and CI environments, with optional browser support.
# Usage:
#   ./nextcloud-ocis.sh [EFSS_PLATFORM_1_VERSION] [EFSS_PLATFORM_2_VERSION] [SCRIPT_MODE] [BROWSER_PLATFORM]
# Arguments:
#   EFSS_PLATFORM_1_VERSION : Version of Nextcloud (default: "v27.1.11-sm").
#   EFSS_PLATFORM_2_VERSION : Version of oCIS (default: "v5.0.9").
#   SCRIPT_MODE             : Script mode (default: "dev"). Options: dev, ci.
#   BROWSER_PLATFORM        : Browser platform (default: "electron"). Options: chrome, edge, firefox, electron.
# Example:
#   ./nextcloud-ocis.sh v27.1.11-sm v5.0.9 ci electron
# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -euo pipefail

# -----------------------------------------------------------------------------------
# Constants and Default Values
# -----------------------------------------------------------------------------------

# Default versions
DEFAULT_EFSS_1_VERSION="v27.1.11-sm"
DEFAULT_EFSS_2_VERSION="v5.0.9"

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
# -----------------------------------------------------------------------------------
main() {
    # Initialize environment and parse arguments
    initialize_environment "../../.."
    setup "$@"

    # Configure OCM providers for oCIS
    prepare_ocis_environment "ocis1.docker,ocis1.docker,dav/" "revanextcloud1.docker,nextcloud1.docker,remote.php/webdav/"
    
    # Create EFSS containers
    create_nextcloud  1      "marie"       "radioactivity"   pondersource/nextcloud   "${EFSS_PLATFORM_1_VERSION}"
    create_ocis       1                                      owncloud/ocis            "${EFSS_PLATFORM_2_VERSION}"
    
    # Create Reva containers with disabled app configs
    local disabled_configs="sciencemesh-apps-codimd.toml sciencemesh-apps-collabora.toml"
    create_reva "nextcloud" 1       pondersource/revad      v1.28.0      "${disabled_configs}"
    
    # Configure ScienceMesh integration
    configure_sciencemesh "nextcloud" 1 "https://revanextcloud1.docker/" "shared-secret-1"  "https://meshdir.docker/meshdir" "invite-manager-endpoint"

    # Start Mesh Directory
    create_meshdir pondersource/ocmstub v1.1.0
    
    if [ "${SCRIPT_MODE}" = "dev" ]; then
        run_dev \
            "https://nextcloud1.docker (username: marie, password: radioactivity)" \
            "https://ocis1.docker (username: einstein, password: relativity)"
    else
        run_ci "${TEST_SCENARIO}" "${EFSS_PLATFORM_1}" "${EFSS_PLATFORM_2}"
    fi
}

# -----------------------------------------------------------------------------------
# Execute the main function with passed arguments
# -----------------------------------------------------------------------------------
main "$@"
