#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Frigate smoketest for ser8.
#
# Asserts that the frigate unit is active, that its web interface answers over
# HTTP, and — the assertion this script exists for — that Frigate is publishing
# to the MQTT broker right now.
#
# The MQTT coupling is proven by subscribing, never by reading configuration.
# modules/automation/frigate.nix only establishes the intended broker settings;
# it says nothing about whether the connection survived a mosquitto upgrade.
# Two subscriptions give both liveness and freshness: the retained availability
# topic proves Frigate connected to this broker at some point, and a message on
# the periodic statistics topic within a bounded wait proves the connection is
# live now. Unit state and an HTTP response prove neither.
#
# The mosquitto client tools are not in ser8's system packages, and this check
# has to run against generations that predate any host change, so the
# subscriber is resolved from the running broker's own store path rather than
# added to the host. If that resolution fails the check fails; it does not skip.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

FRIGATE_UNIT="frigate"
FRIGATE_HTTP_PORT="80"

# The mosquitto listener in modules/automation/home-assistant.nix is bound to
# loopback only, so the subscription has to originate on the host itself.
MQTT_HOST="localhost"
MQTT_PORT="1883"

# Frigate's retained availability topic and its periodic statistics topic
MQTT_AVAILABILITY_TOPIC="frigate/available"
MQTT_STATS_TOPIC="frigate/stats"

# Comfortably longer than Frigate's statistics publication interval
MQTT_STATS_TIMEOUT="90"
MQTT_AVAILABILITY_TIMEOUT="10"

# Resolved from the running mosquitto unit by test_mqtt_client_resolved
MQTT_SUB=""

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

# Test 1: the frigate unit is active
test_frigate_unit_active() {
	info "checking that the '$(fmt_bold "$FRIGATE_UNIT")' unit is active"

	local remote_command
	local remote_args=(systemctl is-active --quiet "$FRIGATE_UNIT")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		pass "'$(fmt_bold "$FRIGATE_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$FRIGATE_UNIT")' unit is not active"
	return 1
}

# Test 2: the Frigate web interface answers
test_frigate_http() {
	info "checking the Frigate web interface on port $(fmt_bold "$FRIGATE_HTTP_PORT")"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		"http://${MQTT_HOST}:${FRIGATE_HTTP_PORT}/")

	case "$response" in
	200 | 301 | 302 | 303 | 401 | 403)
		pass "Frigate web interface responded with HTTP $response on port $FRIGATE_HTTP_PORT"
		return 0
		;;
	esac

	fail "Frigate web interface on port $FRIGATE_HTTP_PORT returned '${response:-no response}'"
	return 1
}

# Test 3: resolve the MQTT subscriber from the running broker
#
# The nixpkgs mosquitto package ships the broker and the client tools in the
# same output, so the subscriber sits beside the binary systemd is running.
# That makes the check work on any generation without touching the host.
test_mqtt_client_resolved() {
	info "resolving the MQTT subscriber from the running mosquitto unit"

	local broker
	broker=$(remote systemctl show -p ExecStart --value mosquitto.service |
		sed -n 's/.*path=\([^ ]*\).*/\1/p')

	if [ -z "$broker" ]; then
		fail "could not read the mosquitto unit's ExecStart path from $host"
		return 1
	fi

	local candidate
	candidate="$(dirname "$broker")/mosquitto_sub"

	local remote_command
	local remote_args=(test -x "$candidate")
	printf -v remote_command '%q ' "${remote_args[@]}"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	if ! ssh "$user@$ipaddr" "$remote_command" 2>/dev/null; then
		fail "no executable mosquitto_sub beside the running broker at $candidate"
		return 1
	fi

	MQTT_SUB="$candidate"
	pass "MQTT subscriber resolved from the running broker: $(fmt_bold "$MQTT_SUB")"
	return 0
}

# Subscribe to one topic on the host, bounded by a timeout. Prints the payload.
mqtt_receive() {
	local topic="$1"
	local timeout="$2"

	remote "$MQTT_SUB" -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -C 1 -W "$timeout"
}

# Test 4: Frigate's retained availability message reports it online
test_mqtt_availability() {
	info "subscribing to '$(fmt_bold "$MQTT_AVAILABILITY_TOPIC")' (retained, ${MQTT_AVAILABILITY_TIMEOUT}s bound)"

	if [ -z "$MQTT_SUB" ]; then
		fail "MQTT subscriber was never resolved; cannot assert the availability topic"
		return 1
	fi

	local payload
	payload=$(mqtt_receive "$MQTT_AVAILABILITY_TOPIC" "$MQTT_AVAILABILITY_TIMEOUT")

	if [ "$payload" = "online" ]; then
		pass "broker holds Frigate's retained availability message: '$(fmt_bold "$payload")'"
		return 0
	fi

	fail "Frigate's retained availability message is '${payload:-absent}', not 'online'"
	fail "  Frigate has never connected to this broker, or announced itself offline"
	return 1
}

# Test 5: a live statistics message arrives within the bounded wait
#
# This is the freshness half. The retained message above survives Frigate's
# death; only a new publication proves the connection is up right now.
test_mqtt_live_publication() {
	info "waiting up to ${MQTT_STATS_TIMEOUT}s for a live message on '$(fmt_bold "$MQTT_STATS_TOPIC")'"

	if [ -z "$MQTT_SUB" ]; then
		fail "MQTT subscriber was never resolved; cannot assert a live publication"
		return 1
	fi

	local payload
	payload=$(mqtt_receive "$MQTT_STATS_TOPIC" "$MQTT_STATS_TIMEOUT")

	if [ -n "$payload" ]; then
		pass "received a live Frigate publication on '$(fmt_bold "$MQTT_STATS_TOPIC")' (${#payload} bytes)"
		return 0
	fi

	fail "no message on '$MQTT_STATS_TOPIC' within ${MQTT_STATS_TIMEOUT}s"
	fail "  Frigate is not publishing; detections are not reaching Home Assistant"
	return 1
}

# Main test execution
echo
info "=== Frigate Service Tests ==="
run_test "frigate_unit_active" test_frigate_unit_active || true
run_test "frigate_http" test_frigate_http || true

echo
info "=== Frigate MQTT Publication Tests ==="
run_test "mqtt_client_resolved" test_mqtt_client_resolved || true
run_test "mqtt_availability" test_mqtt_availability || true
run_test "mqtt_live_publication" test_mqtt_live_publication || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Frigate tests passed"
else
	fail "$tests_passed/$tests_run Frigate tests passed"
	exit 1
fi
