#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Diff a host's currently-evaluated enabledServices against a committed baseline
# and fail when any service present in the baseline has disappeared.
#
# Usage: diff-enabled-services.sh <host> <baseline.json>
#
# The interface is a contract consumed by later Phase 9 plans: host is always the
# first positional argument, the baseline path always the second.
#
# Both sides are JSON *arrays*. The flake's enabledServices output is produced by
# builtins.filter over a list of service names, so it has no object keys. Do not
# reintroduce a `keys`-based comparison here: on an array, jq's `keys` yields the
# integer indices 0..n-1, which means two entirely different service sets of equal
# length would compare identical and the check would certify nothing. Both sides
# are sorted before comparison so element reordering cannot masquerade as a
# dropped service, and set arithmetic is done with array subtraction.

set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <host> <baseline.json>" >&2
	exit 2
fi

host=$1
baseline=$2

if [ ! -f "$baseline" ]; then
	echo "Baseline file not found: $baseline" >&2
	exit 2
fi

project_root=$(git rev-parse --show-toplevel)
cd "$project_root"

if ! jq -e 'type == "array"' "$baseline" >/dev/null; then
	echo "Baseline $baseline is not a JSON array; refusing to compare" >&2
	exit 2
fi

current=$(mktemp)
trap 'rm -f "$current"' EXIT

nix eval --json ".#enabledServices.${host}" | jq -S 'sort' >"$current"

if ! jq -e 'type == "array"' "$current" >/dev/null; then
	echo "Evaluated .#enabledServices.${host} is not a JSON array; refusing to compare" >&2
	exit 2
fi

removed=$(jq -n --slurpfile a "$baseline" --slurpfile b "$current" '($a[0] - $b[0]) | sort')
added=$(jq -n --slurpfile a "$baseline" --slurpfile b "$current" '($b[0] - $a[0]) | sort')

if [ "$(jq -r 'length' <<<"$added")" -gt 0 ]; then
	echo "Services added since baseline (informational):"
	jq -r '.[] | "  + " + .' <<<"$added"
fi

if [ "$(jq -r 'length' <<<"$removed")" -gt 0 ]; then
	echo "Services REMOVED since baseline (regression):" >&2
	jq -r '.[] | "  - " + .' <<<"$removed" >&2
	echo "Baseline: $baseline" >&2
	exit 1
fi

echo "✓ No service present in $baseline is missing from $host"
