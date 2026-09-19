#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# HomeKit export smoketest for ser8.
#
# go2rtc advertises every Frigate camera's _main stream as a HomeKit
# accessory (modules/automation/frigate.nix). This asserts the moving
# parts an Apple device depends on:
#
#   - the go2rtc unit is active,
#   - the accessory list is reachable over the LAN on the API port the
#     HomeKit protocol is served on (proving the firewall opening, which
#     is why this check runs from here and not over SSH),
#   - every camera in Frigate's live configuration has an accessory,
#   - unpaired accessories publish a real XXX-XX-XXX setup code, which
#     fails if the FRIGATE_HOMEKIT_PIN placeholder was never expanded,
#   - the pairing state file exists on the persisted Frigate dataset, so
#     pairings survive the impermanence rollback on reboot.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

GO2RTC_UNIT="go2rtc"
GO2RTC_API_PORT="1984"
HOMEKIT_STATE_FILE="/var/lib/frigate/go2rtc-homekit.yaml"

# Filled by test_homekit_accessories_reachable, reused by later tests
homekit_json=""

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

# Test 1: the go2rtc unit is active
test_go2rtc_unit_active() {
	info "checking that the '$(fmt_bold "$GO2RTC_UNIT")' unit is active"

	local remote_command
	local remote_args=(systemctl is-active --quiet "$GO2RTC_UNIT")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "'$(fmt_bold "$GO2RTC_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$GO2RTC_UNIT")' unit is not active"
	return 1
}

# Test 2: the accessory list answers over the LAN
test_homekit_accessories_reachable() {
	info "fetching HomeKit accessories from port $(fmt_bold "$GO2RTC_API_PORT") over the LAN"

	homekit_json=$(curl -fsS --connect-timeout 5 --max-time 15 \
		"http://${ipaddr}:${GO2RTC_API_PORT}/api/homekit" || echo "")

	if [ -z "$homekit_json" ]; then
		fail "no response from http://${ipaddr}:${GO2RTC_API_PORT}/api/homekit"
		fail "  Apple devices cannot reach the accessory server either"
		return 1
	fi

	local count
	count=$(jq 'length' <<<"$homekit_json")
	if [ "$count" -lt 1 ]; then
		fail "the accessory list is empty; no camera is exported to HomeKit"
		return 1
	fi

	pass "accessory list reachable over the LAN with $(fmt_bold "$count") accessories"
	return 0
}

# Test 3: every Frigate camera has a matching accessory
test_homekit_covers_all_cameras() {
	info "checking that every Frigate camera has a HomeKit accessory"

	if [ -z "$homekit_json" ]; then
		fail "the accessory list was never fetched; cannot compare against cameras"
		return 1
	fi

	# The camera list comes from Frigate's live configuration rather than
	# this repository, so the comparison tracks what is actually deployed.
	local config
	config=$(remote curl -fsS --connect-timeout 5 --max-time 15 \
		"http://localhost:5000/api/config")
	if [ -z "$config" ]; then
		fail "could not read the camera list from Frigate's API"
		return 1
	fi

	local missing
	missing=$(jq -r --argjson homekit "$homekit_json" \
		'.cameras | keys[] | select(($homekit["\(.)_main"] // null) == null)' \
		<<<"$config")

	if [ -n "$missing" ]; then
		fail "cameras without a HomeKit accessory: $(fmt_bold "$missing")"
		return 1
	fi

	pass "every Frigate camera is exported as a HomeKit accessory"
	return 0
}

# Test 4: unpaired accessories publish a real setup code
#
# go2rtc only reveals the setup code while an accessory is unpaired, so a
# fully paired household legitimately publishes none. What must never
# appear is a non-numeric code: that means the FRIGATE_HOMEKIT_PIN
# placeholder survived into the running config unexpanded. go2rtc
# normalizes valid PINs to Apple's dashed XXX-XX-XXX presentation.
test_homekit_setup_codes_expanded() {
	info "checking that published setup codes are expanded XXX-XX-XXX PINs"

	if [ -z "$homekit_json" ]; then
		fail "the accessory list was never fetched; cannot inspect setup codes"
		return 1
	fi

	local malformed
	malformed=$(jq -r 'to_entries[]
		| select(.value.setup_code != null)
		| select(.value.setup_code | test("^[0-9]{3}-[0-9]{2}-[0-9]{3}$") | not)
		| .key' <<<"$homekit_json")

	if [ -n "$malformed" ]; then
		fail "accessories with a malformed setup code: $(fmt_bold "$malformed")"
		fail "  the homekit_pin secret is missing or was not expanded from frigate.env"
		return 1
	fi

	pass "all published setup codes are expanded XXX-XX-XXX PINs"
	return 0
}

# Test 5: the pairing state file sits on the persisted dataset
#
# sudo because Frigate's StateDirectoryMode keeps /var/lib/frigate at
# 0750, which the deploy user cannot traverse.
test_homekit_state_persisted() {
	info "checking the pairing state file at $(fmt_bold "$HOMEKIT_STATE_FILE")"

	local remote_command
	local remote_args=(sudo -n test -s "$HOMEKIT_STATE_FILE")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "pairing state file exists on the persisted Frigate dataset"
		return 0
	fi

	fail "pairing state file is missing or empty at $HOMEKIT_STATE_FILE"
	fail "  pairings made now will not survive a reboot"
	return 1
}

# Main test execution
echo
info "=== go2rtc HomeKit Export Tests ==="
run_test "go2rtc_unit_active" test_go2rtc_unit_active || true
run_test "homekit_accessories_reachable" test_homekit_accessories_reachable || true
run_test "homekit_covers_all_cameras" test_homekit_covers_all_cameras || true
run_test "homekit_setup_codes_expanded" test_homekit_setup_codes_expanded || true
run_test "homekit_state_persisted" test_homekit_state_persisted || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run HomeKit export tests passed"
else
	fail "$tests_passed/$tests_run HomeKit export tests passed"
	exit 1
fi
