#!/usr/bin/env sh
# helm install -n nc-site --dry-run --debug --create-namespace nextcloud -f nc.yaml ../../sciencemesh-site
helm install -n oc-site --create-namespace owncloud -f oc.yaml ../../owncloud
