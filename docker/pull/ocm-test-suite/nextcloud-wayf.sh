#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# Nextcloud WAYF version:
#   - v8.1.0-ocm-nc-master-debian (DockyPody nextcloud-contacts image)
EFSS_PLATFORM_VERSION=${1:-"v8.1.0-ocm-nc-master-debian"}

# 3rd party images.
docker pull mariadb:11.4.2

# dev-stock images.
docker pull pondersource/cypress:latest
docker pull "ghcr.io/mahdibaghbani/containers/nextcloud-contacts:${EFSS_PLATFORM_VERSION}"
