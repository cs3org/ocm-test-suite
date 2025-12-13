#!/usr/bin/env bash

# Create Cypress container for development mode
create_cypress_dev() {
    run_quietly_if_ci echo "Starting Cypress container..."

    sleep 15

    run_docker_container --detach \
        --network="${DOCKER_NETWORK}" \
        --name="cypress.docker" \
        -e DISPLAY="vnc.docker:0.0" \
        -e CYPRESS_EFSS_PLATFORM_1_VERSION="${EFSS_PLATFORM_1_VERSION%%.*}" \
        -e CYPRESS_EFSS_PLATFORM_2_VERSION="${EFSS_PLATFORM_2_VERSION%%.*}" \
        -v "${ENV_ROOT}/cypress/ocm-test-suite:/ocm" \
        -v "${X11_SOCKET}:/tmp/.X11-unix" \
        -w /ocm \
        --entrypoint cypress \
        "${CYPRESS_REPO}:${CYPRESS_TAG}" \
        open --project . || error_exit "Failed to start Cypress."
}

# Create Cypress container for CI mode
create_cypress_ci() {
    local cypress_spec="${1}"

    if [[ -z "$cypress_spec" ]]; then
        error_exit "No Cypress spec provided. Usage: create_cypress_ci <spec-path>"
    fi

    sleep 15

    run_quietly_if_ci echo "Running Cypress tests using spec: $cypress_spec"

    if [ "${CI_ENVIRONMENT:-}" = "true" ]; then
        # do not mount the ocm test suite files from the local filesystem, 
        # use the internal one provided by the image itself
        # only mount the videos and screenshots
        run_quietly_if_ci echo "Running Cypress without mounting test files from host system"
        docker run --network="${DOCKER_NETWORK}" \
            --name="cypress.docker" \
            -e EFSS_PLATFORM_1_VERSION="${EFSS_PLATFORM_1_VERSION%%.*}" \
            -e EFSS_PLATFORM_2_VERSION="${EFSS_PLATFORM_2_VERSION%%.*}" \
            -v "${ENV_ROOT}/cypress/screenshots:/ocm/cypress/screenshots" \
            -v "${ENV_ROOT}/cypress/videos:/ocm/cypress/videos" \
            -w /ocm \
            "${CYPRESS_REPO}:${CYPRESS_TAG}" \
            cypress run \
            --browser "${BROWSER_PLATFORM}" \
            --spec "${cypress_spec}" ||
            error_exit "Cypress tests failed."
    else
        # mount from internal filesystem, for development
        run_quietly_if_ci echo "Running Cypress with mounting test files from host system"
        docker run --network="${DOCKER_NETWORK}" \
            --name="cypress.docker" \
            -e CYPRESS_EFSS_PLATFORM_1_VERSION="${EFSS_PLATFORM_1_VERSION%%.*}" \
            -e CYPRESS_EFSS_PLATFORM_2_VERSION="${EFSS_PLATFORM_2_VERSION%%.*}" \
            -v "${ENV_ROOT}/cypress/ocm-test-suite:/ocm" \
            -w /ocm \
            "${CYPRESS_REPO}:${CYPRESS_TAG}" \
            cypress run \
            --browser "${BROWSER_PLATFORM}" \
            --spec "${cypress_spec}" ||
            error_exit "Cypress tests failed."
    fi
}

delete_cypress() {
    local cp="cypress.docker"

    run_quietly_if_ci echo "Deleting Cypress instance …"

    if ! docker ps -a --format '{{.Names}}' | grep -qx "${cp}"; then
        run_quietly_if_ci echo "Cypress container ${cp} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${cp}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${cp}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${cp}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Cypress removed."
}
