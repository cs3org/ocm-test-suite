#!/usr/bin/env sh
. ../../common.sh

helm dependency update
helm dependency build
