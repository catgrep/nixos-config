#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Stale persisted directory smoketest for ser8.
#
# Each covered service used to keep its state in a directory under the
# persisted tree that was bind-mounted into place at boot. Giving the service a
# dataset of its own replaces that arrangement, and the dataset now mounts
# directly where the service expects it.
#
# Removing the bind entry does not remove the directory it used to bind. The
# old copy simply stops being mounted anywhere and stays on disk: it doubles
# the service's footprint, it is captured by every snapshot from then on so it
# doubles the snapshot churn too, and it is a trap for the next person who
# greps for a state directory and finds two -- one live, one frozen at the
# moment of the migration, with nothing to say which is which.
#
# The check derives its list from the declared covered-service set, so a
# service migrated later is checked without editing this file.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Where the bind sources used to live. Anything still here that names a covered
# service is a leftover, not a backing store.
OLD_STATE_ROOT="/persist/var/lib"

# Where each service's dataset mounts now
LIVE_STATE_ROOT="/var/lib"

SERVICES_NIX="./hosts/ser8/backup/services.nix"

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

# The declared covered-service set, one name per line, or empty output.
covered_services() {
	nix eval --raw --file "$SERVICES_NIX" \
		--apply 'set: builtins.concatStringsSep "\n" (builtins.attrNames set)' 2>/dev/null ||
		echo ""
}

# The declared set as an array, or a non-zero return when it cannot be read.
read_service_list() {
	local services
	services=$(covered_services)
	[ -n "$services" ] || return 1

	service_list=()
	local svc
	while IFS= read -r svc; do
		[ -n "$svc" ] || continue
		service_list+=("$svc")
	done <<<"$services"
	[ "${#service_list[@]}" -gt 0 ]
}

# Test 1: no covered service still has a directory under the old root
#
# The remote loop prints a count when it finishes, so a loop that never ran is
# distinguishable from one that ran and found nothing. Without that sentinel,
# silence would mean both "clean" and "the command did not execute", and the
# second would pass.
test_no_stale_directories() {
	info "checking for leftover state directories under '$(fmt_bold "$OLD_STATE_ROOT")'"

	local service_list=()
	if ! read_service_list; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	local output
	# The loop variables are expanded by the remote shell, not this one.
	# shellcheck disable=SC2016
	output=$(remote sudo sh -c '
		root="$1"
		shift
		checked=0
		for svc in "$@"; do
			checked=$((checked + 1))
			if [ -e "$root/$svc" ]; then
				echo "STALE $root/$svc"
			fi
		done
		echo "CHECKED $checked"
	' _ "$OLD_STATE_ROOT" "${service_list[@]}")

	if [ -z "$output" ]; then
		fail "could not check '$OLD_STATE_ROOT' on $host"
		return 1
	fi

	local checked
	checked=$(printf '%s\n' "$output" | awk '$1 == "CHECKED" { print $2; exit }')

	if [ -z "$checked" ] || [ "$checked" -ne "${#service_list[@]}" ]; then
		fail "the leftover check did not cover every service on $host"
		fail "  checked='$checked' expected='${#service_list[@]}'"
		return 1
	fi

	local stale
	stale=$(printf '%s\n' "$output" | grep '^STALE ' || true)

	if [ -n "$stale" ]; then
		local count
		count=$(printf '%s\n' "$stale" | grep -c .)
		fail "$count leftover state director(ies) remain under $OLD_STATE_ROOT"
		local entry
		while IFS= read -r entry; do
			[ -n "$entry" ] || continue
			fail "  ${entry#STALE }"
		done <<<"$stale"
		fail "  these are frozen copies from before the migration, not backing stores"
		return 1
	fi

	pass "no leftover state directory remains for any of the $checked covered services"
	return 0
}

# Test 2: every covered service's live path is its own dataset
#
# The mirror image of the assertion above, and needed alongside it. An absent
# leftover proves the old copy is gone; it does not prove the replacement is
# there. Together they say the migration completed rather than merely started,
# because a path that is a plain directory on the parent dataset would satisfy
# the first test while having no dataset, no separate snapshot, and no
# per-service restore.
test_live_paths_are_datasets() {
	info "checking that every covered service's live path is its own dataset"

	local service_list=()
	if ! read_service_list; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	local mounts
	mounts=$(remote findmnt -rn -t zfs -o TARGET)

	if [ -z "$mounts" ]; then
		fail "could not list the mounted filesystems on $host"
		return 1
	fi

	local missing=()
	local svc
	for svc in "${service_list[@]}"; do
		if ! printf '%s\n' "$mounts" | grep -qxF "$LIVE_STATE_ROOT/$svc"; then
			missing+=("$LIVE_STATE_ROOT/$svc")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		fail "${#missing[@]} covered service path(s) are not a mounted dataset"
		local entry
		for entry in "${missing[@]}"; do
			fail "  $entry"
		done
		fail "  the state is riding in the parent dataset with no granularity of its own"
		return 1
	fi

	pass "all ${#service_list[@]} covered service paths are mounted datasets"
	return 0
}

echo
info "=== Leftover Directory Tests ==="
run_test "no_stale_directories" test_no_stale_directories || true

echo
info "=== Live Path Tests ==="
run_test "live_paths_are_datasets" test_live_paths_are_datasets || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run leftover directory tests passed"
else
	fail "$tests_passed/$tests_run leftover directory tests passed"
	exit 1
fi
