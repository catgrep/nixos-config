#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Verification run smoketest for ser8.
#
# Asserts that the nightly verification is wired into the backup cycle, has
# actually completed, and that its last run succeeded.
#
# There is no timer to inspect. The verification is pulled in behind the
# replica copier through Wants=, and its ExecCondition skips every pass whose
# replica snapshot the latest manifest already records, so the unit runs the
# heavy walk once per nightly snapshot and is otherwise a no-op. That shapes
# what can be read from systemd: a oneshot that has never been started reports
# its result as success, because that is the field's default, and a
# condition-skipped pass leaves no runtime trace either. So "has ever run" is
# read from the stamp the verification writes only when it finishes cleanly,
# served by the node exporter from persisted storage, while the result and
# wiring are read from systemd's own state. A run that crashed before writing
# anything still shows here through its result, which the manifest test next
# to this one cannot see.

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

# The unit whose Wants= pulls the verification in, per hosts/ser8/backup/verify.nix
COPY_SERVICE="syncoid-rpool-safe-persist.service"

# The stamp verify.sh writes when a run finishes cleanly, served by the node
# exporter from the persisted textfile directory
METRICS_URL="http://localhost:9100/metrics"
VERIFY_STAMP="backup_last_verify_timestamp_seconds"

# The same day-plus-two-hours window the BackupVerifyStale alert rule uses
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

# One property out of a `systemctl show` block, or empty output when the
# property is absent. Read as key=value rather than with --value so that a
# property systemd did not emit is distinguishable from one whose value is
# genuinely empty.
show_property() {
	local block="$1" key="$2"
	printf '%s\n' "$block" | awk -F= -v k="$key" '$1 == k { sub("^" k "=", ""); print; exit }'
}

# Test 1: the verification is wired into the backup cycle
#
# A unit that was removed from the configuration reports as not-found rather
# than failing, so load state is checked explicitly. The Wants= edge is checked
# from the copier's side, because that edge is the only thing that ever starts
# the verification.
test_verify_chained() {
	info "checking that '$(fmt_bold "$VERIFY_SERVICE")' is loaded and wanted by '$COPY_SERVICE'"

	local block
	block=$(remote systemctl show "$VERIFY_SERVICE" -p LoadState)

	if [ -z "$block" ]; then
		fail "could not read the state of '$VERIFY_SERVICE' from $host"
		return 1
	fi

	local load_state
	load_state=$(show_property "$block" LoadState)

	if [ "$load_state" != "loaded" ]; then
		fail "'$VERIFY_SERVICE' has load state '$load_state', expected 'loaded'"
		fail "  the nightly verification is not installed on this host"
		return 1
	fi

	local wants
	wants=$(show_property "$(remote systemctl show "$COPY_SERVICE" -p Wants)" Wants)

	if ! printf '%s\n' "$wants" | tr ' ' '\n' | grep -qx "$VERIFY_SERVICE"; then
		fail "'$COPY_SERVICE' does not want '$VERIFY_SERVICE' on $host"
		fail "  nothing starts the verification after a replica snapshot lands"
		return 1
	fi

	pass "'$(fmt_bold "$VERIFY_SERVICE")' is loaded and wanted by '$COPY_SERVICE'"
	return 0
}

# Test 2: the verification has finished cleanly inside the alert window
#
# The sample line is filtered on the host so the whole exporter payload does
# not cross the link. The URL is expanded by the remote shell, not this one.
test_verify_stamp_fresh() {
	info "checking that '$(fmt_bold "$VERIFY_STAMP")' is under $((MAX_AGE_SECONDS / 3600))h old"

	local sample
	# shellcheck disable=SC2016
	sample=$(remote sh -c \
		'curl -fsS --max-time 10 "$1" | grep -E "^'"$VERIFY_STAMP"'( |\{)" || true' \
		_ "$METRICS_URL")

	if [ -z "$sample" ]; then
		fail "the node exporter on $host serves no '$VERIFY_STAMP' sample"
		fail "  the verification has never finished cleanly, so nothing has ever been proven restorable"
		return 1
	fi

	local stamp now age
	stamp=$(printf '%s\n' "$sample" | awk '{ printf "%d", $NF; exit }')
	now=$(remote date +%s)

	if [ -z "$stamp" ] || [ -z "$now" ]; then
		fail "could not read the verification stamp or the clock from $host"
		return 1
	fi

	age=$((now - stamp))

	if [ "$age" -gt "$MAX_AGE_SECONDS" ]; then
		fail "the last clean verification on $host finished ${age}s ago, outside the $((MAX_AGE_SECONDS / 3600))h window"
		return 1
	fi

	pass "the last clean verification finished ${age}s ago, inside the $((MAX_AGE_SECONDS / 3600))h window"
	return 0
}

# Test 3: the last invocation of the verification succeeded or was skipped
#
# Result covers how the process ended, including a kill that left no output.
# ActiveState is checked alongside it so a run that is currently failed cannot
# pass on a stale successful result. "exec-condition" is the gate declining a
# pass whose replica snapshot is already recorded; that is the unit's normal
# outcome on all but one pass a day, and the stamp test above is what proves
# the real run happened.
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

	if [ "$result" != "success" ] && [ "$result" != "exec-condition" ]; then
		fail "the last run of '$VERIFY_SERVICE' ended with result '$result'"
		fail "  exit status='$exec_status'"
		fail "  a non-success result covers a crash or a kill, which may have left no manifest at all"
		return 1
	fi

	pass "the last run of '$(fmt_bold "$VERIFY_SERVICE")' ended with result '$result'"
	return 0
}

echo
info "=== Verification Wiring Tests ==="
run_test "verify_chained" test_verify_chained || true
run_test "verify_stamp_fresh" test_verify_stamp_fresh || true

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
