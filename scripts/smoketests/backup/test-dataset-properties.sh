#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Dataset property smoketest for ser8.
#
# Both sides of the replication in one test, because they are read the same way
# and they fail for the same kind of reason: a dataset that was created by hand
# without the properties its declaration describes. Disko creates datasets on a
# fresh install and never afterwards, so any dataset added to a running pool is
# created by a human running `zfs create`, and a human who forgets a property
# leaves behind something that works today and is wrong in a way nothing
# reports.
#
# The child list is derived from the declared covered-service set rather than
# written out here, so a service added later is checked without editing this
# file.
#
# Every source-side property is read source-qualified and must be reported as
# local, not inherited. That distinction is the entire point of these
# assertions. An inherited value is right only by accident: it makes the check
# pass today and reverses silently the moment a parent property changes,
# whereas a locally set property is a recorded intent that survives the parent
# being retuned.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

DS_ROOT="rpool/safe/persist"
REPLICA="backup/persist-replica"

# The declared covered-service set, read as data
SERVICES_NIX="./hosts/ser8/backup/services.nix"

# The one child that overrides record size, and the value it overrides it to.
# Every other child keeps the 128K default on purpose: their contents are mixed
# and tuning them on the strength of the database's reasoning would be a guess.
DB_CHILD="postgresql"
DB_RECORDSIZE="16K"

# The directory root the live services keep their state under. A replica
# dataset carrying a mountpoint below this could mount over a running service's
# data; see test_replica_no_live_mountpoints.
LIVE_STATE_ROOT="/var/lib"

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

# The declared covered-service set, one name per line, or empty output on any
# failure. Evaluated as plain data: services.nix takes no arguments, so this
# reads it directly and never evaluates a host configuration.
covered_services() {
	nix eval --raw --file "$SERVICES_NIX" \
		--apply 'set: builtins.concatStringsSep "\n" (builtins.attrNames set)' 2>/dev/null ||
		echo ""
}

# Test 1: every covered child sets access-time updates off, locally
#
# Read for all children in one call. A child that does not exist produces no
# line rather than a wrong one, and the per-service loop below turns a missing
# line into a named failure instead of a silent pass.
test_children_atime_local() {
	info "checking that every covered child sets '$(fmt_bold atime)' off locally"

	local services
	services=$(covered_services)
	if [ -z "$services" ]; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	local datasets=()
	local svc
	while IFS= read -r svc; do
		[ -n "$svc" ] || continue
		datasets+=("$DS_ROOT/$svc")
	done <<<"$services"

	local properties
	properties=$(remote zfs get -H -o name,value,source atime "${datasets[@]}")
	if [ -z "$properties" ]; then
		fail "could not read the atime property of any covered child on $host"
		return 1
	fi

	local bad=()
	local dataset
	for dataset in "${datasets[@]}"; do
		local line
		line=$(printf '%s\n' "$properties" | awk -F'\t' -v ds="$dataset" '$1 == ds { print; exit }')

		if [ -z "$line" ]; then
			bad+=("$dataset: dataset missing, or its atime property could not be read")
			continue
		fi

		local value source
		IFS=$'\t' read -r _ value source <<<"$line"

		if [ "$value" != "off" ]; then
			bad+=("$dataset: atime is '$value', expected 'off'")
		elif [ "$source" != "local" ]; then
			bad+=("$dataset: atime is off but '$source', not 'local'; the value is inherited and would reverse if the parent changed")
		fi
	done

	if [ "${#bad[@]}" -gt 0 ]; then
		fail "${#bad[@]} covered child dataset(s) do not set atime off locally"
		local entry
		for entry in "${bad[@]}"; do
			fail "  $entry"
		done
		return 1
	fi

	pass "all ${#datasets[@]} covered child datasets set atime off locally"
	return 0
}

# Test 2: the database child sets its record size locally
test_database_child_recordsize() {
	local dataset="$DS_ROOT/$DB_CHILD"
	info "checking that '$(fmt_bold "$dataset")' sets recordsize $DB_RECORDSIZE locally"

	local line
	line=$(remote zfs get -H -o value,source recordsize "$dataset")

	if [ -z "$line" ]; then
		fail "could not read the recordsize property of '$dataset' on $host"
		fail "  the dataset is missing, or the pool could not be read"
		return 1
	fi

	local value source
	IFS=$'\t' read -r value source <<<"$line"

	if [ "$value" != "$DB_RECORDSIZE" ]; then
		fail "'$dataset' has recordsize '$value', expected '$DB_RECORDSIZE'"
		return 1
	fi

	if [ "$source" != "local" ]; then
		fail "'$dataset' has recordsize $DB_RECORDSIZE but '$source', not 'local'"
		fail "  the value is inherited and would reverse if the parent's recordsize changed"
		return 1
	fi

	pass "'$(fmt_bold "$dataset")' sets recordsize $DB_RECORDSIZE locally"
	return 0
}

