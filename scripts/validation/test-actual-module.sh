#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assert that the flake resolves the NixOS 26.05 services.actual module rather
# than the 25.11 one. This is the permanent gate for Phase 9 Success Criterion 3.
#
# The discriminator is option existence, not option value: 25.11's module had a
# hard-coded data directory and an unconditional DynamicUser, so the option paths
# services.actual.user and services.actual.group did not exist at all. Their mere
# resolution proves the newer module is in the closure, and their type name is
# asserted as `nullOr` so a future upstream retype is caught rather than ignored.
#
# Note that dataDir lives under services.actual.settings, not at the top level of
# the module. Evaluation failures are allowed to propagate: wrapping these eval
# calls in a fallback that substitutes a default on error would make the gate
# certify nothing.

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
	"options.services.actual.user type" \
	".#nixosConfigurations.${host}.options.services.actual.user.type.name" \
	'"nullOr"'

check_eval \
	"options.services.actual.group type" \
	".#nixosConfigurations.${host}.options.services.actual.group.type.name" \
	'"nullOr"'

check_eval \
	"config.services.actual.settings.dataDir" \
	".#nixosConfigurations.${host}.config.services.actual.settings.dataDir" \
	'"/var/lib/actual"'

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: the resolved services.actual module is not the 26.05 one" >&2
	exit 1
fi

echo "✓ 26.05 services.actual module confirmed on $host"
