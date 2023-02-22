#!/usr/bin/env sh

INGRESS_NAMESPACE=${1:-ingress-nginx}
INGRESS_SERVICE=${2:-ingress-nginx-controller}

echo
echo "🔌  Proxying connections to ${INGRESS_NAMESPACE}/${INGRESS_SERVICE} ports 80, 443"
echo

kubectl port-forward --namespace="${INGRESS_NAMESPACE}" service/"${INGRESS_SERVICE}" 8080:80 8443:443
