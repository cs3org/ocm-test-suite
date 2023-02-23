#!/usr/bin/env sh
export SERVER_VERSION=10.10
export PHP_VERSION=20.04
export TARGET=server-dev

. ../../common.sh

helm dependency update
helm dependency build

clone_repo https://github.com/pondersource/oc-sciencemesh apps/sciencemesh

export DOCKER_BUILDKIT=1 && $docker build . \
    --target $TARGET \
    --build-arg BUILDKIT_INLINE_CACHE=1 SERVER_VERSION=$SERVER_VERSION PHP_VERSION=$PHP_VERSION \
    --tag sciencemesh-owncloud:"${SERVER_VERSION}"
