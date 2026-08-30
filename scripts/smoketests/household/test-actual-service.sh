#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Actual Budget service smoketest for ser8.
#
# Asserts the things a homepage load cannot: that the unit is actually
# running with no startup errors, that its SQLite state landed in a real
# directory owned by its static user on both sides of the impermanence bind
# mount, and -- the check this plan exists for -- that exactly one
# unencrypted budget file exists in account.sqlite. That last check is the
# proof ACT-02 asked for: it is drawn from the server's own database rather
# than trusted from a human report of a browser click.
#
# ACTUAL_ALLOW_UNSEEDED
# ----------------------
# The budget-file assertion is ON by default. Setting ACTUAL_ALLOW_UNSEEDED=1
# downgrades it to informational output, and exists for exactly one run: a
# pre-bootstrap activation before any budget file has been created through the
# web UI. It must be passed on the command line for that single run.
#
# Nothing committed to this repository may set it. Setting it in deploy.yaml,
# in scripts/smoketests/ser8/all.sh, or in scripts/smoketests/household/all.sh
# would turn a real deployment gate into an always-passing one -- the same
# failure MEALIE_ALLOW_UNSEEDED exists to prevent for Mealie.

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

ACTUAL_UNIT="actual"
ACTUAL_PORT="3000"

# settings.dataDir, left at the module's own default (modules/household/actual.nix)
ACTUAL_DATA_DIR="/var/lib/actual"

# The durable state directory. Actual's state is its own ZFS dataset mounted
# here, so the state path and the persisted path are one and the same; there is
# no longer a second copy under /persist to check separately.
ACTUAL_PERSIST_DIR="$ACTUAL_DATA_DIR"

# The single point of truth for ACT-02: settings.serverFiles/account.sqlite
ACTUAL_ACCOUNT_DB="/var/lib/actual/server-files/account.sqlite"

# Unset by default and unset in every committed file. See the header.
ACTUAL_ALLOW_UNSEEDED="${ACTUAL_ALLOW_UNSEEDED:-0}"

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

# Report a zero/missing count. Fails by default; reports informational only
# when the operator passed ACTUAL_ALLOW_UNSEEDED=1 for a pre-bootstrap run.
report_empty() {
	local what="$1"
	if [ "$ACTUAL_ALLOW_UNSEEDED" = "1" ]; then
		info "$what (ACTUAL_ALLOW_UNSEEDED=1, pre-bootstrap run)"
		return 0
	fi
	fail "$what"
	return 1
}

# Test 1: the actual unit is active
test_actual_unit_active() {
	info "checking that the '$(fmt_bold "$ACTUAL_UNIT")' unit is active"

	if remote_ok systemctl is-active --quiet "$ACTUAL_UNIT"; then
		pass "'$(fmt_bold "$ACTUAL_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$ACTUAL_UNIT")' unit is not active"
	return 1
}

# Test 2: the application port is bound
#
# Probed by opening a TCP connection from the host's own login shell rather
# than through ss, netstat, or lsof: none of those is guaranteed to be in the
# system closure, and a check that silently skips when its tool is missing is
# a check that certifies nothing.
test_actual_port_listening() {
	info "checking that port $(fmt_bold "$ACTUAL_PORT") is bound on $host"

	if remote_ok timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${ACTUAL_PORT}"; then
		pass "port $ACTUAL_PORT accepts connections on $host"
		return 0
	fi

	fail "port $ACTUAL_PORT is not accepting connections on $host"
	return 1
}

# Test 3: no error-level journal entry in the unit's current invocation
#
# Scoped to `--invocation=0` (the unit's current start) rather than `-b` (the
# whole boot). NixOS activations happen without a reboot, so a boot-scoped
# check keeps reporting a failed earlier generation's startup error as
# evidence about a later, successfully-fixed one -- exactly the false
# positive this plan's own deploy history produced (a pre-persist-fix
# mount-namespacing failure that predates this activation but shares its
# boot). Scoping to the invocation is what "an error from a previous
# generation is not carried forward" actually requires without a reboot.
test_actual_no_startup_errors() {
	info "checking the current invocation's journal for '$(fmt_bold "$ACTUAL_UNIT")' errors"

	local errors
	errors=$(remote sudo journalctl -u "$ACTUAL_UNIT" --priority=err --no-pager -q -o cat --invocation=0)

	if [ -z "$errors" ]; then
		pass "no error-level journal entries for '$(fmt_bold "$ACTUAL_UNIT")' in the current invocation"
		return 0
	fi

	local count
	count=$(echo "$errors" | wc -l | tr -d ' ')
	fail "$count error-level journal entries for '$(fmt_bold "$ACTUAL_UNIT")' in the current invocation"
	echo "$errors" | head -10 | while IFS= read -r line; do
		fail "  $line"
	done
	return 1
}

