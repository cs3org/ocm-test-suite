#!/usr/bin/env sh
helm install -n nc-site --create-namespace nextcloud -f nc.yaml ../../sciencemesh-site
helm install -n oc-site --create-namespace owncloud -f oc.yaml ../../sciencemesh-site