# Test 3: the replica is deduplication-free and has no mountpoint of its own
#
# Deduplication is checked because the backup pool carries a legacy dataset
# that does have it on, and a replica created by hand under the wrong parent
# would inherit it: deduplication costs permanent memory for a table that never
# shrinks, on a pool whose whole job is to still import years from now.
#
# The mountpoint assertion is the replica's real protection. It is checked as a
# value rather than as a locally set property on purpose: the replica is
# created by the replication run rather than declared, and it is meant to
# inherit `none` from the backup pool root. The receive is configured to drop
# the mountpoint travelling in the send stream, and `none` is what proves the
# drop is still happening.
test_replica_properties() {
	info "checking the replica tree's own properties"

	local dedup mountpoint
	dedup=$(remote zfs get -H -o value dedup "$REPLICA")
	mountpoint=$(remote zfs get -H -o value mountpoint "$REPLICA")

	if [ -z "$dedup" ] || [ -z "$mountpoint" ]; then
		fail "could not read the properties of '$REPLICA' on $host"
		fail "  dedup='$dedup' mountpoint='$mountpoint'"
		fail "  the replica does not exist, or the backup pool could not be read"
		return 1
	fi

	if [ "$dedup" != "off" ]; then
		fail "'$REPLICA' has dedup '$dedup', expected 'off'"
		return 1
	fi

	if [ "$mountpoint" != "none" ]; then
		fail "'$REPLICA' has mountpoint '$mountpoint', expected 'none'"
		fail "  a replica with a mountpoint can be mounted over the data it copies"
		return 1
	fi

	pass "'$(fmt_bold "$REPLICA")' has dedup off and no mountpoint"
	return 0
}

# Test 4: no dataset anywhere in the replica tree points at a live state path
#
# This looks like paranoia until the mechanism is spelled out. A dataset's
# mountpoint travels inside a send stream when the send is asked to carry
# properties. Nothing asks it to today, so every replica inherits `none` and
# cannot mount. Turn on property-carrying sends, though, and the replica of a
# service's state dataset arrives holding that service's real mountpoint -- at
# which point the next thing that mounts everything mounts a month-old copy on
# top of the running service's data, and the service is reading backup content
# while believing it is live.
#
# Checked across the whole tree rather than only its root, because the property
# arrives per dataset and one child is enough to do it.
test_replica_no_live_mountpoints() {
	info "checking that no replica dataset points under '$(fmt_bold "$LIVE_STATE_ROOT")'"

	local listing
	listing=$(remote zfs list -H -r -o name,mountpoint "$REPLICA")

	if [ -z "$listing" ]; then
		fail "could not list the datasets under '$REPLICA' on $host"
		return 1
	fi

	local offenders=()
	local name mountpoint
	while IFS=$'\t' read -r name mountpoint; do
		[ -n "$name" ] || continue
		case "$mountpoint" in
		"$LIVE_STATE_ROOT" | "$LIVE_STATE_ROOT"/*)
			offenders+=("$name -> $mountpoint")
			;;
		esac
	done <<<"$listing"

	if [ "${#offenders[@]}" -gt 0 ]; then
		fail "${#offenders[@]} replica dataset(s) carry a mountpoint under $LIVE_STATE_ROOT"
		local entry
		for entry in "${offenders[@]}"; do
			fail "  $entry"
		done
		fail "  mounting the replica would shadow live service state with a copy"
		return 1
	fi

	pass "no replica dataset carries a mountpoint under $LIVE_STATE_ROOT"
	return 0
}

echo
info "=== Source Dataset Property Tests ==="
run_test "children_atime_local" test_children_atime_local || true
run_test "database_child_recordsize" test_database_child_recordsize || true

echo
info "=== Replica Dataset Property Tests ==="
run_test "replica_properties" test_replica_properties || true
run_test "replica_no_live_mountpoints" test_replica_no_live_mountpoints || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run dataset property tests passed"
else
	fail "$tests_passed/$tests_run dataset property tests passed"
	exit 1
fi
