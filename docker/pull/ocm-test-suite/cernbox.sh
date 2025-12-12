#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# CERNBox versions:
#   - v1.28.0, v1.29.0 (legacy v1 stack with Keycloak + pondersource images)
#   - v2 (logical v2 using DockyPody GHCR images for idp, cernbox-revad, cernbox-web)
EFSS_PLATFORM_VERSION=${1:-"v1.29.0"}

docker pull pondersource/cypress:latest

if [[ "${EFSS_PLATFORM_VERSION}" == "v2" ]]; then
  # CERNBox v2 stack from DockyPody GHCR
  docker pull ghcr.io/mahdibaghbani/containers/idp:latest
  docker pull ghcr.io/mahdibaghbani/containers/cernbox-revad:mahdi_fix_localhome-development
  docker pull ghcr.io/mahdibaghbani/containers/cernbox-web:testing
else
  # Legacy v1 stack
  docker pull pondersource/keycloak:latest
  docker pull pondersource/cernbox:latest
  docker pull "pondersource/revad-cernbox:${EFSS_PLATFORM_VERSION}"
fi
