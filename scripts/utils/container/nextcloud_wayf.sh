#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Nextcloud WAYF Container Creation Utilities
#
# This script provides functions for creating Nextcloud containers with OCM
# Invites support using DockyPody nextcloud-contacts images, specifically for
# WAYF (Where Are You From) test scenarios.
#
# Author: Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Function: _create_nextcloud_wayf_base
# Purpose: Internal helper function to create a Nextcloud WAYF container with common configuration
#
# Arguments:
#   $1: Container number/ID
#   $2: Admin username
#   $3: Admin password
#   $4: Docker image
#   $5: Docker tag
#
# Environment Variables Used:
#   DOCKER_NETWORK: Network for container communication (testnet)
#   MARIADB_ROOT_PASSWORD: Root password for MariaDB
#   MARIADB_REPO: MariaDB Docker image repository
#   MARIADB_TAG: MariaDB Docker image tag
# ------------------------------------------------------------------------------
_create_nextcloud_wayf_base() {
    local number="${1}"
    local user="${2}"
    local password="${3}"
    local image="${4}"
    local tag="${5}"

    run_quietly_if_ci echo "Creating Nextcloud WAYF instance ${number} with MariaDB backend"

    # Start MariaDB container with optimized configuration
    # Container name includes -wayf suffix to distinguish from legacy containers
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="marianextcloud${number}-wayf.docker" \
        -e MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        "${MARIADB_REPO}":"${MARIADB_TAG}" \
        --transaction-isolation=READ-COMMITTED \
        --log-bin=binlog \
        --binlog-format=ROW \
        --innodb-file-per-table=1 \
        --skip-innodb-read-only-compressed || error_exit "Failed to start MariaDB container for nextcloud wayf ${number}."

    # Ensure MariaDB is ready before proceeding
    wait_for_port "marianextcloud${number}-wayf.docker" 3306

    # Start Nextcloud WAYF container with OCM Invites enabled
    # Container name includes -wayf suffix, but hostname is nextcloud${number}.docker for Cypress compatibility
    # Uses NEXTCLOUD_HTTPS_MODE=https-only to enable HTTPS on port 443 for WAYF tests
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="nextcloud${number}-wayf.docker" \
        --hostname="nextcloud${number}.docker" \
        --add-host "host.docker.internal:host-gateway" \
        -e HOST="nextcloud${number}" \
        -e NEXTCLOUD_HOST="nextcloud${number}.docker" \
        -e NEXTCLOUD_TRUSTED_DOMAINS="nextcloud${number}.docker" \
        -e NEXTCLOUD_HTTPS_MODE="https-only" \
        -e NEXTCLOUD_ADMIN_USER="${user}" \
        -e NEXTCLOUD_ADMIN_PASSWORD="${password}" \
        -e NEXTCLOUD_APACHE_LOGLEVEL="warn" \
        -e MYSQL_HOST="marianextcloud${number}-wayf.docker" \
        -e MYSQL_DATABASE="efss" \
        -e MYSQL_USER="root" \
        -e MYSQL_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        -e CONTACTS_ENABLE_OCM_INVITES="true" \
        -e CONTACTS_OCM_INVITES_MODE="advanced" \
        "${image}:${tag}" || error_exit "Failed to start Nextcloud WAYF container ${number}."

    # Ensure Nextcloud is ready to accept connections
    run_quietly_if_ci wait_for_port "nextcloud${number}-wayf.docker" 443
}

# ------------------------------------------------------------------------------
# Function: create_nextcloud_wayf
# Purpose: Creates a Nextcloud WAYF container with MariaDB backend and OCM Invites enabled
#
# Arguments:
#   $1: Container number/ID
#   $2: Admin username
#   $3: Admin password
#   $4: Docker image (e.g., "nextcloud-contacts" or "local/nextcloud-contacts")
#   $5: Docker tag (e.g., "ocm-testing")
#
# Example:
#   create_nextcloud_wayf 1 "einstein" "relativity" "local/nextcloud-contacts" "ocm-testing"
# ------------------------------------------------------------------------------
create_nextcloud_wayf() {
    _create_nextcloud_wayf_base "${1}" "${2}" "${3}" "${4}" "${5}"
}

# ------------------------------------------------------------------------------
# Function: delete_nextcloud_wayf
# Purpose : Stop and remove a Nextcloud WAYF + MariaDB pair (and their named volumes)
#
# Arguments:
#   $1  Container number
#
# Example:
#   delete_nextcloud_wayf 1       # removes nextcloud1-wayf.docker & marianextcloud1-wayf.docker
#
# Notes:
#   • Anonymous volumes are removed automatically with `docker rm -v`.
#   • Named volumes are detected via `docker inspect` and removed explicitly.
#   • Bind-mounts on the host are intentionally not touched.
# ------------------------------------------------------------------------------
delete_nextcloud_wayf() {
    local number="${1}"
    local nc="nextcloud${number}-wayf.docker"
    local db="marianextcloud${number}-wayf.docker"

    run_quietly_if_ci echo "Deleting Nextcloud WAYF instance ${number} …"

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${nc}" "${db}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${nc}" 2>/dev/null || true
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${db}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${nc}" "${db}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Nextcloud WAYF instance ${number} removed."
}
