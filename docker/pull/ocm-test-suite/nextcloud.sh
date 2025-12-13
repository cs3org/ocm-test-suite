#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

EFSS_PLATFORM_VERSION=${1:-"v27.1.11"}

# For logical Nextcloud v33, use DockyPody nextcloud-contacts image with OCM-enabled Contacts app
# rather than pondersource/nextcloud (which has no v33 tag)
if [[ "${EFSS_PLATFORM_VERSION}" == "v33" ]]; then
  # v33-specific dependencies matching WAYF stack
  docker pull mariadb:11.8
  docker pull valkey/valkey:9.0-alpine
  docker pull pondersource/cypress:latest
  docker pull ghcr.io/mahdibaghbani/containers/nextcloud-contacts:v8.1.0-ocm-nc-master-debian
else
  # Legacy versions (v27-v32) use standard pondersource images
  docker pull mariadb:11.4.2
  docker pull pondersource/cypress:latest
  docker pull "pondersource/nextcloud:${EFSS_PLATFORM_VERSION}"
fi
