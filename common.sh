#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

docker=${DOCKER_PATH:-docker}

function indent() {
	sed 's/^/    /'
}

function indent_cli() {
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
	read -r -p "❓ Do you want to ${1}? (y/n) " yn

	case $yn in
	[yY])
		"${2}"
		return
		;;
	[nN])
		return
		;;
	*) echo invalid response ;;
	esac
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
