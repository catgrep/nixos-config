#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Service-monitoring smoketest for ser8's local exporters.
#
# firebat's Prometheus (scripts/smoketests/gateway/test-service-monitoring.sh)
# proves the whole path from ser8 through to the alert rules. This suite
# proves the half of that path that lives on ser8 itself: the policy file the
# systemd module writes, and that both local exporters are actually serving
# it. A break here and a break on firebat's end look identical from the
# gateway suite alone -- both read as "the metric never arrived" -- so this is
# what narrows the failure to this host.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Written by modules/servers/service-monitoring.nix
POLICY_FILE="/etc/node-exporter-static/systemd-policy.prom"

NODE_EXPORTER_URL="http://localhost:9100/metrics"
SYSTEMD_EXPORTER_URL="http://localhost:9558/metrics"

FRIGATE_UNIT="frigate.service"

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

# Scrapes an exporter endpoint on the host itself. The URL is expanded by the
# remote shell, not this one.
scrape() {
	local url="$1"
	# shellcheck disable=SC2016
	remote sh -c 'curl -fsS --max-time 10 "$1"' _ "$url"
}

# Test 1: the policy file exists and declares the monitoring info metric
test_policy_file_present() {
	info "checking that '$(fmt_bold "$POLICY_FILE")' declares the monitoring info metric"

	local contents
	contents=$(remote cat "$POLICY_FILE")

	if [ -z "$contents" ]; then
		fail "'$POLICY_FILE' is missing or empty on $host"
		return 1
	fi

	if printf '%s\n' "$contents" | grep -qx 'homelab_systemd_monitoring_info 1'; then
		pass "'$POLICY_FILE' declares 'homelab_systemd_monitoring_info 1'"
		return 0
	fi

	fail "'$POLICY_FILE' does not declare 'homelab_systemd_monitoring_info 1'"
	return 1
}

# Test 2: the local node exporter serves both the policy metric and at least
# one pre-existing backup metric, proving both textfile directories are still
# read after the handover to a second one.
test_node_exporter_serves_policy_and_backup_metrics() {
	info "checking that the node exporter serves the monitoring info metric and backup metrics"

	local payload ok=1
	payload=$(scrape "$NODE_EXPORTER_URL")

	if [ -z "$payload" ]; then
		fail "the node exporter at '$NODE_EXPORTER_URL' returned nothing on $host"
		return 1
	fi

	if printf '%s\n' "$payload" | grep -qE '^homelab_systemd_monitoring_info( |\{)'; then
		pass "node exporter serves 'homelab_systemd_monitoring_info'"
	else
		fail "node exporter does not serve 'homelab_systemd_monitoring_info'"
		ok=0
	fi

	if printf '%s\n' "$payload" | grep -qE '^backup_[a-zA-Z_]+( |\{)'; then
		pass "node exporter serves at least one 'backup_*' metric"
	else
		fail "node exporter does not serve any 'backup_*' metric"
		ok=0
	fi

	[ "$ok" -eq 1 ]
}

# Test 3: the local systemd exporter serves unit state for a known unit and
# restart counting for at least one unit.
test_systemd_exporter_serves_unit_metrics() {
	info "checking that the systemd exporter serves unit state and restart metrics"

	local payload ok=1
	payload=$(scrape "$SYSTEMD_EXPORTER_URL")

	if [ -z "$payload" ]; then
		fail "the systemd exporter at '$SYSTEMD_EXPORTER_URL' returned nothing on $host"
		return 1
	fi

	if printf '%s\n' "$payload" | grep -qF "systemd_unit_state{name=\"${FRIGATE_UNIT}\""; then
		pass "systemd exporter serves 'systemd_unit_state' for '$FRIGATE_UNIT'"
	else
		fail "systemd exporter does not serve 'systemd_unit_state' for '$FRIGATE_UNIT'"
		ok=0
	fi

	if printf '%s\n' "$payload" | grep -qE '^systemd_service_restart_total\{'; then
		pass "systemd exporter serves 'systemd_service_restart_total' for at least one unit"
	else
		fail "systemd exporter does not serve 'systemd_service_restart_total' for any unit"
		ok=0
	fi

	[ "$ok" -eq 1 ]
}

echo
info "=== Service Monitoring Policy Tests ==="
run_test "policy_file_present" test_policy_file_present || true

echo
info "=== Service Monitoring Exporter Tests ==="
run_test "node_exporter_serves_policy_and_backup_metrics" test_node_exporter_serves_policy_and_backup_metrics || true
run_test "systemd_exporter_serves_unit_metrics" test_systemd_exporter_serves_unit_metrics || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run service-monitoring tests passed"
else
	fail "$tests_passed/$tests_run service-monitoring tests passed"
	exit 1
fi
