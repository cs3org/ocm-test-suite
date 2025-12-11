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
#   MARIADB_WAYF_REPO: MariaDB Docker image repository for WAYF tests
#   MARIADB_WAYF_TAG: MariaDB Docker image tag for WAYF tests
#   MYSQL_WAYF_DATABASE: Database name 
#   MYSQL_WAYF_USER: Database user 
#   MYSQL_WAYF_PASSWORD: Database password 
#   VALKEY_WAYF_REPO: Valkey Docker image repository for WAYF tests
#   VALKEY_WAYF_TAG: Valkey Docker image tag for WAYF tests
#   REDIS_WAYF_HOST_PORT: Redis port 
#   REDIS_WAYF_HOST_PASSWORD: Redis password 
#   TLS_CERT_DIR: Directory containing TLS certificates (e.g., nextcloud1.crt, nextcloud1.key)
# ------------------------------------------------------------------------------
_create_nextcloud_wayf_base() {
    local number="${1}"
    local user="${2}"
    local password="${3}"
    local image="${4}"
    local tag="${5}"

    run_quietly_if_ci echo "Creating Nextcloud WAYF instance ${number} with MariaDB backend"

    # Start MariaDB container with optimized configuration matching examples/nextcloud
    # Container name includes -wayf suffix to distinguish from legacy containers
    # MYSQL_* env vars match examples/nextcloud/env - keep in sync when example changes
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="marianextcloud${number}-wayf.docker" \
        -e MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        -e MYSQL_DATABASE="${MYSQL_WAYF_DATABASE}" \
        -e MYSQL_USER="${MYSQL_WAYF_USER}" \
        -e MYSQL_PASSWORD="${MYSQL_WAYF_PASSWORD}" \
        "${MARIADB_WAYF_REPO}":"${MARIADB_WAYF_TAG}" \
        --transaction-isolation=READ-COMMITTED \
        --binlog-format=ROW \
        --innodb-file-per-table=1 \
        --skip-innodb-read-only-compressed || error_exit "Failed to start MariaDB container for nextcloud wayf ${number}."

    # Ensure MariaDB is ready before proceeding
    wait_for_port "marianextcloud${number}-wayf.docker" 3306

    # Start Valkey container for Redis caching
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="redisnextcloud${number}-wayf.docker" \
        "${VALKEY_WAYF_REPO}":"${VALKEY_WAYF_TAG}" || error_exit "Failed to start Valkey container for nextcloud wayf ${number}."

    # Start Nextcloud WAYF container with OCM Invites enabled
    # Container name includes -wayf suffix, but hostname is nextcloud${number}.docker for Cypress compatibility
    # Uses NEXTCLOUD_HTTPS_MODE=https-only to enable HTTPS on port 443 for WAYF tests
    # Mounts TLS certificates for HTTPS support
    # MYSQL_* and CONTACTS_* env vars match examples/nextcloud - keep in sync when example changes
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="nextcloud${number}-wayf.docker" \
        --hostname="nextcloud${number}.docker" \
        --add-host "host.docker.internal:host-gateway" \
        -e HOST="nextcloud${number}" \
        -e NEXTCLOUD_HOST="nextcloud${number}.docker" \
        -e NEXTCLOUD_TRUSTED_DOMAINS="nextcloud${number}.docker" \
        -e APACHE_SERVER_NAME="nextcloud${number}.docker" \
        -e NEXTCLOUD_HTTPS_MODE="https-only" \
        -e NEXTCLOUD_ADMIN_USER="${user}" \
        -e NEXTCLOUD_ADMIN_PASSWORD="${password}" \
        -e NEXTCLOUD_APACHE_LOGLEVEL="warn" \
        -e MYSQL_HOST="marianextcloud${number}-wayf.docker" \
        -e MYSQL_DATABASE="${MYSQL_WAYF_DATABASE}" \
        -e MYSQL_USER="${MYSQL_WAYF_USER}" \
        -e MYSQL_PASSWORD="${MYSQL_WAYF_PASSWORD}" \
        -e REDIS_HOST="redisnextcloud${number}-wayf.docker" \
        -e REDIS_HOST_PORT="${REDIS_WAYF_HOST_PORT}" \
        -e REDIS_HOST_PASSWORD="${REDIS_WAYF_HOST_PASSWORD}" \
        -e CONTACTS_ENABLE_OCM_INVITES="true" \
        -e CONTACTS_OCM_INVITES_MODE="advanced" \
        "${image}:${tag}" || error_exit "Failed to start Nextcloud WAYF container ${number}."


    sleep 10

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
# Purpose : Stop and remove a Nextcloud WAYF + MariaDB + Valkey trio (and their named volumes)
#
# Arguments:
#   $1  Container number
#
# Example:
#   delete_nextcloud_wayf 1       # removes nextcloud1-wayf.docker, marianextcloud1-wayf.docker, redisnextcloud1-wayf.docker
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
    local redis="redisnextcloud${number}-wayf.docker"

    run_quietly_if_ci echo "Deleting Nextcloud WAYF instance ${number} …"

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${nc}" "${db}" "${redis}" || true

    # Collect any **named** volumes attached to the containers
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${nc}" 2>/dev/null || true
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${db}" 2>/dev/null || true
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${redis}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${nc}" "${db}" "${redis}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "Nextcloud WAYF instance ${number} removed."
}
