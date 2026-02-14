#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# OCM-Go version (default: v1.0.0).
EFSS_PLATFORM_VERSION=${1:-"v1.0.0"}

# dev-stock images.
docker pull pondersource/cypress:latest
docker pull "ghcr.io/mahdibaghbani/containers/opencloudmesh-go:${EFSS_PLATFORM_VERSION}"
