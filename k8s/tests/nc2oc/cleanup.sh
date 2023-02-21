#!/usr/bin/env sh
helm uninstall -n oc-site owncloud
helm uninstall -n nc-site nextcloud

kubectl delete namespaces oc-site nc-site
