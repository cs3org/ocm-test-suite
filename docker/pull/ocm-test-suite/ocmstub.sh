#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# OCM Stub version (default: v1.0.0 for legacy scenarios).
# v1.1.0 is the invite-link Stub tag used by invite-link scenarios.
EFSS_PLATFORM_VERSION=${1:-"v1.0.0"}

# dev-stock images.
docker pull pondersource/cypress:latest
docker pull "pondersource/ocmstub:${EFSS_PLATFORM_VERSION}"

# This is temporary to fix some CI problems should be removed and depend on the env variables
docker pull "pondersource/ocmstub:v1.0.0"
docker pull "pondersource/ocmstub:v1.1.0"
