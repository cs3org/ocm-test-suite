#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

. ./common.sh

find . -name build.sh -type f | while read -r build_file; do
	build_dir="$(dirname "${build_file}")"
	(
		echo "🏗️  Building ${build_dir}" | indent &&
			cd "${build_dir}" && ./build.sh . 2>&1 >/dev/null | indent_cli
	)
done
