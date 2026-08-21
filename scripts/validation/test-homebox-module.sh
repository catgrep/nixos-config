#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assert, without touching a host, the things the household Homebox
# configuration can get silently wrong. Every one of these produces a
# successful `nix build` and a UI that loads, so nothing but an explicit
# assertion catches them.
#
# homebox package version: the host pins services.homebox.package to
# pkgs.homebox. A future nixpkgs bump could move this past HBX-01's pinned
# 0.25.x line unless re-verified here.
#
# homebox HBOX_WEB_PORT: services.homebox.settings is a freeform
# attrsOf (nullOr str) with no dedicated port option, and the upstream
# module itself never sets HBOX_WEB_PORT (it only documents 7745 as the
# application's internal default). If this literal drifts from the
# firewall rule in modules/household/homebox.nix, the gateway gets a
# closed port and returns a 502.
#
# homebox HBOX_OPTIONS_ALLOW_ANALYTICS: must stay the literal string
# "false" -- a bare Nix boolean here is a hard eval error (the settings
# type is attrsOf (nullOr str)), so this is a value-drift check, not a
# type-safety backstop the way Mealie's toString-based ALLOW_SIGNUP check
# is.
#
# homebox HBOX_OPTIONS_ALLOW_REGISTRATION: must be the literal string
# "false" now that both household accounts exist. Closing self-registration
# is T-11-02's mitigation and this is its offline half; the live half is
# scripts/smoketests/household/test-homebox-endpoint.sh asserting a real
# POST /api/v1/users/register with no invite token returns 403.
#
# Evaluation failures are deliberately allowed to propagate. Wrapping these
# eval calls in a fallback that substitutes a default on error would make the
# gate certify nothing.

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
cd "$project_root"

host=ser8
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

check_eval \
	"HBX-01 homebox package version" \
	".#nixosConfigurations.${host}.config.services.homebox.package.version" \
	'"0.25.0"'

check_eval \
	"HBX-01 homebox HBOX_WEB_PORT" \
	".#nixosConfigurations.${host}.config.services.homebox.settings.HBOX_WEB_PORT" \
	'"7745"'

check_eval \
	"HBX-02 homebox HBOX_OPTIONS_ALLOW_ANALYTICS" \
	".#nixosConfigurations.${host}.config.services.homebox.settings.HBOX_OPTIONS_ALLOW_ANALYTICS" \
	'"false"'

check_eval \
	"HBX-02 homebox HBOX_OPTIONS_ALLOW_REGISTRATION" \
	".#nixosConfigurations.${host}.config.services.homebox.settings.HBOX_OPTIONS_ALLOW_REGISTRATION" \
	'"false"'

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: the Homebox configuration has drifted" >&2
	exit 1
fi

echo "✓ Homebox configuration confirmed on $host"
