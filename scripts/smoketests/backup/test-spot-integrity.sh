#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Spot structural check for ser8.
#
# The nightly verification opens every database inside the snapshot the way a
# restore would. This runs that same mechanism against one database at
# deployment time, so a change that breaks it is caught by the person who made
# it rather than at three in the morning by a job whose mail nobody is
# expecting.
#
# The copy is not a workaround, it is the thing being tested. A write-ahead-log
# database is not the file alone: its recent transactions live in a sidecar log
# whose replay needs a shared-memory file created beside the database. A
# snapshot path is read-only, so that file cannot be created there -- checking
# in place either errors, or, if the database is opened as unchangeable to make
# the error go away, skips the log and certifies a stale image while reporting
# success. That second behaviour is the dangerous one, because it looks exactly
# like a pass. Copying the file and its sidecars out and opening the copy
# read-write replays the log exactly as crash recovery would, which is the
# claim the whole design rests on.
#
# The subject is discovered rather than named, so this keeps working when the
# smallest database on the host changes. This is the only test in the suite
# that writes anything on the host: a scratch directory it creates, uses, and
# removes, whose removal is then asserted rather than assumed.

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
SERVICES_NIX="./hosts/ser8/backup/services.nix"

# Where each covered service's state is mounted, and therefore where its own
# snapshot view hangs off
LIVE_STATE_ROOT="/var/lib"

# The single token a clean structural check returns. Anything else, including a
# description of the first problem found, is a failure.
EXPECTED_TOKEN="ok"

tests_run=0
tests_passed=0

# Set by test_spot_check for the cleanup assertion that follows it
scratch_path=""

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

# The short name of the newest nightly snapshot of the tree, or empty output.
newest_nightly_name() {
	remote zfs list -H -p -t snapshot -o name,creation -s creation "$DS_ROOT" |
		awk -F'\t' -v ds="$DS_ROOT" '
			index($1, ds "@autosnap_") == 1 && $1 ~ /_daily$/ { newest = $1 }
			END { if (newest != "") { sub(/^[^@]*@/, "", newest); print newest } }
		'
}

# The declared covered-service set, one name per line, or empty output.
covered_services() {
	nix eval --raw --file "$SERVICES_NIX" \
		--apply 'set: builtins.concatStringsSep "\n" (builtins.attrNames set)' 2>/dev/null ||
		echo ""
}

