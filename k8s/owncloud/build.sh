#!/usr/bin/env sh
export SERVER_VERSION=10.10
export PHP_VERSION=20.04

docker=$DOCKER_PATH

helm dependency build

$docker build . --build-arg SERVER_VERSION=$SERVER_VERSION PHP_VERSION=$PHP_VERSION --tag sciencemesh-owncloud:"${SERVER_VERSION}"
