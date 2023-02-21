#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

which docker

# Kubernetes Dashboard admin-user token.
DASHBOARD_TOKEN=""

indent() {
	sed 's/^/    /'
}

indent_cli() {
	if [[ "$OSTYPE" == "darwin"* ]]; then
		sed -l 's/^/   > /'
	else
		sed -u 's/^/   > /'
	fi
}

function helm_add() {
	( 
		(helm repo add "$1" "$2" 2>&1 >/dev/null && echo "✅ $1 repo configured successfully") ||
			(echo "❌ Failed to configure repo $1" && exit 1)
	) | indent
}

function ask() {
	read -r -p "❓ Do you want to proceed? (y/n) " yn

	case $yn in
	[yY])
		$1
		return
		;;
	[nN])
		return
		;;
	*) echo invalid response ;;
	esac
}

function install_k8s_dashboard() {
	(
		echo "🖥️ Installing Kubernetes Dashboard"
		(
			kubectl get namespaces kubernetes-dashboard 2>&1 >/dev/null && echo "✅ Already installed." | indent && return ||
				kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml | indent_cli &&
				kubectl apply -f ./k8s/kubernetes-dashboard/dashboard-adminuser.yaml | indent_cli
		) || (echo "❗️ Failed to install Kubernetes Dashboard. You can set this up later..." | indent)
	) | indent

	DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
}

function install_k8s_ingress_controller() {
	(
		echo "🔀 Installing Nginx ingress controller"
		(
			helm -n ingress-nginx list | grep 'ingress-nginx' 2>&1 >/dev/null && echo "✅ Already installed." | indent && return ||
				helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
					-n ingress-nginx --create-namespace 2>&1 >/dev/null && echo "✅ Ingress controller installed successfully" | indent
		) || (echo "❌ Failed to set up ingress controller" && exit 1)
	) | indent
}

function clone_repo() {
	URL=$1
	NAME=$2
	BRANCH=${3:-main}

	if [ -d "workspace/${NAME}" ]; then
		echo "✅ Repository ${NAME} already present."
		return
	fi

	echo "🌏 Fetching 𓆱  ${BRANCH} of ${NAME}"
	(
		git clone -b "${BRANCH}" "${URL}" "workspace/${NAME}" 2>&1 | indent_cli
	) || (echo "❌ Failed to clone ${NAME}" | indent && exit 1)
}

function fetch_repositories() {
	( 
		(
			mkdir -p workspace/ &&
				clone_repo https://github.com/pondersource/nc-sciencemesh nc-sciencemesh &&
				clone_repo https://github.com/pondersource/oc-sciencemesh oc-sciencemesh &&
				clone_repo https://github.com/cs3org/reva revad master &&
				clone_repo https://github.com/michielbdejong/ocm-stub ocm-stub &&
				clone_repo https://github.com/sciencemesh/efss-deployment-sample.git efss-deployment
		) || (echo "❌ Failed to set up repositories" && exit 1)
	) | indent
}

function configure_helm() {
	( 
		(
			echo "📦 Configuring Helm Chart repositories" &&
				helm_add owncloud https://owncloud-docker.github.io/helm-charts &&
				helm_add nextcloud https://nextcloud.github.io/helm/ &&
				helm_add cs3org https://cs3org.github.io/charts/ &&
				helm_add bitnami https://charts.bitnami.com/bitnami &&
				helm_add ingress-nginx https://kubernetes.github.io/ingress-nginx
		) || (echo "❌ Failed to configure helm repositories" && exit 1)
	) | indent
}

function is_installed() {
	(
		if [ -x "$(command -v "$1")" ]; then
			echo "✅ $1 is properly installed"
		else
			echo "❌ Install $1 before running this script"
			exit 1
		fi
	) | indent
}

echo
echo "🩻  Performing system checks"

is_installed docker
is_installed docker-compose
is_installed git
is_installed helm
is_installed kubectl

( 
	(docker ps 2>&1 >/dev/null && echo "✅ Docker is properly executable") ||
		(echo "❌ Cannot run docker ps, you might need to check that your user is able to use docker properly" && exit 1)
) | indent

( 
	(kubectl cluster-info | grep kubernetes.docker 2>&1 >/dev/null && echo "✅ Minikube cluster is running properly") ||
		(echo "❌ Minikube cluster is not running properly. Please refer to https://minikube.sigs.k8s.io/docs/ on how to start it." && exit 1)
) | indent

echo
echo "🗄️ Setting up folder structure and fetching repositories"
fetch_repositories

echo
echo "☸️ Setting up Kubernetes environment"
configure_helm
ask install_k8s_dashboard
ask install_k8s_ingress_controller

cat <<EOF

 ╔═════════════════════════════════════════╗
 ║ \O/ Ready to go!                        ║
 ╚═════════════════════════════════════════╝

 🖥️  You can check status & manage all k8s services by navigating to:

    http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login

    Use 'admin-user' password:
	${DASHBOARD_TOKEN}
    

 🚀  Start the Nextcloud server by running

	$ docker-compose up -d nextcloud


 💤  Stop it with

	$ docker-compose stop nextcloud


 🗑  Fresh install and wipe all data

	$ docker-compose down -v


	Note that for performance reasons the server repository has been cloned with
	--depth=1. To get the full history it is highly recommended to run:

	$ cd workspace/server
	$ git fetch --unshallow
	$ git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
	$ git fetch origin

	This may take some time depending on your internet connection speed.

EOF
