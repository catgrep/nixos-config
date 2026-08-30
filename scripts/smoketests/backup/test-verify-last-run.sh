#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Verification run smoketest for ser8.
#
# Asserts that the nightly verification is scheduled, has actually run, and
# that its last run succeeded.
#
# Everything here is read out of systemd's own state rather than out of any
# file the job wrote. That is deliberate and it is what makes this test
# different from the manifest one next to it: a run that crashed before writing
# anything leaves last night's manifest in place, so a check that reads the
# manifest would report a healthy engine while the job has been dying on start
# for a week. systemd remembers how the process ended whether or not it got far
# enough to leave a trace.
#
# The "has ever run" assertion is read from the timer rather than the service,
# and the difference matters. A oneshot service that has never been started
# reports its result as success, because that is the field's default -- so a
# test looking only at the service would pass on a host where the verification
# has never executed once. The timer's last-trigger stamp is unset until it
# genuinely fires, and it is written to persisted storage, so it survives the
# reboot that resets the service's own runtime state.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

VERIFY_SERVICE="backup-verify.service"
VERIFY_TIMER="backup-verify.timer"

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

# One property out of a `systemctl show` block, or empty output when the
# property is absent. Read as key=value rather than with --value so that a
# property systemd did not emit is distinguishable from one whose value is
# genuinely empty.
show_property() {
	local block="$1" key="$2"
	printf '%s\n' "$block" | awk -F= -v k="$key" '$1 == k { sub("^" k "=", ""); print; exit }'
}

# Test 1: the timer exists and is scheduled
#
# A unit that was removed from the configuration reports as not-found rather
# than failing, so load state is checked explicitly. Without it, a verification
# deleted from the host would show up here as nothing at all.
test_timer_scheduled() {
	info "checking that '$(fmt_bold "$VERIFY_TIMER")' is loaded and active"

	local block
	block=$(remote systemctl show "$VERIFY_TIMER" -p LoadState -p ActiveState)

	if [ -z "$block" ]; then
		fail "could not read the state of '$VERIFY_TIMER' from $host"
		return 1
	fi

	local load_state active_state
	load_state=$(show_property "$block" LoadState)
	active_state=$(show_property "$block" ActiveState)

	if [ "$load_state" != "loaded" ]; then
		fail "'$VERIFY_TIMER' has load state '$load_state', expected 'loaded'"
		fail "  the nightly verification is not installed on this host"
		return 1
	fi

	if [ "$active_state" != "active" ]; then
		fail "'$VERIFY_TIMER' has active state '$active_state', expected 'active'"
		fail "  the verification is installed but will never fire"
		return 1
	fi

	pass "'$(fmt_bold "$VERIFY_TIMER")' is loaded and active"
	return 0
}

# Test 2: the timer has fired at least once
test_timer_has_fired() {
	info "checking that '$(fmt_bold "$VERIFY_TIMER")' has fired at least once"

	local block
	block=$(remote systemctl show "$VERIFY_TIMER" -p LastTriggerUSec)

	if [ -z "$block" ]; then
		fail "could not read the last trigger time of '$VERIFY_TIMER' from $host"
		return 1
	fi

	local last_trigger
	last_trigger=$(show_property "$block" LastTriggerUSec)

	# systemd renders a timer that has never fired as an empty value or as
	# "n/a" depending on version, and both mean the same thing here.
	if [ -z "$last_trigger" ] || [ "$last_trigger" = "n/a" ] || [ "$last_trigger" = "0" ]; then
		fail "'$VERIFY_TIMER' has never fired on $host"
		fail "  the verification has not run once, so nothing has ever been proven restorable"
		return 1
	fi

	pass "'$(fmt_bold "$VERIFY_TIMER")' last fired at $last_trigger"
	return 0
}

# Test 3: the last invocation of the verification succeeded
#
# Result covers how the process ended, including a kill that left no output.
# ActiveState is checked alongside it so a run that is currently failed cannot
# pass on a stale successful result.
test_last_run_succeeded() {
	info "checking that the last run of '$(fmt_bold "$VERIFY_SERVICE")' succeeded"

	local block
	block=$(remote systemctl show "$VERIFY_SERVICE" -p Result -p ActiveState -p ExecMainStatus)

	if [ -z "$block" ]; then
		fail "could not read the state of '$VERIFY_SERVICE' from $host"
		return 1
	fi

	local result active_state exec_status
	result=$(show_property "$block" Result)
	active_state=$(show_property "$block" ActiveState)
	exec_status=$(show_property "$block" ExecMainStatus)

	if [ -z "$result" ]; then
		fail "'$VERIFY_SERVICE' reported no result on $host; the unit may not exist"
		return 1
	fi

	if [ "$active_state" = "failed" ]; then
		fail "'$VERIFY_SERVICE' is in the failed state on $host"
		fail "  result='$result' exit status='$exec_status'"
		return 1
	fi

	if [ "$result" != "success" ]; then
		fail "the last run of '$VERIFY_SERVICE' ended with result '$result'"
		fail "  exit status='$exec_status'"
		fail "  a non-success result covers a crash or a kill, which may have left no manifest at all"
		return 1
	fi

	pass "the last run of '$(fmt_bold "$VERIFY_SERVICE")' succeeded"
	return 0
}

echo
info "=== Verification Schedule Tests ==="
run_test "timer_scheduled" test_timer_scheduled || true
run_test "timer_has_fired" test_timer_has_fired || true

echo
info "=== Verification Result Tests ==="
run_test "last_run_succeeded" test_last_run_succeeded || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run verification run tests passed"
else
	fail "$tests_passed/$tests_run verification run tests passed"
	exit 1
fi
