#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Mealie endpoint smoketest.
#
# Covers the things that are wrong even when the service is up and the
# homepage renders: a base URL still pointing at the module's loopback
# default, a signup control that stringified away to the empty string, and the
# shipped administrator account still answering with its published password.
#
# None of these has a visible symptom. A share link that silently points at
# http://localhost:9000 looks fine until somebody outside the house opens it;
# an empty ALLOW_SIGNUP looks fine until a stranger registers.
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

MEALIE_UNIT="mealie"
MEALIE_PORT="9000"

# The tsnet node bound in modules/gateway/Caddyfile
MEALIE_TS_HOST="mealie.shad-bangus.ts.net"
MEALIE_BASE_URL="https://${MEALIE_TS_HOST}"

# What the NixOS module sets when BASE_URL is left alone. Share links,
# password-reset links, and every future redirect read this value, so landing
# on it is a silent misconfiguration rather than an outage.
MEALIE_MODULE_DEFAULT_BASE_URL="http://localhost:${MEALIE_PORT}"

# Mealie's shipped first-run administrator. These are published upstream
# defaults, not secrets; the changed credentials appear nowhere in this repo.
MEALIE_DEFAULT_ADMIN_USER="changeme@example.com"
MEALIE_DEFAULT_ADMIN_PASSWORD="MyPassword"
MEALIE_TOKEN_PATH="/api/auth/token"

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

# The same, against the gateway host. Same printf %q escaping: probe arguments
# are never interpolated into a remote shell unescaped.
remote_gateway() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$gateway_user@$gateway_ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Read one variable out of the DEPLOYED unit environment, which is what the
# service actually runs with — not what the flake evaluates to.
unit_env() {
	remote systemctl show "$MEALIE_UNIT" --property=Environment --value |
		tr ' ' '\n' |
		sed -n "s/^${1}=//p"
}

# True when the named variable is present in the deployed unit environment at
# all, empty or not. Distinguishes "stringified to nothing" from "never set".
unit_env_present() {
	remote systemctl show "$MEALIE_UNIT" --property=Environment --value |
		tr ' ' '\n' |
		grep -q "^${1}="
}

# Test 1: the application answers on its own port
#
# Isolates "the app is serving" from "the proxy path works". When the firewall
# port is closed the two diverge, and a check that only probes the tsnet vhost
# reports one failure for two very different causes.
test_local_endpoint() {
	info "checking Mealie on the loopback port $(fmt_bold "$MEALIE_PORT")"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		"http://127.0.0.1:${MEALIE_PORT}/")

	if [[ "$response" =~ $ACCEPTED_STATUS ]]; then
		pass "Mealie answered with HTTP $response on port $MEALIE_PORT"
		return 0
	fi

	fail "Mealie on port $MEALIE_PORT returned '${response:-no response}'"
	return 1
}

# Test 2: the deployed BASE_URL is the tsnet URL
test_base_url_is_tsnet() {
	info "checking that the deployed BASE_URL is $(fmt_bold "$MEALIE_BASE_URL")"

	local value
	value=$(unit_env BASE_URL)

	if [ "$value" = "$MEALIE_BASE_URL" ]; then
		pass "BASE_URL is $value"
		return 0
	fi

	fail "BASE_URL is '${value:-unset}', expected '$MEALIE_BASE_URL'"
	return 1
}

# Test 3: the deployed BASE_URL is not the module default
#
# Asserted separately from test 2 so the failure names the actual cause. A
# BASE_URL still on the loopback default means every share link generated for
# the household points at a host only ser8 itself can reach.
test_base_url_not_module_default() {
	info "checking that BASE_URL is not the module default $(fmt_bold "$MEALIE_MODULE_DEFAULT_BASE_URL")"

	local value
	value=$(unit_env BASE_URL)

	if [ "$value" = "$MEALIE_MODULE_DEFAULT_BASE_URL" ]; then
		fail "BASE_URL is still the module default '$value'; the settings override did not reach the unit"
		return 1
	fi

	pass "BASE_URL is not the module default"
	return 0
}

