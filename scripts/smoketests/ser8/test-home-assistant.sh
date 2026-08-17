#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Home Assistant smoketest for ser8.
#
# Asserts that the home-assistant unit is active, that it answers over HTTP,
# and that the current boot's journal carries no error-level entry for it.
#
# The journal assertion is the one that earns its place. Home Assistant crosses
# roughly six months of releases in a channel bump and rewrites its own storage
# on first start with no supported downgrade. A unit that started, failed to
# load a component, and stayed up is the outcome the bump actually produces —
# and it is indistinguishable from a healthy one if the check stops at
# `systemctl is-active` and an HTTP 200.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

HASS_UNIT="home-assistant"
HASS_HTTP_PORT="8123"

# The HTTP probe originates on the host itself, matching the Frigate check
HASS_HTTP_HOST="localhost"

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

# Run a command on the target host, returning its stdout.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Test 1: the home-assistant unit is active
test_hass_unit_active() {
	info "checking that the '$(fmt_bold "$HASS_UNIT")' unit is active"

	local remote_command
	local remote_args=(systemctl is-active --quiet "$HASS_UNIT")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "'$(fmt_bold "$HASS_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$HASS_UNIT")' unit is not active"
	return 1
}

# Test 2: the Home Assistant frontend answers
test_hass_http() {
	info "checking the Home Assistant frontend on port $(fmt_bold "$HASS_HTTP_PORT")"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		"http://${HASS_HTTP_HOST}:${HASS_HTTP_PORT}/")

	case "$response" in
	200 | 301 | 302 | 303 | 401 | 403)
		pass "Home Assistant frontend responded with HTTP $response on port $HASS_HTTP_PORT"
		return 0
		;;
	esac

	fail "Home Assistant frontend on port $HASS_HTTP_PORT returned '${response:-no response}'"
	return 1
}

# Test 3: no error-level journal entry in the current boot
#
# Scoped to the current boot on purpose: an error from a previous generation is
# not evidence about the one running now, and carrying it forward would make
# the check permanently red after any single bad start.
test_hass_no_startup_errors() {
	info "checking the current boot's journal for '$(fmt_bold "$HASS_UNIT")' errors"

	local errors
	errors=$(remote journalctl -b -u "$HASS_UNIT" --priority=err --no-pager -q -o cat)

	if [ -z "$errors" ]; then
		pass "no error-level journal entries for '$(fmt_bold "$HASS_UNIT")' in the current boot"
		return 0
	fi

	local count
	count=$(echo "$errors" | wc -l | tr -d ' ')
	fail "$count error-level journal entries for '$(fmt_bold "$HASS_UNIT")' in the current boot"
	echo "$errors" | head -10 | while IFS= read -r line; do
		fail "  $line"
	done
	return 1
}

# Main test execution
echo
info "=== Home Assistant Service Tests ==="
run_test "hass_unit_active" test_hass_unit_active || true
run_test "hass_http" test_hass_http || true

echo
info "=== Home Assistant Startup Tests ==="
run_test "hass_no_startup_errors" test_hass_no_startup_errors || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Home Assistant tests passed"
else
	fail "$tests_passed/$tests_run Home Assistant tests passed"
	exit 1
fi
