#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Replica freshness smoketest for ser8.
#
# The same freshness assertion as the source side, against the replicated copy
# on the backup pool, and it is a separate test rather than a second case in
# the source one because it fails for entirely different reasons.
#
# Both sides are checked because a snapshot that is never replicated is not a
# backup: it lives on the same disk as the data it protects and dies with it.
# The source side can look perfectly healthy -- snapshots taken on time, every
# child covered -- while replication has been failing for a month, and nothing
# on the source side would say so.
#
# The replica is deliberately never mounted, so everything here is read out of
# pool metadata and nothing tries to open the data.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# The replication target, matching hosts/ser8/backup/policy.nix. It is created
# by the first replication run rather than declared, because a send must land
# on a target that does not yet exist.
REPLICA="backup/persist-replica"

# The source tree the replica is compared against
DS_ROOT="rpool/safe/persist"

# The same day-plus-two-hours window the source side uses
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
newest_nightly() {
	local dataset="$1"
	remote zfs list -H -p -t snapshot -o name,creation -s creation "$dataset" |
		awk -F'\t' -v ds="$dataset" '
			index($1, ds "@autosnap_") == 1 && $1 ~ /_daily$/ { newest = $0 }
			END { if (newest != "") print newest }
		'
}

# Test 1: the replica dataset exists at all
#
# Checked separately from freshness because the two mean different things. A
# missing dataset means replication has never once succeeded; a stale one means
# it succeeded and then stopped. Collapsing them would report the first as the
# second and send whoever reads it looking in the wrong place.
test_replica_exists() {
	info "checking that the replica dataset '$(fmt_bold "$REPLICA")' exists"

	local listed
	listed=$(remote zfs list -H -o name "$REPLICA")

	if [ "$listed" != "$REPLICA" ]; then
		fail "replica dataset '$(fmt_bold "$REPLICA")' does not exist on $host"
		fail "  replication has never completed a first send, or the backup pool is not imported"
		return 1
	fi

	pass "replica dataset '$(fmt_bold "$REPLICA")' exists"
	return 0
}

# Test 2: the replica carries a nightly snapshot inside the freshness window
test_replica_fresh() {
	info "checking that the newest replica snapshot is under $((MAX_AGE_SECONDS / 3600))h old"

	local line
	line=$(newest_nightly "$REPLICA")

	if [ -z "$line" ]; then
		fail "no nightly snapshot on '$(fmt_bold "$REPLICA")' on $host"
		fail "  'zfs list -t snapshot $REPLICA' returned no autosnap_*_daily entry"
		fail "  nothing has ever been replicated, or the backup pool could not be read"
		return 1
	fi

	local name created
	IFS=$'\t' read -r name created <<<"$line"

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
		fail "the newest replica snapshot '$(fmt_bold "$name")' is ${age}s old"
		fail "  replication has not delivered a nightly within $((MAX_AGE_SECONDS / 3600))h"
		fail "  the source may still be snapshotting normally; this is the copy that survives the disk"
		return 1
	fi

	pass "newest replica snapshot is ${age}s old, inside the $((MAX_AGE_SECONDS / 3600))h window"
	return 0
}

# Test 3: the replica's newest nightly is the source's newest nightly
#
# Freshness alone cannot distinguish a replication run that delivered last
# night's snapshot from one that delivered the night before's and then stalled,
# because both are inside the window for part of a day. Comparing the names
# says outright whether the two sides agree.
test_replica_matches_source() {
	info "checking that the replica's newest nightly matches the source's"

	local source_line replica_line
	source_line=$(newest_nightly "$DS_ROOT")
	replica_line=$(newest_nightly "$REPLICA")

	if [ -z "$source_line" ] || [ -z "$replica_line" ]; then
		fail "could not read the newest nightly from both sides on $host"
		fail "  source='$source_line' replica='$replica_line'"
		return 1
	fi

	local source_name replica_name
	IFS=$'\t' read -r source_name _ <<<"$source_line"
	IFS=$'\t' read -r replica_name _ <<<"$replica_line"

	source_name=${source_name#*@}
	replica_name=${replica_name#*@}

	if [ "$source_name" != "$replica_name" ]; then
		fail "the replica's newest nightly does not match the source's"
		fail "  source:  $source_name"
		fail "  replica: $replica_name"
		fail "  the most recent snapshot exists only on the disk it is protecting"
		return 1
	fi

	pass "both sides agree on nightly '$(fmt_bold "$source_name")'"
	return 0
}

echo
info "=== Replica Freshness Tests ==="
run_test "replica_exists" test_replica_exists || true
run_test "replica_fresh" test_replica_fresh || true
run_test "replica_matches_source" test_replica_matches_source || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run replica freshness tests passed"
else
	fail "$tests_passed/$tests_run replica freshness tests passed"
	exit 1
fi
