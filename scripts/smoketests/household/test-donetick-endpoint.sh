#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Donetick endpoint smoketest.
#
# Covers the things that are wrong even when the service is up and the
# homepage renders: public signup re-opened by a hand-edited unit, and the
# tsnet vhost unreachable despite Caddy reporting healthy. Neither has a
# visible symptom until a stranger registers or a household member's link
# 404s.
#
# Takes the ser8 host as its argument. The tsnet probes run from the gateway
# host instead, resolved through deploy.yaml the same way.

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

# The tsnet node and vhost live on the gateway; addresses come from deploy.yaml
GATEWAY_HOST="firebat"
gateway_ipaddr=$(get_ip "$GATEWAY_HOST")
gateway_user=$(get_user "$GATEWAY_HOST")

DONETICK_PORT="2021"

# The tsnet node bound in modules/gateway/Caddyfile
DONETICK_TS_HOST="donetick.shad-bangus.ts.net"
DONETICK_BASE_URL="https://${DONETICK_TS_HOST}"

# Statuses the sibling suites accept: the service may redirect or demand auth
ACCEPTED_STATUS='^(200|301|302|303|401|403)$'

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

# Run a command on the ser8 host, returning its stdout. Empty output means the
# command could not be run or produced nothing; every caller treats that as a
# failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# The same, against the gateway host. Same printf %q escaping: probe
# arguments are never interpolated into a remote shell unescaped.
remote_gateway() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$gateway_user@$gateway_ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Test 1: the application answers on its own port
#
# Isolates "the app is serving" from "the proxy path works". When the
# firewall port is closed the two diverge, and a check that only probes the
# tsnet vhost reports one failure for two very different causes.
test_local_endpoint() {
	info "checking Donetick on the loopback port $(fmt_bold "$DONETICK_PORT")"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		"http://127.0.0.1:${DONETICK_PORT}/")

	if [[ "$response" =~ $ACCEPTED_STATUS ]]; then
		pass "Donetick answered with HTTP $response on port $DONETICK_PORT"
		return 0
	fi

	fail "Donetick on port $DONETICK_PORT returned '${response:-no response}'"
	return 1
}

# Test 2: public signup is closed
#
# The runtime counterpart to the two-stage deploy DTK-03 asks for. A
# connection failure counts as a failure, not a pass: a down service also
# rejects this request, and treating that as evidence of closed signup is how
# an unchanged default survives a green suite.
test_signup_closed() {
	info "checking that public signup is rejected"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		-X POST -H 'Content-Type: application/json' \
		-d '{"username":"stranger1","password":"whatever123","email":"stranger@household.internal"}' \
		"http://127.0.0.1:${DONETICK_PORT}/api/v1/auth/")

	if ! [[ "$response" =~ ^[0-9]{3}$ ]]; then
		fail "signup request returned '${response:-no response}'; a down service is not evidence signup is closed"
		return 1
	fi

	if [ "$response" = "201" ]; then
		fail "public signup still succeeds (HTTP 201); DT_IS_USER_CREATION_DISABLED did not reach the running process"
		return 1
	fi

	if [ "$response" = "403" ]; then
		pass "public signup rejected with HTTP 403"
		return 0
	fi

	fail "signup returned unexpected HTTP $response, expected 403"
	return 1
}

# Test 3: the tsnet name resolves
test_tsnet_dns() {
	# Probed from the gateway host because MagicDNS answers for tailnet
	# members only: donetick.shad-bangus.ts.net does not resolve from a
	# developer machine that is off the tailnet.
	info "checking DNS resolution for '$(fmt_bold "$DONETICK_TS_HOST")' from $GATEWAY_HOST"

	local result
	result=$(remote_gateway dig +short "$DONETICK_TS_HOST")

	if [ -n "$result" ]; then
		pass "DNS resolves '$(fmt_bold "$DONETICK_TS_HOST")' -> $result"
		return 0
	fi

	fail "DNS resolution failed for '$(fmt_bold "$DONETICK_TS_HOST")'"
	return 1
}

# Test 4: the tsnet vhost answers over HTTPS
test_tsnet_https() {
	info "checking HTTPS connectivity to '$(fmt_bold "$DONETICK_BASE_URL")' from $GATEWAY_HOST"

	local response
	response=$(remote_gateway curl -s -o /dev/null -w '%{http_code}' \
		--connect-timeout 10 --max-time 15 "$DONETICK_BASE_URL")

	if [[ "$response" =~ $ACCEPTED_STATUS ]]; then
		pass "$DONETICK_TS_HOST answered with HTTP $response"
		return 0
	fi

	fail "$DONETICK_TS_HOST returned '${response:-no response}'"
	return 1
}

# Main test execution
echo
info "=== Donetick Endpoint Tests ==="
run_test "local_endpoint" test_local_endpoint || true

echo
info "=== Donetick Signup Tests ==="
run_test "signup_closed" test_signup_closed || true

echo
info "=== Donetick Tsnet Tests ==="
run_test "tsnet_dns" test_tsnet_dns || true
run_test "tsnet_https" test_tsnet_https || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Donetick endpoint tests passed"
else
	fail "$tests_passed/$tests_run Donetick endpoint tests passed"
	exit 1
fi
