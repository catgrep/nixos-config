#!/usr/bin/env bash
. ./scripts/common.sh

set -euo pipefail

cleanup_hook() {
	if [ ! -f "./result/${result}" ]; then
		errmsg "$0: '${nixattr}' failed!"
		exit 1
	fi
}

usage() {
	infomsg "Usage: $0 <nixattr> <result>"
	echo ""
	echo "Build a target linux-aarch64 artifact using 'nix-build' and copy it out."
	echo ""
	infomsg "Arguments:"
	echo "  nixattr     Name of the nix attribute to build"
	echo "  artifact    Path to the artifact to copy out to './result'. Globbing is allowed."
	echo "  result      What to name the build artifact in './result'"
	echo ""
	infomsg "Examples:"
	echo "$0 installerConfigurations.pi4 *.img.zst pi4-installer.img.zst"
}

if [ $# -lt 3 ]; then
	usage
	exit 1
fi

# Args
nixattr="${1}"
artifact="${2}"
result="${3}"

# Defaults
volume="${NIX_DOCKER_VOLUME:-nix-store-cache}"
image="${NIX_DOCKER_IMAGE:-nixos/nix:2.30.1-arm64}"

infomsg "$0: ensuring Docker volume exists: ${volume}"
docker volume create "${volume}" >/dev/null 2>&1 || true

infomsg "$0: building '$result' using '$nixattr'..."

docker run --rm \
	-v "${volume}:/nix" \
	-v "${PWD}:/build:ro" \
	-v "${PWD}/result:/tmp/output:rw" \
	-w /build \
	"${image}" \
	bash -c "./scripts/linux-aarch64-nix-build.sh ${nixattr} ${artifact}"

msg "$0: ✓ ${nixattr} complete: ./result/${result}"
