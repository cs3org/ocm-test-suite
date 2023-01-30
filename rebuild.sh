#!/bin/bash
set -e

# base image for nextcloud image and owncloud image:
cd ../apache-php
cp -r ../../tls .
docker build -t apache-php .

# base image for nc1 image and nc2 image:
cd ../nextcloud
# docker build -t nextcloud --build-arg CACHEBUST=`date +%s` .
docker build -t nextcloud .

# image for nc1:
cd ../nc1
docker build -t nc1 .

# image for nc2:
cd ../nc2
docker build -t nc2 .

# base image for oc1 image and oc2 image:
cd ../owncloud
docker build -t owncloud .

# image for oc1:
cd ../oc1
docker build -t oc1 .

# image for oc2:
cd ../oc2
docker build -t oc2 .
