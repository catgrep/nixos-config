#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ZFS media storage smoketest for ser8.
#
# Validates the media zpool mirror that replaced the old ext4 + MergerFS
# pair: native ZFS mount (not fuse.mergerfs), pool health, mirror membership
# by the two approved disk WWNs, canonical library directories, media-group
# read access, and an import-write check confirming files written under
# /mnt/media land with the correct owner and can be cleaned up.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Approved disk WWNs (hosts/ser8/disko-config.nix, media zpool)
APPROVED_WWN_1="wwn-0x5000c500b56ea81a"
APPROVED_WWN_2="wwn-0x5000c500b3733a87"

MEDIA_POOL="media"
MEDIA_MOUNT="/mnt/media"
# Shared media account uid, pinned in modules/common/users.nix
MEDIA_UID="1100"

# Track test results
tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	((tests_run += 1))
	if "$test_func" "$@"; then
		((tests_passed += 1))
		return 0
	fi
	warn "test failed: $test_name"
	return 1
}

# Run a command on the target host, returning its stdout. Empty output means
# the command could not be run or produced nothing; every caller treats that
# as a failure rather than as an inconclusive result, except where a test
# explicitly expects empty output to mean "no problems found".
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Test 1: mount source is native ZFS, not fuse.mergerfs
test_mount_type() {
	info "checking mount type of $(fmt_bold "$MEDIA_MOUNT")"

	local mount_info
	mount_info=$(remote mount | grep "$MEDIA_MOUNT ")

	if [ -z "$mount_info" ]; then
		fail "$MEDIA_MOUNT is not mounted on $host"
		return 1
	fi

	if echo "$mount_info" | grep -q 'type zfs'; then
		pass "$MEDIA_MOUNT is mounted as ZFS (not mergerfs)"
		return 0
	fi

	fail "$MEDIA_MOUNT is not a ZFS mount (found: $mount_info)"
	return 1
}

# Test 2: pool is online and healthy
test_pool_online() {
	info "checking ZFS pool '$(fmt_bold "$MEDIA_POOL")' health"

	local status
	status=$(remote zpool status -x "$MEDIA_POOL")

	if [ -z "$status" ]; then
		fail "could not read 'zpool status -x $MEDIA_POOL' from $host"
		return 1
	fi

	if echo "$status" | grep -qE "pool '$MEDIA_POOL' is healthy|all pools are healthy"; then
		pass "ZFS pool '$(fmt_bold "$MEDIA_POOL")' is healthy"
		return 0
	fi

	fail "ZFS pool '$(fmt_bold "$MEDIA_POOL")' is NOT healthy"
	fail "  $(echo "$status" | tr '\n' ' ')"
	return 1
}

# Test 3: mirror membership by the two approved WWNs
test_mirror_members() {
	info "checking mirror membership against the approved disk inventory"

	local status
	status=$(remote zpool status "$MEDIA_POOL")

	if [ -z "$status" ]; then
		fail "could not read 'zpool status $MEDIA_POOL' from $host"
		return 1
	fi

	local missing=0
	if ! echo "$status" | grep -q "$APPROVED_WWN_1"; then
		fail "Mirror missing approved disk $APPROVED_WWN_1"
		missing=1
	fi
	if ! echo "$status" | grep -q "$APPROVED_WWN_2"; then
		fail "Mirror missing approved disk $APPROVED_WWN_2"
		missing=1
	fi

	if [ "$missing" -eq 0 ]; then
		pass "Mirror membership verified (both approved WWNs present)"
		return 0
	fi
	return 1
}

# Test 4: canonical library directories exist
test_canonical_dirs() {
	info "checking canonical library directories under $(fmt_bold "$MEDIA_MOUNT")"

	local dir
	for dir in movies tv books music; do
		# remote() reconstructs each argument as a separate shell word on the
		# remote end, so "&&" cannot be passed as a bare argument here (it
		# would arrive as a literal, non-operator token) -- wrap the
		# conditional in sh -c instead, matching test_import_write below.
		# $1 must stay single-quoted so it expands on the remote shell, not
		# the local one.
		# shellcheck disable=SC2016
		if [ "$(remote sh -c 'test -d "$1" && echo present' -- "$MEDIA_MOUNT/$dir")" != "present" ]; then
			fail "Missing $MEDIA_MOUNT/$dir"
			return 1
		fi
	done

	pass "All canonical directories exist ($MEDIA_MOUNT/{movies,tv,books,music})"
	return 0
}

# Test 5: media group can read the canonical libraries
test_service_access() {
	info "checking media-group read access to all canonical libraries"

	# Empty output here means "no directory failed the check" -- a real pass,
	# not an unreachable-host signal (find always exits 0 on a reachable host,
	# with or without matches).
	local bad_path
	bad_path=$(remote find "$MEDIA_MOUNT/movies" "$MEDIA_MOUNT/tv" \
		"$MEDIA_MOUNT/books" "$MEDIA_MOUNT/music" -maxdepth 0 \
		'(' ! -group media -o ! -perm -g+rx ')' -print)

	if [ -n "$bad_path" ]; then
		fail "Directory not readable by the media group: $bad_path"
		return 1
	fi

	pass "media group can read $MEDIA_MOUNT/movies and $MEDIA_MOUNT/tv"
	return 0
}

# Test 6: import-write test (D-22, replaces the old cross-directory hardlink
# check now that torrents -- and the hardlink requirement -- are retired)
test_import_write() {
	info "import-write test: file lands with uid $MEDIA_UID and is removable"

	# $f and $$ must stay single-quoted so they expand on the remote shell
	# (as the remote-side PID), not the local one.
	local result
	# shellcheck disable=SC2016
	result=$(remote sudo -n -u media sh -c \
		'f="/mnt/media/.smoketest-import-write-$$"; echo smoketest >"$f" && stat -c%u "$f" && rm -f "$f"')

	if [ "$result" != "$MEDIA_UID" ]; then
		fail "Import-write test file did not land with uid $MEDIA_UID (got: '$result')"
		return 1
	fi

	pass "Import-write test file landed with uid $MEDIA_UID and was removed"
	return 0
}

# Main test execution
echo
info "=== ZFS Media Pool Tests ==="
run_test "mount_type" test_mount_type || true
run_test "pool_online" test_pool_online || true
run_test "mirror_members" test_mirror_members || true

echo
info "=== Media Library Tests ==="
run_test "canonical_dirs" test_canonical_dirs || true
run_test "service_access" test_service_access || true
run_test "import_write" test_import_write || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run ZFS media tests passed"
else
	fail "$tests_passed/$tests_run ZFS media tests passed"
	exit 1
fi
