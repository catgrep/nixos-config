#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Snapshot freshness smoketest for ser8.
#
# Asserts that the persisted-state tree carries a nightly snapshot, that it is
# younger than the window the whole engine is tuned to, and that the recursive
# snapshot really did reach every child dataset.
#
# The last assertion is the one that is easy to leave out and expensive to
# miss. The parent dataset holds almost none of the state; each service's data
# lives in a child. A snapshot present on the parent but absent from a child is
# a service with no backup at all, and every summary view -- the parent's
# snapshot list, the freshness metric, this test without its third assertion --
# would still look healthy.
#
# No snapshot is a failure, not a skip. A host that has never run the snapshot
# job produces exactly the same empty listing as one whose pool is unreachable,
# and neither may certify a deployment.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# The snapshotted tree, matching hosts/ser8/backup/policy.nix
DS_ROOT="rpool/safe/persist"

# A day plus two hours, the same window the verification job and the staleness
# alert use. Wide enough that a snapshot taken slightly late is not an alert,
# narrow enough that a missed night is.
MAX_AGE_SECONDS=$((26 * 3600))

tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	tests_run=$((tests_run + 1))
	if "$test_func" "$@"; then
		tests_passed=$((tests_passed + 1))
		return 0
	fi
	warn "test failed: $test_name"
	return 1
}

# Run a command on the target host, returning its stdout. Empty output means
# the command could not be run or produced nothing; every caller treats that as
# a failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# The newest snapshot of a dataset whose name matches the nightly shape, as a
# name<TAB>creation-epoch pair, or empty output when there is none.
#
# Matched by literal prefix and suffix rather than by a regex built from the
# dataset name, so a pool name containing a regex metacharacter cannot widen
# the match.
newest_nightly() {
	local dataset="$1"
	remote zfs list -H -p -t snapshot -o name,creation -s creation "$dataset" |
		awk -F'\t' -v ds="$dataset" '
			index($1, ds "@autosnap_") == 1 && $1 ~ /_daily$/ { newest = $0 }
			END { if (newest != "") print newest }
		'
}

# Test 1: a nightly snapshot of the tree exists at all
test_snapshot_exists() {
	info "checking for a nightly snapshot of '$(fmt_bold "$DS_ROOT")'"

	local line
	line=$(newest_nightly "$DS_ROOT")

	if [ -z "$line" ]; then
		fail "no nightly snapshot of '$(fmt_bold "$DS_ROOT")' on $host"
		fail "  'zfs list -t snapshot $DS_ROOT' returned no autosnap_*_daily entry"
		fail "  the snapshot job has never produced a nightly, or the pool could not be read"
		return 1
	fi

	pass "nightly snapshot '$(fmt_bold "${line%%$'\t'*}")' exists"
	return 0
}

# Test 2: that snapshot is inside the freshness window
test_snapshot_fresh() {
	info "checking that the newest nightly snapshot is under $((MAX_AGE_SECONDS / 3600))h old"

	local line
	line=$(newest_nightly "$DS_ROOT")

	if [ -z "$line" ]; then
		fail "could not read the newest nightly snapshot of '$DS_ROOT' from $host"
		return 1
	fi

	local name created
	IFS=$'\t' read -r name created <<<"$line"

	# The host's own clock, not the workstation's. Comparing a host timestamp
	# against a local clock turns any skew between the two into a phantom
	# freshness failure.
	local now
	now=$(remote date +%s)

	if [ -z "$now" ] || [ -z "$created" ]; then
		fail "could not read the current time from $host, or the snapshot carried no creation time"
		return 1
	fi

	case "$now$created" in
	*[!0-9]*)
		fail "unparseable timestamps from $host: now='$now' created='$created'"
		return 1
		;;
	esac

	local age=$((now - created))
	if [ "$age" -gt "$MAX_AGE_SECONDS" ]; then
		fail "the newest nightly snapshot '$(fmt_bold "$name")' is ${age}s old"
		fail "  the snapshot job has not produced a nightly within $((MAX_AGE_SECONDS / 3600))h"
		return 1
	fi

	pass "newest nightly snapshot is ${age}s old, inside the $((MAX_AGE_SECONDS / 3600))h window"
	return 0
}

# Test 3: the recursive snapshot reached every child dataset
#
# The nightly is taken recursively in one transaction, so the same name is
# expected on the parent and on every child. A child missing it is a service
# whose state was not captured, which the parent's own snapshot list cannot
# show.
test_snapshot_covers_children() {
	info "checking that the nightly snapshot name is present on every child dataset"

	local line
	line=$(newest_nightly "$DS_ROOT")

	if [ -z "$line" ]; then
		fail "could not read the newest nightly snapshot of '$DS_ROOT' from $host"
		return 1
	fi

	local name snap
	IFS=$'\t' read -r name _ <<<"$line"
	snap=${name#*@}

	local datasets
	datasets=$(remote zfs list -H -r -o name "$DS_ROOT")
	if [ -z "$datasets" ]; then
		fail "could not list the datasets under '$DS_ROOT' on $host"
		return 1
	fi

	local snapshots
	snapshots=$(remote zfs list -H -r -t snapshot -o name "$DS_ROOT")
	if [ -z "$snapshots" ]; then
		fail "could not list the snapshots under '$DS_ROOT' on $host"
		return 1
	fi

	local missing=()
	local dataset
	while IFS= read -r dataset; do
		[ -n "$dataset" ] || continue
		if ! printf '%s\n' "$snapshots" | grep -qxF "$dataset@$snap"; then
			missing+=("$dataset")
		fi
	done <<<"$datasets"

	if [ "${#missing[@]}" -gt 0 ]; then
		fail "nightly snapshot '$(fmt_bold "$snap")' is MISSING on ${#missing[@]} dataset(s)"
		local absent
		for absent in "${missing[@]}"; do
			fail "  $absent"
		done
		return 1
	fi

	pass "nightly snapshot '$(fmt_bold "$snap")' is present on every dataset under '$DS_ROOT'"
	return 0
}

echo
info "=== Snapshot Freshness Tests ==="
run_test "snapshot_exists" test_snapshot_exists || true
run_test "snapshot_fresh" test_snapshot_fresh || true
run_test "snapshot_covers_children" test_snapshot_covers_children || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run snapshot freshness tests passed"
else
	fail "$tests_passed/$tests_run snapshot freshness tests passed"
	exit 1
fi
