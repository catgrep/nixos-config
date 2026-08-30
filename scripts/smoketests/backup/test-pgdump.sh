#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Database archive smoketest for ser8.
#
# A crash-consistent copy of a database's data directory only restores into the
# same server version with the same binaries on the same architecture. The
# portable archive is what decouples the backup from the machine that made it,
# so its absence is a silent downgrade of what a restore can actually do -- the
# snapshot still looks complete, and it is, right up until the restore target
# is not an identical host.
#
# The expected list comes from the live catalog rather than from a constant
# here, so a database created by a service added later is checked from the
# first night it exists. A hardcoded list would go green while ignoring it.
#
# Everything is read out of the newest snapshot rather than out of the live
# directory, because an archive that exists only outside the snapshot is an
# archive no restore can reach.

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

# The dump directory lives on the parent dataset, so its snapshot view hangs
# off the parent's mountpoint rather than off any service's.
PERSIST_MOUNT="/persist"
DUMP_SUBPATH="var/lib/backup-dumps"

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

# The short name of the newest nightly snapshot of the tree, or empty output.
newest_nightly_name() {
	remote zfs list -H -p -t snapshot -o name,creation -s creation "$DS_ROOT" |
		awk -F'\t' -v ds="$DS_ROOT" '
			index($1, ds "@autosnap_") == 1 && $1 ~ /_daily$/ { newest = $1 }
			END { if (newest != "") { sub(/^[^@]*@/, "", newest); print newest } }
		'
}

# The directory inside the newest snapshot that holds the archives.
dump_view() {
	local snapshot="$1"
	printf '%s/.zfs/snapshot/%s/%s' "$PERSIST_MOUNT" "$snapshot" "$DUMP_SUBPATH"
}

# Every database the live catalog reports, excluding templates and anything
# that refuses connections. One name per line, or empty output on any failure.
catalog_databases() {
	remote sudo -u postgres psql -At -c \
		"select datname from pg_database where not datistemplate and datallowconn order by datname"
}

# Test 1: the snapshot contains an archive for every database in the catalog
test_every_database_archived() {
	info "checking that the newest snapshot carries an archive per database"

	local snapshot
	snapshot=$(newest_nightly_name)
	if [ -z "$snapshot" ]; then
		fail "no nightly snapshot of '$DS_ROOT' on $host, so no archives can be read"
		return 1
	fi

	local expected
	expected=$(catalog_databases)
	if [ -z "$expected" ]; then
		fail "could not read the database catalog from $host"
		fail "  the server is down, or the deploy user cannot reach it"
		return 1
	fi

	local view present
	view=$(dump_view "$snapshot")
	present=$(remote sudo ls -1 "$view")

	if [ -z "$present" ]; then
		fail "the archive directory '$view' is empty or unreadable on $host"
		fail "  no archive rode inside the newest snapshot"
		return 1
	fi

	local missing=()
	local db
	while IFS= read -r db; do
		[ -n "$db" ] || continue
		if ! printf '%s\n' "$present" | grep -qxF "$db.dump"; then
			missing+=("$db")
		fi
	done <<<"$expected"

	if [ "${#missing[@]}" -gt 0 ]; then
		fail "${#missing[@]} database(s) have no archive in snapshot '$snapshot'"
		local entry
		for entry in "${missing[@]}"; do
			fail "  $entry (expected $view/$entry.dump)"
		done
		return 1
	fi

	local count
	count=$(printf '%s\n' "$expected" | grep -c .)
	pass "all $count catalog database(s) have an archive in snapshot '$(fmt_bold "$snapshot")'"
	return 0
}

# Test 2: the cluster-wide role and permission dump rode along too
#
# Restoring the per-database archives into a server with no roles produces
# tables nobody can read. This file is small enough to overlook and load
# bearing enough that its absence turns a restore into a second outage.
test_globals_present() {
	info "checking that the cluster-wide role dump is in the newest snapshot"

	local snapshot
	snapshot=$(newest_nightly_name)
	if [ -z "$snapshot" ]; then
		fail "no nightly snapshot of '$DS_ROOT' on $host"
		return 1
	fi

	local view size
	view=$(dump_view "$snapshot")
	size=$(remote sudo stat -c %s "$view/globals.sql")

	if [ -z "$size" ]; then
		fail "'$view/globals.sql' is missing or unreadable on $host"
		return 1
	fi

	case "$size" in
	*[!0-9]*)
		fail "unparseable size for '$view/globals.sql': '$size'"
		return 1
		;;
	esac

	if [ "$size" -eq 0 ]; then
		fail "'$view/globals.sql' is empty; a restore would recreate no roles at all"
		return 1
	fi

	pass "the cluster-wide role dump is present ($size bytes)"
	return 0
}

# Test 3: every archive in the snapshot is structurally listable
#
# A truncated archive is the failure mode worth catching: it exists, it has a
# plausible size, and it is unusable. Listing its table of contents is the
# cheapest operation that has to read the archive's own structure to answer.
#
# The remote loop prints a sentinel when it finishes, so a loop that never ran
# is distinguishable from one that ran and found nothing wrong. Without it,
# silence would mean both "every archive is fine" and "the command did not
# execute", and the second would pass.
test_archives_listable() {
	info "checking that every archive in the newest snapshot is listable"

	local snapshot
	snapshot=$(newest_nightly_name)
	if [ -z "$snapshot" ]; then
		fail "no nightly snapshot of '$DS_ROOT' on $host"
		return 1
	fi

	local view output
	view=$(dump_view "$snapshot")
	# The loop variables are expanded by the remote shell, not this one.
	# shellcheck disable=SC2016
	output=$(remote sudo sh -c '
		checked=0
		for f in "$1"/*.dump; do
			[ -e "$f" ] || continue
			checked=$((checked + 1))
			pg_restore --list "$f" >/dev/null 2>&1 || echo "UNLISTABLE $f"
		done
		echo "CHECKED $checked"
	' _ "$view")

	if [ -z "$output" ]; then
		fail "could not list the archives under '$view' on $host"
		return 1
	fi

	local checked
	checked=$(printf '%s\n' "$output" | awk '$1 == "CHECKED" { print $2; exit }')

	if [ -z "$checked" ]; then
		fail "the archive check did not run to completion on $host"
		fail "  output: $(printf '%s' "$output" | tr '\n' ' ')"
		return 1
	fi

	if [ "$checked" -eq 0 ]; then
		fail "no archive was found under '$view' on $host"
		return 1
	fi

	local unlistable
	unlistable=$(printf '%s\n' "$output" | grep '^UNLISTABLE ' || true)

	if [ -n "$unlistable" ]; then
		fail "one or more archives in snapshot '$snapshot' cannot be listed"
		local entry
		while IFS= read -r entry; do
			[ -n "$entry" ] || continue
			fail "  ${entry#UNLISTABLE }"
		done <<<"$unlistable"
		return 1
	fi

	pass "all $checked archive(s) in snapshot '$(fmt_bold "$snapshot")' are listable"
	return 0
}

echo
info "=== Archive Presence Tests ==="
run_test "every_database_archived" test_every_database_archived || true
run_test "globals_present" test_globals_present || true

echo
info "=== Archive Structure Tests ==="
run_test "archives_listable" test_archives_listable || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run database archive tests passed"
else
	fail "$tests_passed/$tests_run database archive tests passed"
	exit 1
fi
