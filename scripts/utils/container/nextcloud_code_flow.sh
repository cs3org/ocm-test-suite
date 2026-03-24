#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Nextcloud code-flow Container Creation Utilities
#
# This script provides scenario-specific wrappers for the code-flow recipient
# topology while reusing the shared OCM-invites Nextcloud container base.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Function: create_nextcloud_code_flow
# Purpose: Creates a Nextcloud code-flow container with MariaDB backend and OCM
#          Invites enabled.
#
# Arguments:
#   $1: Container number/ID
#   $2: Admin username
#   $3: Admin password
#   $4: Docker image (e.g., "ghcr.io/mahdibaghbani/containers/nextcloud-contacts")
#   $5: Docker tag (e.g., "sta-ocm-m6-debian")
#
# Example:
#   create_nextcloud_code_flow 1 "einstein" "relativity" "ghcr.io/mahdibaghbani/containers/nextcloud-contacts" "sta-ocm-m6-debian"
# ------------------------------------------------------------------------------
create_nextcloud_code_flow() {
    _create_nextcloud_contacts_ocm_base "code-flow" "code-flow" "${1}" "${2}" "${3}" "${4}" "${5}"
}

# ------------------------------------------------------------------------------
# Function: delete_nextcloud_code_flow
# Purpose : Stop and remove a Nextcloud code-flow + MariaDB + Valkey trio.
#
# Arguments:
#   $1  Container number
#
# Example:
#   delete_nextcloud_code_flow 1  # removes nextcloud1-code-flow.docker and companions
# ------------------------------------------------------------------------------
delete_nextcloud_code_flow() {
    _delete_nextcloud_contacts_ocm_base "code-flow" "code-flow" "${1}"
}
