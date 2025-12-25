#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Test CERNBox to Opencloud OCM invite link flow tests.
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------
# Description:
#   This script automates the setup and testing of EFSS (Enterprise File Synchronization and Sharing) platforms
#   specifically CERNBox and Opencloud, using ScienceMesh integration and tools like Reva, Cypress, and Docker containers.
#   It supports both development and CI environments, with optional browser support.
# Usage:
#   ./cernbox-opencloud.sh [EFSS_PLATFORM_1_VERSION] [EFSS_PLATFORM_2_VERSION] [SCRIPT_MODE] [BROWSER_PLATFORM]
# Arguments:
#   EFSS_PLATFORM_1_VERSION : Version of CERNBox (default: "v2").
#   EFSS_PLATFORM_2_VERSION : Version of Opencloud (default: "v2.3.0").
#   SCRIPT_MODE             : Script mode (default: "dev"). Options: dev, ci.
#   BROWSER_PLATFORM        : Browser platform (default: "electron"). Options: chrome, edge, firefox, electron.
# Example:
#   ./cernbox-opencloud.sh v2 v2.3.0 ci electron
# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -euo pipefail

# -----------------------------------------------------------------------------------
# Constants and Default Values
# -----------------------------------------------------------------------------------

# Default versions
DEFAULT_EFSS_1_VERSION="v2"
DEFAULT_EFSS_2_VERSION="v2.3.0"

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

    local cernbox_revad_image=ghcr.io/mahdibaghbani/containers/cernbox-revad
    local cernbox_revad_tag=mahdi_fix_localhome-development
    local cernbox_web_image=ghcr.io/mahdibaghbani/containers/cernbox-web
    local cernbox_web_tag=testing
    local cernbox_idp_image=ghcr.io/mahdibaghbani/containers/idp
    local cernbox_idp_tag=latest

    # Create IdP container for CERNBox v2
    create_idp "${cernbox_idp_image}" "${cernbox_idp_tag}"

    # Configure OCM providers for Opencloud
    prepare_opencloud_environment "cernbox1.docker,cernbox1.docker,dav/" "opencloud1.docker,opencloud1.docker,dav/"

    # Create CERNBox v2 container (sender)
    #                 # id      # revad image             # revad tag              # web image               # web tag
    create_cernbox    1         "${cernbox_revad_image}"  "${cernbox_revad_tag}"   "${cernbox_web_image}"    "${cernbox_web_tag}"
    
    # Create OpenCloud container (receiver)
    create_opencloud  1         opencloudeu/opencloud-rolling                   "${EFSS_PLATFORM_2_VERSION}"
    
    # Start Mesh Directory
    create_meshdir pondersource/ocmstub v1.1.0
    
    if [ "${SCRIPT_MODE}" = "dev" ]; then
        run_dev \
          "https://cernbox1.docker (username: einstein, password: relativity)" \
          "https://opencloud1.docker (username: alan, password: demo)"
    else
        run_ci "${TEST_SCENARIO}" "${EFSS_PLATFORM_1}" "${EFSS_PLATFORM_2}"
    fi
}

# -----------------------------------------------------------------------------------
# Execute the main function with passed arguments
# -----------------------------------------------------------------------------------
main "$@"