# The first database found inside the newest snapshot, searched in declared
# service order so the same host picks the same subject on every run.
#
# The sidecars cannot match the search: they carry their suffix after the
# extension, so a write-ahead log named foo.db-wal is not foo.db.
find_snapshot_database() {
	local snapshot="$1"
	shift
	# The loop variables are expanded by the remote shell, not this one.
	# shellcheck disable=SC2016
	remote sudo sh -c '
		snap="$1"
		root="$2"
		shift 2
		for svc in "$@"; do
			view="$root/$svc/.zfs/snapshot/$snap"
			[ -d "$view" ] || continue
			found=$(find "$view" -type f \
				\( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
				2>/dev/null | LC_ALL=C sort | head -1)
			if [ -n "$found" ]; then
				printf "%s\n" "$found"
				exit 0
			fi
		done
		exit 0
	' _ "$snapshot" "$LIVE_STATE_ROOT" "$@"
}

# Test 1: a database can be found inside the newest snapshot
#
# Nothing to check is a failure, not a skip. A host whose snapshot contains no
# database at all has either lost its state or never captured it, and either
# way this suite must not go green.
test_subject_discoverable() {
	info "checking that the newest snapshot contains a database to check"

	local snapshot
	snapshot=$(newest_nightly_name)
	if [ -z "$snapshot" ]; then
		fail "no nightly snapshot of '$DS_ROOT' on $host"
		return 1
	fi

	local services
	services=$(covered_services)
	if [ -z "$services" ]; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	local service_list=()
	local svc
	while IFS= read -r svc; do
		[ -n "$svc" ] || continue
		service_list+=("$svc")
	done <<<"$services"

	local database
	database=$(find_snapshot_database "$snapshot" "${service_list[@]}")

	if [ -z "$database" ]; then
		fail "no database found inside snapshot '$snapshot' on $host"
		fail "  searched ${#service_list[@]} covered service view(s) under $LIVE_STATE_ROOT"
		return 1
	fi

	pass "found '$(fmt_bold "$database")' inside snapshot '$snapshot'"
	return 0
}

# Test 2: that database opens clean when recovered the way a restore would
test_spot_check() {
	info "running a structural check on a copy taken out of the snapshot"

	local snapshot
	snapshot=$(newest_nightly_name)
	if [ -z "$snapshot" ]; then
		fail "no nightly snapshot of '$DS_ROOT' on $host"
		return 1
	fi

	local services
	services=$(covered_services)
	if [ -z "$services" ]; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	local service_list=()
	local svc
	while IFS= read -r svc; do
		[ -n "$svc" ] || continue
		service_list+=("$svc")
	done <<<"$services"

	local database
	database=$(find_snapshot_database "$snapshot" "${service_list[@]}")
	if [ -z "$database" ]; then
		fail "no database found inside snapshot '$snapshot' on $host"
		return 1
	fi

	# The snapshot preserves the live mode, which is usually writable by
	# nobody but the owning service, so the copy needs its mode relaxed before
	# the replay can write to it.
	local output
	# The database path and scratch directory are expanded by the remote
	# shell, not this one.
	# shellcheck disable=SC2016
	output=$(remote sudo sh -c '
		db="$1"
		scratch=$(mktemp -d) || exit 1
		printf "SCRATCH %s\n" "$scratch"
		if ! cp -- "$db" "$scratch/db"; then
			rm -rf -- "$scratch"
			exit 1
		fi
		if [ -e "$db-wal" ]; then cp -- "$db-wal" "$scratch/db-wal"; fi
		if [ -e "$db-shm" ]; then cp -- "$db-shm" "$scratch/db-shm"; fi
		chmod -R u+w -- "$scratch"
		printf "RESULT %s\n" "$(sqlite3 "$scratch/db" "PRAGMA integrity_check;" 2>&1 | head -1)"
		rm -rf -- "$scratch"
	' _ "$database")

	if [ -z "$output" ]; then
		fail "the structural check did not run on $host"
		fail "  could not copy '$database' out of the snapshot"
		return 1
	fi

	scratch_path=$(printf '%s\n' "$output" | awk '$1 == "SCRATCH" { print $2; exit }')

	local result
	result=$(printf '%s\n' "$output" | awk '$1 == "RESULT" { sub(/^RESULT /, ""); print; exit }')

	if [ -z "$result" ]; then
		fail "the structural check produced no result for '$database' on $host"
		fail "  the copy was made but the check never reported"
		return 1
	fi

	if [ "$result" != "$EXPECTED_TOKEN" ]; then
		fail "'$database' failed its structural check"
		fail "  $result"
		fail "  this database would not survive a restore from snapshot '$snapshot'"
		return 1
	fi

	pass "'$(fmt_bold "$database")' passed its structural check out of snapshot '$snapshot'"
	return 0
}

# Test 3: the scratch copy was removed
#
# Asserted rather than assumed. This suite's contract is that it does not
# change the host it inspects, and the one test that writes anything is the one
# place that contract can break.
test_scratch_removed() {
	info "checking that the scratch copy was removed from $host"

	if [ -z "$scratch_path" ]; then
		fail "the structural check reported no scratch path, so its cleanup cannot be verified"
		return 1
	fi

	local state
	# The path is expanded by the remote shell, not this one.
	# shellcheck disable=SC2016
	state=$(remote sh -c 'if [ -e "$1" ]; then echo present; else echo absent; fi' _ "$scratch_path")

	if [ -z "$state" ]; then
		fail "could not check whether '$scratch_path' still exists on $host"
		return 1
	fi

	if [ "$state" != "absent" ]; then
		fail "the scratch copy '$scratch_path' is still on $host"
		fail "  it holds a readable copy of service state and must be removed"
		return 1
	fi

	pass "the scratch copy was removed"
	return 0
}

echo
info "=== Spot Integrity Tests ==="
run_test "subject_discoverable" test_subject_discoverable || true
run_test "spot_check" test_spot_check || true
run_test "scratch_removed" test_scratch_removed || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run spot integrity tests passed"
else
	fail "$tests_passed/$tests_run spot integrity tests passed"
	exit 1
fi
