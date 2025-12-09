#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Script to Automate EFSS OCM Test Suite Execution
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# Description:
#   This script automates EFSS (Enterprise File Synchronization and Sharing) OCM (Open Cloud Mesh) test suite case execution.
#   It supports operations such as login, share-with, share-link, invite-link, and wayf for platforms like
#   Nextcloud, ownCloud, Seafile, and others.

# Usage:
#   ./ocm-test-suite.sh [TEST_CASE] [EFSS_PLATFORM_1] [EFSS_PLATFORM_1_VERSION] [SCRIPT_MODE]
#                  [BROWSER_PLATFORM] [EFSS_PLATFORM_2] [EFSS_PLATFORM_2_VERSION]

# Arguments:
#   TEST_CASE               : Test case to execute (default: "login").
#                             Options: login, share-with, share-link, invite-link, wayf.
#   EFSS_PLATFORM_1         : Primary EFSS platform (default: "nextcloud").
#   EFSS_PLATFORM_1_VERSION : Version of the primary EFSS platform (default: "v27.1.11").
#   SCRIPT_MODE             : Script mode (default: "dev"). Options: dev, ci.
#   BROWSER_PLATFORM        : Browser platform (default: "electron").
#                             Options: chrome, edge, firefox, electron.
#   EFSS_PLATFORM_2         : (Optional) Secondary EFSS platform for interop tests (default: "nextcloud").
#   EFSS_PLATFORM_2_VERSION : (Optional) Version of the secondary EFSS platform (default: "v27.1.11").

# TODO @MahdiBaghbani: How about more documentation? what do we exatly need to run these tests?
# Requirements:
#   - Test scripts must exist in the folder structure: dev/ocm-test-suite/<test-case>/<platform>.sh
#   - Required tools and dependencies must be installed.

# Example:
#   ./ocm-test-suite.sh login nextcloud v27.1.11 ci electron

# Exit Codes:
#   0 - Success
#   1 - Failure or unknown test case/script.

# -----------------------------------------------------------------------------------

# Exit immediately on any error, treat unset variables as an error, and catch errors in pipelines.
set -euo pipefail

