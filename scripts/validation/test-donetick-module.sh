#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assert, without touching a host, the things the household Donetick
# configuration can get silently wrong. Every one of these produces a
# successful `nix build` with no runtime signal until the unit fails to
# start or a security posture silently regresses, so nothing but an explicit
# assertion catches them.
#
# DT_SINGLE_CIRCLE_INSTANCE: if ever set to true, Donetick removes the
# /api/v1/circles/join and /api/v1/circles/members/requests/accept routes
# that plan 11-05's household bootstrap depends on. Its absence must be
# grepped for directly since there is no config.services.donetick option
# for it -- it only ever exists as a literal string in the env template.
#
# DT_JWT_SECRET: the env template must reference the sops placeholder, never
# a literal value, or the secret would land in the Nix store (T-11-11).
#
# Evaluation failures are deliberately allowed to propagate. Wrapping these
# eval calls in a fallback that substitutes a default on error would make
# the gate certify nothing.

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
	"config.services.donetick.enable" \
	".#nixosConfigurations.${host}.config.services.donetick.enable" \
	'true'

check_eval \
	"config.systemd.services.donetick.serviceConfig.DynamicUser" \
	".#nixosConfigurations.${host}.config.systemd.services.donetick.serviceConfig.DynamicUser" \
	'false'

if nix eval --json ".#nixosConfigurations.${host}.config.networking.firewall.allowedTCPPorts" |
	python3 -c 'import json,sys; sys.exit(0 if 2021 in json.load(sys.stdin) else 1)'; then
	echo "ok: networking.firewall.allowedTCPPorts contains 2021"
else
	echo "FAIL: networking.firewall.allowedTCPPorts does not contain 2021" >&2
	failures=$((failures + 1))
fi

# A plain `nix eval --json .../directories` forces every submodule entry's
# full attrset, including a `method` field the impermanence input removed
# upstream (pre-existing across every household service's entry, not just
# Donetick's -- see deferred-items.md). --apply plucks only `.directory` (or
# the bare string) per entry, never touching `.method`, which sidesteps it.
if nix eval --json --apply \
	'dirs: builtins.elem "/var/lib/donetick" (map (d: if builtins.isString d then d else d.directory) dirs)' \
	".#nixosConfigurations.${host}.config.environment.persistence.\"/persist\".directories" |
	grep -q '^true$'; then
	echo "ok: /var/lib/donetick is a persisted directory"
else
	echo "FAIL: /var/lib/donetick is not in environment.persistence./persist.directories" >&2
	failures=$((failures + 1))
fi

if rg -c 'DT_SINGLE_CIRCLE_INSTANCE' hosts/ser8/household/donetick.nix modules/household/donetick.nix >/dev/null 2>&1; then
	echo "FAIL: DT_SINGLE_CIRCLE_INSTANCE is set somewhere -- this strips routes plan 11-05 needs" >&2
	failures=$((failures + 1))
else
	echo "ok: DT_SINGLE_CIRCLE_INSTANCE is never set"
fi

if rg -q 'DT_JWT_SECRET=\$\{config\.sops\.placeholder\.donetick_jwt_secret\}' hosts/ser8/household/donetick.nix; then
	echo "ok: DT_JWT_SECRET references the sops placeholder, not a literal value"
else
	echo "FAIL: DT_JWT_SECRET does not reference config.sops.placeholder.donetick_jwt_secret" >&2
	failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: the Donetick configuration has drifted" >&2
	exit 1
fi

echo "✓ Donetick configuration confirmed on $host"
