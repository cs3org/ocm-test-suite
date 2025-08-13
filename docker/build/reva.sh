#!/usr/bin/env bash

# -----------------------------------------------------------------------------------
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# -----------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status,
# a variable is used but not defined, or a command in a pipeline fails
set -eo pipefail

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

    sudo rm -rf "${ENV_ROOT}/../cypress/ocm-test-suite/cypress/downloads"

    # Ensure required commands are available
    for cmd in docker; do
        if ! command_exists "${cmd}"; then
            error_exit "Required command '${cmd}' is not available. Please install it and try again."
        fi
    done
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
# Function: command_exists
# Purpose: Check if a command exists on the system.
# Arguments:
#   $1 - The command to check.
# Returns:
#   0 if the command exists, 1 otherwise.
# -----------------------------------------------------------------------------------
command_exists() {
    command -v "${1}" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------------
# Docker Build Functions
# -----------------------------------------------------------------------------------
# A helper function to streamline the Docker build process.
# Arguments:
#   1. Dockerfile path (relative to the current working directory)
#   2. Image name
#   3. Tags (space-separated string of tags)
#   4. Cache Bust to force rebuild.
#   5. Additional build arguments (optional)
#   6. Build context path (optional, defaults to '.')
build_docker_image() {
    local dockerfile="${1}"
    local image_name="${2}"
    local tags="${3}"
    local cache_bust="${4}"
    local build_args="${5:-}"
    local context_path="${6:-.}"

    # Validate that the Dockerfile exists
    if [[ ! -f "./dockerfiles/${dockerfile}" ]]; then
        print_error "Dockerfile not found at '${dockerfile}'. Skipping build of ${image_name}."
        return 1
    fi

    echo "Building image: ${image_name} from Dockerfile: ${dockerfile}"
    if ! docker build \
        --build-arg CACHEBUST="${cache_bust}" ${build_args} \
        --file "./dockerfiles/${dockerfile}" \
        $(for tag in ${tags}; do printf -- "--tag ${image_name}:%s " "${tag}"; done) \
        "${context_path}"; then
        print_error "Failed to build image ${image_name}."
        return 1
    fi

    echo "Successfully built: ${image_name}"
    echo
}

go_version_for_reva() {
  # Input like "v3.0.1", "v1.29.0", or "1.28.0"
  local ref="$1"
  local major
  major="$(sed -E 's/^v?([0-9]+).*/\1/' <<<"$ref")"
  if (( major >= 3 )); then
    printf '%s\n' "1.24.6"
  else
    printf '%s\n' "1.23.12"
  fi
}


# -----------------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------------
main() {
    # Initialize environment and source utilities
    initialize_environment

    # Enable Docker BuildKit (Optional)
    USE_BUILDKIT=${1:-1}
    export DOCKER_BUILDKIT="${USE_BUILDKIT}"

    # export BUILDKIT_PROGRESS=plain

    # -----------------------------------------------------------------------------------
    # Build Images
    # -----------------------------------------------------------------------------------

    # Reva Repo
    REVA_REPO=https://github.com/cs3org/reva

    # Reva Versions
    # The first element in this array is considered the "latest".
    reva_versions=("v3.0.1" "v1.29.0" "v1.28.0")

    # Iterate over the array of versions
    for i in "${!reva_versions[@]}"; do
        version="${reva_versions[i]}"

        tags="${version}"
        # If this is the first element (index 0), also add the "latest" tag
        [[ "$i" -eq 0 ]] && tags+=" latest"

        GO_VERSION="$(go_version_for_reva "$version")"
        
        build_args="--build-arg GO_VERSION=${GO_VERSION}"
        build_args="${build_args} --build-arg REVA_REPO=${REVA_REPO}"
        build_args="${build_args} --build-arg REVA_BRANCH=${version}"
        
        # Revad base
        build_docker_image \
            revad-base.Dockerfile \
            pondersource/revad-base \
            "${tags}" \
            DEFAULT \
            "${build_args}"

        # Revad CERNBox
        build_docker_image \
            revad-cernbox.Dockerfile \
            pondersource/revad-cernbox \
            "${tags}" \
            DEFAULT \
            "${build_args}"

        # Revad ScienceMesh
        build_docker_image \
            revad.Dockerfile \
            pondersource/revad \
            "${tags}" \
            DEFAULT \
            "${build_args}"
    done

    # CERNBox Web
    build_docker_image cernbox.Dockerfile           pondersource/cernbox            "v1.0.0 latest"             DEFAULT
    
    echo "All builds attempted."
    echo "Check the above output for any build failures or errors."
}

# -----------------------------------------------------------------------------------
# Execute the main function and pass all script arguments.
# -----------------------------------------------------------------------------------
main "$@"
