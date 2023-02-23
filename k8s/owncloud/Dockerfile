ARG SERVER_VERSION=10.10
ARG PHP_VERSION=20.04

FROM owncloud/php:${PHP_VERSION} AS sciencemesh-builder

ENV SCIENCEMESH_APP_SOURCE="https://github.com/pondersource/oc-sciencemesh.git"

# Build the latest DEV version of the sciencemesh app
RUN apt update && apt install -y make git nodejs npm patch
RUN mkdir /tmp/build
RUN git clone "${SCIENCEMESH_APP_SOURCE}" /tmp/build/sciencemesh
WORKDIR /tmp/build/sciencemesh
RUN ./release.sh
WORKDIR /tmp/build/sciencemesh/release
RUN tar -xzf sciencemesh.tar.gz

FROM owncloud/server:${SERVER_VERSION} AS server
WORKDIR /var/www/owncloud

COPY ./docker/post_install.d/ /etc/post_install.d/
RUN chmod u+x -R /etc/post_install.d/

# Apply the sciencemesh sharing patch && install the app
RUN apt update && apt install -y patch
RUN curl -sL https://patch-diff.githubusercontent.com/raw/owncloud/core/pull/40577.diff | patch -p1 -t --forward --no-backup-if-mismatch || true
RUN apt remove -y patch && apt autoremove
COPY --from=sciencemesh-builder /tmp/build/sciencemesh/release/sciencemesh ./apps/sciencemesh

# Cleanup & re-set correct permissions
RUN find /var/www/owncloud \( \! -user www-data -o \! -group root \) -print0 | xargs -r -0 chown www-data:root
WORKDIR /var/www/owncloud
