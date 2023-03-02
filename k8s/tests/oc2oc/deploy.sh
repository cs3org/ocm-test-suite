#!/usr/bin/env sh

VALUES_DIR=$PWD

cd ../../owncloud || exit

if [ "$1" = "--rebuild" ]; then
    echo "- Rebuilding images..."
    ./build.sh
fi

echo "- Deploying charts..."
helm upgrade -i -n oc-site1 --create-namespace owncloud -f "${VALUES_DIR}/oc1.yaml" --set-file gateway.revad.configFiles.ocm-providers\\.json="${VALUES_DIR}"/ocm-providers.json .
helm upgrade -i -n oc-site2 --create-namespace owncloud -f "${VALUES_DIR}/oc2.yaml" --set-file gateway.revad.configFiles.ocm-providers\\.json="${VALUES_DIR}"/ocm-providers.json .
