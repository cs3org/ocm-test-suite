#!/usr/bin/env sh
helm upgrade -i -n oc-site1 --create-namespace owncloud -f oc1.yaml ../../owncloud
helm upgrade -i -n oc-site2 --create-namespace owncloud -f oc2.yaml ../../owncloud
