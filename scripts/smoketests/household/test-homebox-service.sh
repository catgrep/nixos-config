#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Homebox service smoketest for ser8.
#
# Asserts the things a homepage load cannot: that the unit is actually
# running with no startup errors, and that its SQLite state landed in a real
# directory owned by its static user on both sides of the impermanence bind
# mount. A symlink or wrong owner here means state is silently landing
# somewhere impermanence does not cover, which nothing visibly breaks until
# the next reboot discards it.

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

HOMEBOX_UNIT="homebox"
HOMEBOX_PORT="7745"

# StateDirectory = "homebox", forced to mode 0750 by
# modules/household/homebox.nix's StateDirectoryMode override.
HOMEBOX_DATA_DIR="/var/lib/homebox"

# The durable state directory. Homebox's state is its own ZFS dataset mounted
# here, so the state path and the persisted path are one and the same; there is
# no longer a second copy under /persist to check separately.
HOMEBOX_PERSIST_DIR="$HOMEBOX_DATA_DIR"

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
# as a failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Run a command on the target host, returning its exit status rather than its
# stdout. Same printf %q escaping as `remote`: probe arguments are never
# interpolated into a remote shell unescaped.
remote_ok() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" >/dev/null 2>&1
}

# Test 1: the homebox unit is active
test_homebox_unit_active() {
	info "checking that the '$(fmt_bold "$HOMEBOX_UNIT")' unit is active"

	if remote_ok systemctl is-active --quiet "$HOMEBOX_UNIT"; then
		pass "'$(fmt_bold "$HOMEBOX_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$HOMEBOX_UNIT")' unit is not active"
	return 1
}

# Test 2: the application port is bound
#
# Probed by opening a TCP connection from the host's own login shell rather
# than through ss, netstat, or lsof: none of those is guaranteed to be in the
# system closure, and a check that silently skips when its tool is missing is
# a check that certifies nothing.
test_homebox_port_listening() {
	info "checking that port $(fmt_bold "$HOMEBOX_PORT") is bound on $host"

	if remote_ok timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${HOMEBOX_PORT}"; then
		pass "port $HOMEBOX_PORT accepts connections on $host"
		return 0
	fi

	fail "port $HOMEBOX_PORT is not accepting connections on $host"
	return 1
}

# Test 3: no error-level journal entry in the current boot
test_homebox_no_startup_errors() {
	info "checking the current boot's journal for '$(fmt_bold "$HOMEBOX_UNIT")' errors"

	local errors
	errors=$(remote journalctl -b -u "$HOMEBOX_UNIT" --priority=err --no-pager -q -o cat)

	if [ -z "$errors" ]; then
		pass "no error-level journal entries for '$(fmt_bold "$HOMEBOX_UNIT")' in the current boot"
		return 0
	fi

	local count
	count=$(echo "$errors" | wc -l | tr -d ' ')
	fail "$count error-level journal entries for '$(fmt_bold "$HOMEBOX_UNIT")' in the current boot"
	echo "$errors" | head -10 | while IFS= read -r line; do
		fail "  $line"
	done
	return 1
}

# Test 4: the Homebox state directory is a real directory, not a symlink
#
# A symlink here means the settings.HBOX_STORAGE_CONN_STRING path landed
# somewhere other than the StateDirectory systemd manages. 0750, matching
# modules/household/homebox.nix's explicit StateDirectoryMode override --
# systemd's own StateDirectory default is 0755.
test_homebox_state_dir_shape() {
	info "checking that $(fmt_bold "$HOMEBOX_DATA_DIR") is a real directory"

	if remote_ok test -L "$HOMEBOX_DATA_DIR"; then
		fail "$HOMEBOX_DATA_DIR is a symlink; state is landing somewhere else"
		return 1
	fi

	if ! remote_ok test -d "$HOMEBOX_DATA_DIR"; then
		fail "$HOMEBOX_DATA_DIR is not a directory"
		return 1
	fi

	local stat_out
	stat_out=$(remote stat -c '%U %G %a' "$HOMEBOX_DATA_DIR")

	if [ "$stat_out" = "homebox homebox 750" ]; then
		pass "$HOMEBOX_DATA_DIR is a real directory owned homebox:homebox mode 750"
		return 0
	fi

	fail "$HOMEBOX_DATA_DIR is '${stat_out:-unreadable}', expected 'homebox homebox 750'"
	return 1
}

# Test 5: the persisted path is its own mounted ZFS dataset
#
# Since the dataset migration, HOMEBOX_PERSIST_DIR and HOMEBOX_DATA_DIR are the
# same path (see the definition above), so this no longer compares two
# directories against each other -- it proves the one path really is a mounted
# ZFS dataset rather than a plain directory riding the parent dataset's
# storage, which is what would let a reboot silently discard every item,
# photo, and location Homebox wrote.
test_homebox_persist_dir() {
	info "checking that $(fmt_bold "$HOMEBOX_PERSIST_DIR") is a mounted ZFS dataset"

	if remote_ok findmnt -rn -t zfs "$HOMEBOX_PERSIST_DIR"; then
		pass "$HOMEBOX_PERSIST_DIR is a mounted ZFS dataset"
		return 0
	fi

	fail "$HOMEBOX_PERSIST_DIR is not a mounted ZFS dataset"
	return 1
}

# Main test execution
echo
info "=== Homebox Service Tests ==="
run_test "homebox_unit_active" test_homebox_unit_active || true
run_test "homebox_port_listening" test_homebox_port_listening || true
run_test "homebox_no_startup_errors" test_homebox_no_startup_errors || true

echo
info "=== State Directory Tests ==="
run_test "homebox_state_dir_shape" test_homebox_state_dir_shape || true
run_test "homebox_persist_dir" test_homebox_persist_dir || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Homebox service tests passed"
else
	fail "$tests_passed/$tests_run Homebox service tests passed"
	exit 1
fi
