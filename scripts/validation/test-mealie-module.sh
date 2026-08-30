#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Assert, without touching a host, the five things the household Mealie and
# PostgreSQL configuration can get silently wrong. Every one of these produces a
# successful `nix build` and a UI that loads, so nothing but an explicit
# assertion catches them.
#
# mealie package version: the host pins services.mealie.package to the unstable
# package. If that override is dropped or the specialArg stops resolving, the
# stable 3.16.0 takes over and Alembic migrates the database to a schema the
# pinned version never wrote.
#
# postgresql psqlSchema and dataDir: services.postgresql.enable arrives
# implicitly from services.mealie.database.createLocally, and the postgresql
# module then derives its major from system.stateVersion. ser8's "24.11"
# selects postgresql_16 with no warning. Once data exists at the wrong major,
# recovery requires pg_upgrade against an impermanence-persisted directory.
#
# mealie BASE_URL: the module hardcodes http://localhost:<port>. If the setting
# is lost, every share link and password-reset link points at localhost.
#
# mealie ALLOW_SIGNUP: the module stringifies the whole settings attrset with
# toString, and `toString false` is the empty string in Nix. A Nix boolean here
# type-checks, builds, and silently leaves registration open. What this
# assertion pins is therefore the *type* -- a quoted string -- and it must never
# be relaxed to a JSON literal, whichever way the answer goes.
#
# The expected value is "true" because signup is deliberately open: this
# instance is reachable only over Tailscale, so profile creation is trusted.
# Should that change, close it in the host configuration and change the
# expectation here to the quoted string "false" -- never to a bare false.
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
	"MEAL-01 mealie package version" \
	".#nixosConfigurations.${host}.config.services.mealie.package.version" \
	'"3.22.0"'

check_eval \
	"FOUND-04 postgresql major" \
	".#nixosConfigurations.${host}.config.services.postgresql.package.psqlSchema" \
	'"17"'

check_eval \
	"FOUND-04 postgresql dataDir" \
	".#nixosConfigurations.${host}.config.services.postgresql.dataDir" \
	'"/var/lib/postgresql/17"'

check_eval \
	"MEAL-03 mealie BASE_URL" \
	".#nixosConfigurations.${host}.config.services.mealie.settings.BASE_URL" \
	'"https://mealie.shad-bangus.ts.net"'

check_eval \
	"MEAL-02 mealie ALLOW_SIGNUP" \
	".#nixosConfigurations.${host}.config.services.mealie.settings.ALLOW_SIGNUP" \
	'"true"'

if [ "$failures" -ne 0 ]; then
	echo "$failures assertion(s) failed: the Mealie/PostgreSQL configuration has drifted" >&2
	exit 1
fi

echo "✓ Mealie and PostgreSQL configuration confirmed on $host"