# -----------------------------------------------------------------------------------
# Function: resolve_script_dir
# Purpose: Resolves the absolute path of the script's directory, handling symlinks.
# Returns:
#   The absolute path to the script's directory.
# -----------------------------------------------------------------------------------
resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    while [ -L "${source}" ]; do
        dir="$(cd -P "$(dirname "${source}")" >/dev/null 2>&1 && pwd)"
        source="$(readlink "${source}")"
        # Resolve relative symlink
        [[ "${source}" != /* ]] && source="${dir}/${source}"
    done
    dir="$(cd -P "$(dirname "${source}")" >/dev/null 2>&1 && pwd)"
    printf "%s" "${dir}"
}

# -----------------------------------------------------------------------------------
# Function: initialize_environment
# Purpose: Initialize the environment and set global variables.
# -----------------------------------------------------------------------------------
initialize_environment() {
    local script_dir
    script_dir="$(resolve_script_dir)"
    cd "$script_dir/.." || error_exit "Failed to change directory to script root."
    ENV_ROOT="$(pwd)"
    export ENV_ROOT="${ENV_ROOT}"
}

# -----------------------------------------------------------------------------------
# Function: print_error
# Purpose: Print an error message to stderr.
# Arguments:
#   $1 - The error message to display.
# -----------------------------------------------------------------------------------
print_error() {
    local message="${1}"
    printf "Error: %s\n" "$message" >&2
}

# -----------------------------------------------------------------------------------
# Function: error_exit
# Purpose: Print an error message and exit with code 1.
# Arguments:
#   $1 - The error message to display.
# -----------------------------------------------------------------------------------
error_exit() {
    print_error "${1}"
    exit 1
}

# -----------------------------------------------------------------------------------
# Function: run_test_script
# Purpose: Check if a test script exists and is executable, then run it with provided arguments.
# Arguments:
#   $1 - The path to the test script.
#   $@ - Additional arguments to pass to the test script.
# -----------------------------------------------------------------------------------
run_test_script() {
    local script_path="${1}"
    shift
    if [[ -x "${script_path}" ]]; then
        "${script_path}" "$@"
    else
        error_exit "Test script not found or not executable: ${script_path}"
    fi
}

# -----------------------------------------------------------------------------------
# Function: handle_login
# Purpose: Handle the "login" test case.
# Arguments:
#   $1 - EFSS platform.
#   $2 - EFSS platform version.
#   $3 - Script mode.
#   $4 - Browser platform.
# -----------------------------------------------------------------------------------
handle_login() {
    local platform="${1}"
    local version="${2}"
    local mode="${3}"
    local browser="${4}"
    local script_path="${ENV_ROOT}/dev/ocm-test-suite/login/${platform}.sh"
    run_test_script "${script_path}" "${version}" "${mode}" "${browser}"
}

# -----------------------------------------------------------------------------------
# Function: handle_share_with
# Purpose: Handle the "share-with" test case.
# Arguments:
#   $1 - EFSS platform 1.
#   $2 - EFSS platform 1 version.
#   $3 - EFSS platform 2.
#   $4 - EFSS platform 2 version.
#   $5 - Script mode.
#   $6 - Browser platform.
# -----------------------------------------------------------------------------------
handle_share_with() {
    local platform1="${1}"
    local version1="${2}"
    local platform2="${3}"
    local version2="${4}"
    local mode="${5}"
    local browser="${6}"
    local script_path="${ENV_ROOT}/dev/ocm-test-suite/share-with/${platform1}-${platform2}.sh"

    # Check for unsupported combinations.
    if [[ "${platform1}-${platform2}" =~ ^(nextcloud-seafile|owncloud-seafile|seafile-nextcloud|seafile-owncloud)$ ]]; then
        print_error "Combination '${platform1}-${platform2}' is not supported for 'share-with' test case."
        exit 1
    else
        run_test_script "${script_path}" "${version1}" "${version2}" "${mode}" "${browser}"
    fi
}

# -----------------------------------------------------------------------------------
# Function: handle_share_link
# Purpose: Handle the "share-link" test case.
# Arguments:
#   $1 - EFSS platform 1.
#   $2 - EFSS platform 1 version.
#   $3 - EFSS platform 2.
#   $4 - EFSS platform 2 version.
#   $5 - Script mode.
#   $6 - Browser platform.
# -----------------------------------------------------------------------------------
handle_share_link() {
    local platform1="${1}"
    local version1="${2}"
    local platform2="${3}"
    local version2="${4}"
    local mode="${5}"
    local browser="${6}"
    local script_path="${ENV_ROOT}/dev/ocm-test-suite/share-link/${platform1}-${platform2}.sh"

    # Check for unsupported combinations.
    if [[ "${platform1}-${platform2}" =~ ^(nextcloud-seafile|owncloud-seafile|seafile-nextcloud|seafile-owncloud)$ ]]; then
        print_error "Combination '${platform1}-${platform2}' is not supported for 'share-link' test case."
        exit 1
    else
        run_test_script "${script_path}" "${version1}" "${version2}" "${mode}" "${browser}"
    fi
}

# -----------------------------------------------------------------------------------
# Function: handle_invite_link
# Purpose: Handle the "invite-link" test case.
# Arguments:
#   $1 - EFSS platform 1.
#   $2 - EFSS platform 1 version.
#   $3 - EFSS platform 2.
#   $4 - EFSS platform 2 version.
#   $5 - Script mode.
#   $6 - Browser platform.
# -----------------------------------------------------------------------------------
handle_invite_link() {
    local platform1="${1}"
    local version1="${2}"
    local platform2="${3}"
    local version2="${4}"
    local mode="${5}"
    local browser="${6}"
    local script_path="${ENV_ROOT}/dev/ocm-test-suite/invite-link/${platform1}-${platform2}.sh"

    # Check for unsupported combinations.
    if [[ "${platform1}-${platform2}" =~ ^(nextcloud-seafile|owncloud-seafile|seafile-nextcloud|seafile-owncloud)$ ]]; then
        print_error "Combination '${platform1}-${platform2}' is not supported for 'invite-link' test case."
        exit 1
    else
        run_test_script "${script_path}" "${version1}" "${version2}" "${mode}" "${browser}"
    fi
}

# -----------------------------------------------------------------------------------
# Function: handle_wayf
# Purpose: Handle the "wayf" test case.
# Arguments:
#   $1 - EFSS platform 1.
#   $2 - EFSS platform 1 version.
#   $3 - EFSS platform 2.
#   $4 - EFSS platform 2 version.
#   $5 - Script mode.
#   $6 - Browser platform.
# -----------------------------------------------------------------------------------
handle_wayf() {
    local platform1="${1}"
    local version1="${2}"
    local platform2="${3}"
    local version2="${4}"
    local mode="${5}"
    local browser="${6}"
    local script_path="${ENV_ROOT}/dev/ocm-test-suite/wayf/${platform1}-${platform2}.sh"

    # Check for unsupported combinations.
    if [[ "${platform1}-${platform2}" =~ ^(nextcloud-seafile|owncloud-seafile|seafile-nextcloud|seafile-owncloud)$ ]]; then
        print_error "Combination '${platform1}-${platform2}' is not supported for 'wayf' test case."
        exit 1
    else
        run_test_script "${script_path}" "${version1}" "${version2}" "${mode}" "${browser}"
    fi
}

# -----------------------------------------------------------------------------------
# Function: main
# Purpose: Main function to manage the flow of the script.
# -----------------------------------------------------------------------------------
main() {
    # Initialize environment.
    initialize_environment

    # Parse arguments with default values.
    local test_case="${1:-login}"
    local efss_platform_1="${2:-nextcloud}"
    local efss_platform_1_version="${3:-unknown}"
    local script_mode="${4:-dev}"
    local browser_platform="${5:-electron}"
    local efss_platform_2="${6:-nextcloud}"
    local efss_platform_2_version="${7:-unknown}"

    # Validate test case.
    case "${test_case}" in
    "login" | "share-with" | "share-link" | "invite-link" | "wayf") ;;

    *)
        error_exit "Unknown test case: '${test_case}'. Valid options are: login, share-with, share-link, invite-link, wayf."
        ;;
    esac

    # Route the test case to the appropriate handler.
    case "$test_case" in
    "login")
        handle_login "${efss_platform_1}" "${efss_platform_1_version}" "${script_mode}" "${browser_platform}"
        ;;
    "share-with")
        handle_share_with "${efss_platform_1}" "${efss_platform_1_version}" "${efss_platform_2}" "${efss_platform_2_version}" "${script_mode}" "${browser_platform}"
        ;;
    "share-link")
        handle_share_link "${efss_platform_1}" "${efss_platform_1_version}" "${efss_platform_2}" "${efss_platform_2_version}" "${script_mode}" "${browser_platform}"
        ;;
    "invite-link")
        handle_invite_link "${efss_platform_1}" "${efss_platform_1_version}" "${efss_platform_2}" "${efss_platform_2_version}" "${script_mode}" "${browser_platform}"
        ;;
    "wayf")
        handle_wayf "${efss_platform_1}" "${efss_platform_1_version}" "${efss_platform_2}" "${efss_platform_2_version}" "${script_mode}" "${browser_platform}"
        ;;
    esac
}

# -----------------------------------------------------------------------------------
# Execute the main function and pass all script arguments.
# -----------------------------------------------------------------------------------
main "$@"