# Test 4: the Actual state directory is a real directory, not a symlink
#
# A symlink here means the static-user override in
# modules/household/actual.nix did not take effect and state is landing in
# /var/lib/private instead. 0700, matching services.actual's own
# StateDirectoryMode.
test_actual_state_dir_shape() {
	info "checking that $(fmt_bold "$ACTUAL_DATA_DIR") is a real directory"

	if remote_ok test -L "$ACTUAL_DATA_DIR"; then
		fail "$ACTUAL_DATA_DIR is a symlink; state is landing in the private state tree"
		return 1
	fi

	if ! remote_ok test -d "$ACTUAL_DATA_DIR"; then
		fail "$ACTUAL_DATA_DIR is not a directory"
		return 1
	fi

	local stat_out
	stat_out=$(remote stat -c '%U %G %a' "$ACTUAL_DATA_DIR")

	if [ "$stat_out" = "actual actual 700" ]; then
		pass "$ACTUAL_DATA_DIR is a real directory owned actual:actual mode 700"
		return 0
	fi

	fail "$ACTUAL_DATA_DIR is '${stat_out:-unreadable}', expected 'actual actual 700'"
	return 1
}

# Test 5: the persisted path is its own mounted ZFS dataset
#
# Since the dataset migration, ACTUAL_PERSIST_DIR and ACTUAL_DATA_DIR are the
# same path (see the definition above), so this no longer compares two
# directories against each other -- it proves the one path really is a mounted
# ZFS dataset rather than a plain directory riding the parent dataset's
# storage, which is what would let a reboot silently discard the one budget
# file this plan just proved exists.
test_actual_persist_dir() {
	info "checking that $(fmt_bold "$ACTUAL_PERSIST_DIR") is a mounted ZFS dataset"

	if remote_ok findmnt -rn -t zfs "$ACTUAL_PERSIST_DIR"; then
		pass "$ACTUAL_PERSIST_DIR is a mounted ZFS dataset"
		return 0
	fi

	fail "$ACTUAL_PERSIST_DIR is not a mounted ZFS dataset"
	return 1
}

# Test 6: exactly one non-deleted, unencrypted budget file (ACT-02)
#
# The proof this plan exists to produce: queried directly from account.sqlite
# rather than trusted from the checkpoint's human report. Zero rows means the
# wizard did not complete; more than one means a duplicate was created from a
# mis-click or a race -- neither counts as a pass.
test_actual_budget_file_unencrypted() {
	info "checking $(fmt_bold "$ACTUAL_ACCOUNT_DB") for exactly one unencrypted budget file"

	local row
	row=$(remote sudo sqlite3 "$ACTUAL_ACCOUNT_DB" \
		"SELECT count(*), group_concat(encrypt_keyid) FROM files WHERE deleted=0")

	local count keyids
	count="${row%%|*}"
	keyids="${row#*|}"

	if [ -z "$count" ]; then
		report_empty "could not query $ACTUAL_ACCOUNT_DB (account.sqlite unreadable or missing)"
		return $?
	fi

	if [ "$count" = "0" ]; then
		report_empty "no non-deleted budget file exists in account.sqlite"
		return $?
	fi

	if [ "$count" != "1" ]; then
		fail "account.sqlite has $count non-deleted budget files, expected exactly 1"
		return 1
	fi

	if [ -n "$keyids" ]; then
		fail "the budget file has a non-empty encrypt_keyid ('$keyids'); end-to-end encryption is enabled, reversing the Out-of-Scope decision"
		return 1
	fi

	pass "exactly one unencrypted budget file exists in account.sqlite"
	return 0
}

# Main test execution
echo
info "=== Actual Service Tests ==="
run_test "actual_unit_active" test_actual_unit_active || true
run_test "actual_port_listening" test_actual_port_listening || true
run_test "actual_no_startup_errors" test_actual_no_startup_errors || true

echo
info "=== State Directory Tests ==="
run_test "actual_state_dir_shape" test_actual_state_dir_shape || true
run_test "actual_persist_dir" test_actual_persist_dir || true

echo
info "=== Budget File Tests (ACT-02) ==="
run_test "actual_budget_file_unencrypted" test_actual_budget_file_unencrypted || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Actual service tests passed"
else
	fail "$tests_passed/$tests_run Actual service tests passed"
	exit 1
fi
