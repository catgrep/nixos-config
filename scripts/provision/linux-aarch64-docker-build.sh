#!/usr/bin/env bash

. ./scripts/provision/common.sh

set -euo pipefail

cleanup_hook() {
	if [ ! -f "./result/${artifact}" ]; then
		error "$0: '${nixattr}' failed!"
		exit 1
	fi
}

usage() {
	info "Usage: $0 <nixattr> <result>"
	echo ""
	echo "Build a target linux-aarch64 artifact using 'nix-build' and copy it out. This is just a thin"
	echo "docker wrapper around './scripts/linux-aarch64-nix-build.sh' to enable local multi-arch builds."
	echo ""
	info "Arguments:"
	echo "  nixattr     Name of the nix attribute to build"
	echo "  artifact    Exact name of the artifact to copy out to './result'."
	echo ""
	info "Examples:"
	echo "$0 installerConfigurations.pi4 sd-image/nixos-sd-image-rpi4-uboot.img.zst"
}

if [ $# -lt 2 ]; then
	usage
	exit 1
fi

# Args
nixattr="${1}"
artifact="${2}"

# Defaults
volume="${NIX_DOCKER_VOLUME:-nix-store-cache}"
image="${NIX_DOCKER_IMAGE:-nixos/nix:2.30.1-arm64}"

info "$0: ensuring Docker volume exists: ${volume}"
docker volume create "${volume}" >/dev/null 2>&1 || true

info "$0: building '$artifact' using '$nixattr'..."

docker run --rm \
	-v "${volume}:/nix" \
	-v "${PWD}:/build:ro" \
	-v "${PWD}/result:/tmp/output:rw" \
	-w /build \
	"${image}" \
	bash -c "./scripts/linux-aarch64-nix-build.sh ${nixattr} ${artifact}"

info "$0: ✓ ${nixattr} complete: './result/$(basename "${artifact}")'"
