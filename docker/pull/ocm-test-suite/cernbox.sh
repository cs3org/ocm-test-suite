#!/usr/bin/env bash

# @michielbdejong halt on error in docker init scripts.
set -e

# CERNBox v2 only (v1 has been removed)
EFSS_PLATFORM_VERSION=${1:-"v2"}

docker pull pondersource/cypress:latest

# CERNBox v2 stack from DockyPody GHCR
docker pull ghcr.io/mahdibaghbani/containers/idp:latest
docker pull ghcr.io/mahdibaghbani/containers/cernbox-revad:mahdi_fix_localhome-development
docker pull ghcr.io/mahdibaghbani/containers/cernbox-web:testing

