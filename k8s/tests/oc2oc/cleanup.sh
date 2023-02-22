#!/usr/bin/env sh
helm uninstall -n oc-site1 owncloud
helm uninstall -n oc-site2 owncloud

kubectl delete namespaces oc-site1 oc-site2
