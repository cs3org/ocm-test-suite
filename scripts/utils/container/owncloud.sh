#!/usr/bin/env bash

# Create an ownCloud container with MariaDB backend
create_owncloud() {
    local number="${1}"
    local user="${2}"
    local password="${3}"
    local image="${4}"
    local tag="${5}"

    run_quietly_if_ci echo "Creating EFSS instance: owncloud ${number}"

    # Start MariaDB container
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="mariaowncloud${number}.docker" \
        -e MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        "${MARIADB_REPO}":"${MARIADB_TAG}" \
        --transaction-isolation=READ-COMMITTED \
        --log-bin=binlog \
        --binlog-format=ROW \
        --innodb-file-per-table=1 \
        --skip-innodb-read-only-compressed || error_exit "Failed to start MariaDB container for owncloud ${number}."

    # Wait for MariaDB port to open
    wait_for_port "mariaowncloud${number}.docker" 3306

    # Start EFSS container
    run_docker_container --detach --network="${DOCKER_NETWORK}" \
        --name="owncloud${number}.docker" \
        --add-host "host.docker.internal:host-gateway" \
        -e HOST="owncloud${number}" \
        -e OWNCLOUD_HOST="owncloud${number}.docker" \
        -e OWNCLOUD_TRUSTED_DOMAINS="owncloud${number}.docker" \
        -e OWNCLOUD_ADMIN_USER="${user}" \
        -e OWNCLOUD_ADMIN_PASSWORD="${password}" \
        -e OWNCLOUD_APACHE_LOGLEVEL="warn" \
        -e MYSQL_HOST="mariaowncloud${number}.docker" \
        -e MYSQL_DATABASE="efss" \
        -e MYSQL_USER="root" \
        -e MYSQL_PASSWORD="${MARIADB_ROOT_PASSWORD}" \
        "${image}:${tag}" || error_exit "Failed to start EFSS container for owncloud ${number}."

    # Wait for EFSS port to open
    run_quietly_if_ci wait_for_port "owncloud${number}.docker" 443
}

delete_owncloud() {
    local number="${1}"
    local oc="owncloud${number}.docker"
    local db="mariaowncloud${number}.docker"

    run_quietly_if_ci echo "Deleting ownCloud instance ${number} …"

    # If neither the app nor DB container exists, skip Docker operations and log softly.
    local any_present="false"
    if docker ps -a --format '{{.Names}}' | grep -qx "${oc}"; then
        any_present="true"
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "${db}"; then
        any_present="true"
    fi
    if [[ "${any_present}" != "true" ]]; then
        run_quietly_if_ci echo "ownCloud instance ${number} not found - cleaning skipped."
        return 0
    fi

    # Stop containers if they exist (ignore errors if already gone/stopped)
    run_quietly_if_ci docker stop "${oc}" "${db}" || true

    # Collect any **named** volumes attached to either container
    local volumes
    volumes="$(
        {
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${oc}" 2>/dev/null || true
            docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "${db}" 2>/dev/null || true
        } | xargs -r echo
    )"

    # Remove containers (+ anonymous volumes with -v)
    run_quietly_if_ci docker rm -fv "${oc}" "${db}" || true

    # Remove any named volumes we discovered
    if [[ -n "${volumes}" ]]; then
        run_quietly_if_ci echo "Removing volumes: ${volumes}"
        run_quietly_if_ci docker volume rm -f ${volumes} || true
    fi

    run_quietly_if_ci echo "ownCloud instance ${number} removed."
}
