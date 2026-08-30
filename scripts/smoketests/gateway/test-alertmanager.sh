#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Alertmanager smoketest.
#
# What this exists to catch is the silent case: Prometheus evaluates its rules
# and marks them firing whether or not anything is listening, so a rules page
# full of firing alerts looks identical when nobody is being told. Every check
# below is about the delivery path rather than about the rules.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

ALERTMANAGER_URL="http://localhost:9093"
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"

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

remote() {
	# Expanded here rather than remotely on purpose: the URLs above are defined
	# in this file and are meant to reach the remote host's loopback.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$@"
}

# Test 1: the service is running at all
test_alertmanager_active() {
	info "checking that the Alertmanager service is active on $host"
	if remote 'systemctl is-active --quiet alertmanager'; then
		pass "alertmanager.service is active"
		return 0
	fi
	fail "alertmanager.service is not active on $host"
	return 1
}

# Test 2: it answers, which proves the configuration parsed
test_alertmanager_healthy() {
	info "checking that Alertmanager reports itself healthy"
	if remote "curl -sf --max-time 8 ${ALERTMANAGER_URL}/-/healthy >/dev/null"; then
		pass "Alertmanager is answering on its health endpoint"
		return 0
	fi
	fail "Alertmanager is not answering at $ALERTMANAGER_URL"
	fail "  a configuration it cannot parse leaves the unit up but the endpoint dead"
	return 1
}

# Test 3: Prometheus has actually been told where to send alerts.
# This is the one that matters. Everything else can be healthy while this list
# is empty, and an empty list is indistinguishable from a working one on the
# rules page.
test_prometheus_knows_the_alertmanager() {
	info "checking that Prometheus has a live Alertmanager registered"

	local payload
	payload=$(remote "curl -sf --max-time 8 ${PROMETHEUS_URL}/api/v1/alertmanagers" || true)

	if [ -z "$payload" ]; then
		fail "Prometheus did not answer its alertmanagers endpoint on $host"
		return 1
	fi

	# The active list carries one entry per reachable Alertmanager. Matching on
	# the port rather than parsing JSON keeps this readable and needs no parser
	# on the remote host.
	if printf '%s' "$payload" | grep -q '9093/api/v2/alerts'; then
		pass "Prometheus is sending alerts to an Alertmanager on port 9093"
	else
		fail "Prometheus has no active Alertmanager registered"
		fail "  rules will evaluate and fire, and reach nobody"
		return 1
	fi

	if printf '%s' "$payload" | grep -q '"droppedAlertmanagers":\[\]'; then
		pass "no Alertmanager was dropped as unreachable"
		return 0
	fi

	fail "Prometheus dropped an Alertmanager as unreachable"
	return 1
}

# Test 4: mail is configured, and the credential did not land in the store.
# The rendered configuration is world-readable, so a password in it would be a
# password on disk for every user of the host.
test_mail_configured_without_leaking() {
	info "checking that mail delivery is configured and the password is not in the store"

	# Found the way the unit itself finds it. The configuration is not named on
	# the command line: the service substitutes its environment into a copy at
	# start, and the source it reads from is named in the pre-start script.
	local prestart rendered
	prestart=$(remote "systemctl show alertmanager.service -p ExecStartPre --value | grep -oE '/nix/store/[^ ;]*alertmanager-pre-start' | head -1" || true)

	if [ -z "$prestart" ]; then
		fail "could not locate the Alertmanager pre-start script on $host"
		return 1
	fi

	rendered=$(remote "grep -oE '/nix/store/[^ \"]*checked-config' '$prestart' | head -1" || true)

	if [ -z "$rendered" ]; then
		fail "could not locate the rendered Alertmanager configuration on $host"
		return 1
	fi

	if remote "grep -q 'smtp_smarthost' '$rendered'"; then
		pass "the rendered configuration carries an SMTP destination"
	else
		fail "the rendered configuration has no SMTP destination; alerts would go nowhere"
		return 1
	fi

	if remote "grep -q '\"smtp_auth_password\":\"\\\$' '$rendered'"; then
		pass "the SMTP password is a placeholder in the store, substituted at start"
		return 0
	fi

	fail "the SMTP password in $rendered is not a placeholder"
	fail "  a literal there is world-readable to every user of this host"
	return 1
}

# Test 5: Grafana carries no alert rules of its own.
# Prometheus is meant to be the single rule-evaluation path, but Grafana keeps
# file-provisioned rules until told to delete them -- a rules block removed
# from provisioning can quietly keep evaluating and mailing. grafana.nix
# provisions explicit deletions; this checks they actually took.
test_grafana_has_no_alert_rules() {
	info "checking that Grafana evaluates no alert rules of its own"

	local payload
	payload=$(remote "curl -sf --max-time 8 ${GRAFANA_URL}/api/prometheus/grafana/api/v1/rules" || true)

	if [ -z "$payload" ]; then
		fail "Grafana did not answer its rules endpoint on $host"
		return 1
	fi

	if printf '%s' "$payload" | grep -q '"groups":\[\]'; then
		pass "Grafana carries no alert rules; Prometheus is the single evaluation path"
		return 0
	fi

	fail "Grafana still evaluates alert rules of its own"
	fail "  the mirrored rules were meant to be deleted with the consolidation"
	return 1
}

echo
info "=== Alertmanager Delivery Tests ==="
run_test "alertmanager_active" test_alertmanager_active || true
run_test "alertmanager_healthy" test_alertmanager_healthy || true
run_test "prometheus_knows_the_alertmanager" test_prometheus_knows_the_alertmanager || true
run_test "mail_configured_without_leaking" test_mail_configured_without_leaking || true
run_test "grafana_has_no_alert_rules" test_grafana_has_no_alert_rules || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Alertmanager tests passed"
else
	fail "$tests_passed/$tests_run Alertmanager tests passed"
	exit 1
fi
