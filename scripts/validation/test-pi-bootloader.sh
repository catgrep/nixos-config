#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assert that both Raspberry Pi hosts boot via upstream extlinux and run the
# mainline kernel. This is the permanent gate for the Phase 9 migration off the
# third-party nixos-raspberrypi fork.
#
# Why the bootloader assertion: the fork supplied its own bootloader option path
# and its own U-Boot machinery. Upstream nixos-hardware leaves the Pis on
# boot.loader.generic-extlinux-compatible. If that flips to false, the hosts have
# silently drifted onto some other loader and the extlinux boot entries this repo
# assumes will not be written.
#
# Why the kernel assertion matters more than it looks: both nixos-hardware board
# modules default boot.kernelPackages to the vendor linux-rpi kernel via
# lib.mkDefault, and modules/raspberrypi/base.nix overrides that with a plain
# assignment. A result of "linux-rpi" here means the override stopped applying --
# and because the vendor kernel has no Hydra cache build, any real build would then
# attempt an uncached multi-hour kernel compile rather than fail fast.
#
# Evaluation failures are allowed to propagate. Wrapping these eval calls in a
# fallback that substitutes a default on error would make the gate certify nothing.

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
cd "$project_root"

failures=0

check_eval() {
	local label=$1 expr=$2 expected=$3 actual
	actual=$(nix eval --json "$expr")
	if [ "$actual" != "$expected" ]; then
		echo "FAIL: $label is $actual, expected $expected" >&2
		failures=$((failures + 1))
		return
	fi
	echo "ok: $label = $actual"
}

for host in pi4 pi5; do
	check_eval \
		"${host} boot.loader.generic-extlinux-compatible.enable" \
		".#nixosConfigurations.${host}.config.boot.loader.generic-extlinux-compatible.enable" \
		'true'

	check_eval \
		"${host} boot.kernelPackages.kernel.pname" \
		".#nixosConfigurations.${host}.config.boot.kernelPackages.kernel.pname" \
		'"linux"'
done

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: a Pi host has drifted off extlinux or off the mainline kernel" >&2
	exit 1
fi

echo "✓ both Pi hosts confirmed on extlinux with the mainline kernel"
