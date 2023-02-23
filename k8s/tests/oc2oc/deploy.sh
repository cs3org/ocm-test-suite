#!/usr/bin/env sh

VALUES_DIR=$PWD

echo "1) Building fresh images..."
cd ../../owncloud || exit
./build.sh

echo "2) Deploying charts..."
echo "${VALUES_DIR}/oc1.yaml" "${PWD}"
helm upgrade -i -n oc-site1 --create-namespace owncloud -f "${VALUES_DIR}/oc1.yaml" .
helm upgrade -i -n oc-site2 --create-namespace owncloud -f "${VALUES_DIR}/oc2.yaml" .
