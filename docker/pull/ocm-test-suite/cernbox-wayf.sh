#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# CERNBox WAYF version:
#   - v2 (CERNBox v2 WAYF topology using cernbox-revad + cernbox-web + keycloak)
EFSS_PLATFORM_VERSION=${1:-"v2"}

if [[ "${EFSS_PLATFORM_VERSION}" != "v2" ]]; then
  echo "Warning: cernbox-wayf only supports v2 right now (got: ${EFSS_PLATFORM_VERSION}). Continuing with v2 images." >&2
fi

# dev-stock images.
docker pull pondersource/cypress:latest

# CERNBox v2 WAYF images.
docker pull "ghcr.io/mahdibaghbani/containers/idp:latest"
docker pull "ghcr.io/mahdibaghbani/containers/cernbox-revad:mahdi_fix_localhome-development"
docker pull "ghcr.io/mahdibaghbani/containers/cernbox-web:testing"
