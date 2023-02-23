ARG SERVER_VERSION=10.10
ARG PHP_VERSION=20.04

FROM owncloud/server:${SERVER_VERSION} AS server-base
WORKDIR /var/www/owncloud

COPY ./docker/post_install.d/ /etc/post_install.d/
RUN chmod u+x -R /etc/post_install.d/

# Apply the sciencemesh sharing patch && install the app
RUN apt update && apt install -y patch
RUN curl -sL https://patch-diff.githubusercontent.com/raw/owncloud/core/pull/40577.diff | patch -p1 -t --forward --no-backup-if-mismatch || true
RUN apt remove -y patch && apt autoremove

# Fetches the latest git master version of the sciencemesh app
FROM owncloud/php:${PHP_VERSION} AS sciencemesh-base
RUN apt update && apt install -y make git nodejs npm patch
RUN mkdir /tmp/build

FROM sciencemesh-base AS sciencemesh-git
ARG CACHEBUST=1
ENV SCIENCEMESH_APP_SOURCE="https://github.com/pondersource/oc-sciencemesh.git"
RUN git clone "${SCIENCEMESH_APP_SOURCE}" /tmp/build/sciencemesh
WORKDIR /tmp/build/sciencemesh
RUN ./release.sh
WORKDIR /tmp/build/sciencemesh/release
RUN tar -xzf sciencemesh.tar.gz

FROM sciencemesh-base AS sciencemesh-dev
ARG CACHEBUST=1
COPY ./apps/sciencemesh /tmp/build/sciencemesh
WORKDIR /tmp/build/sciencemesh
RUN ./release.sh
WORKDIR /tmp/build/sciencemesh/release
RUN tar -xzf sciencemesh.tar.gz

FROM server-base as server-git
ARG CACHEBUST=1
COPY --from=sciencemesh-git /tmp/build/sciencemesh/release/sciencemesh ./apps/sciencemesh
RUN find /var/www/owncloud \( \! -user www-data -o \! -group root \) -print0 | xargs -r -0 chown www-data:root
WORKDIR /var/www/owncloud

FROM server-base as server-dev
ARG CACHEBUST=1
COPY --from=sciencemesh-dev /tmp/build/sciencemesh/release/sciencemesh ./apps/sciencemesh
RUN find /var/www/owncloud \( \! -user www-data -o \! -group root \) -print0 | xargs -r -0 chown www-data:root
WORKDIR /var/www/owncloud