# Test 4: the signup setting survived stringification
#
# The runtime counterpart to the evaluation assertion in plan 10-01. Both are
# worth having: the eval gate catches the mistake before a deploy, this one
# catches a hand-edited unit after it. `toString false` is the empty string in
# Nix, so an empty value here is the exact footprint of a boolean that was
# meant to be the string "false" — and it leaves registration unconfigured.
test_signup_closed() {
	info "checking that ALLOW_SIGNUP is the non-empty string 'false'"

	if ! unit_env_present ALLOW_SIGNUP; then
		fail "ALLOW_SIGNUP is absent from the deployed unit environment"
		return 1
	fi

	local value
	value=$(unit_env ALLOW_SIGNUP)

	if [ -z "$value" ]; then
		fail "ALLOW_SIGNUP is present but empty; a Nix boolean stringified away and registration is unconfigured"
		return 1
	fi

	if [ "$value" = "false" ]; then
		pass "ALLOW_SIGNUP is the string 'false'"
		return 0
	fi

	fail "ALLOW_SIGNUP is '$value', expected the string 'false'"
	return 1
}

# Test 5: the shipped administrator account is gone
#
# A connection failure counts as a failure, not a pass: a service that is down
# rejects these credentials too, and treating that as evidence of hardening is
# how an unchanged default survives a green suite.
test_default_admin_rejected() {
	info "checking that Mealie's shipped default administrator is rejected"

	local response
	response=$(remote curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
		-X POST \
		-d "username=${MEALIE_DEFAULT_ADMIN_USER}&password=${MEALIE_DEFAULT_ADMIN_PASSWORD}" \
		"http://127.0.0.1:${MEALIE_PORT}${MEALIE_TOKEN_PATH}")

	if ! [[ "$response" =~ ^[0-9]{3}$ ]]; then
		fail "token request returned '${response:-no response}'; a down service is not evidence that the default account was changed"
		return 1
	fi

	if [ "$response" = "200" ]; then
		fail "the shipped default administrator still authenticates (HTTP 200); change it before exposing Mealie"
		return 1
	fi

	pass "shipped default administrator rejected with HTTP $response"
	return 0
}

# Test 6: the tsnet name resolves
test_tsnet_dns() {
	# Probed from the gateway host because MagicDNS answers for tailnet
	# members only: mealie.shad-bangus.ts.net does not resolve from a
	# developer machine that is off the tailnet.
	info "checking DNS resolution for '$(fmt_bold "$MEALIE_TS_HOST")' from $GATEWAY_HOST"

	local result
	result=$(remote_gateway dig +short "$MEALIE_TS_HOST")

	if [ -n "$result" ]; then
		pass "DNS resolves '$(fmt_bold "$MEALIE_TS_HOST")' -> $result"
		return 0
	fi

	fail "DNS resolution failed for '$(fmt_bold "$MEALIE_TS_HOST")'"
	return 1
}

# Test 7: the tsnet vhost answers over HTTPS
test_tsnet_https() {
	info "checking HTTPS connectivity to '$(fmt_bold "$MEALIE_BASE_URL")' from $GATEWAY_HOST"

	local response
	response=$(remote_gateway curl -s -o /dev/null -w '%{http_code}' \
		--connect-timeout 10 --max-time 15 "$MEALIE_BASE_URL")

	if [[ "$response" =~ $ACCEPTED_STATUS ]]; then
		pass "$MEALIE_TS_HOST answered with HTTP $response"
		return 0
	fi

	fail "$MEALIE_TS_HOST returned '${response:-no response}'"
	return 1
}

# Main test execution
echo
info "=== Mealie Endpoint Tests ==="
run_test "local_endpoint" test_local_endpoint || true

echo
info "=== Mealie Deployed Settings Tests ==="
run_test "base_url_is_tsnet" test_base_url_is_tsnet || true
run_test "base_url_not_module_default" test_base_url_not_module_default || true
run_test "signup_closed" test_signup_closed || true

echo
info "=== Mealie Authentication Tests ==="
run_test "default_admin_rejected" test_default_admin_rejected || true

echo
info "=== Mealie Tsnet Tests ==="
run_test "tsnet_dns" test_tsnet_dns || true
run_test "tsnet_https" test_tsnet_https || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Mealie endpoint tests passed"
else
	fail "$tests_passed/$tests_run Mealie endpoint tests passed"
	exit 1
fi
