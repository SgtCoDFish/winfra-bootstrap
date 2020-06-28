#!/usr/bin/env bash

set -eu -o pipefail

if [[ $# -ne 1 ]]; then
	echo "USAGE: $0 <github-username>"
	echo "e.g.: $0 myuser"
	exit 1
fi

curl -sSL https://github.com/$1.keys > authorized_keys
