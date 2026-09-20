#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Service-monitoring smoketest for firebat's Prometheus.
#
# The systemd and node-exporter jobs, the textfile-sourced policy metrics, and
# the service-monitoring rule group are all new surface with no user-visible
# symptom when any one link breaks: a target that silently stops scraping, a
# policy file that stops being read, or a rule that fails to load all look
# identical to "nothing changed" until the alert that depends on them never
# fires.
#
# Every check here queries Prometheus's own HTTP API rather than the exporters
# directly, because the API is what proves the whole path -- target discovery,
# scrape, and label attachment -- rather than only that an exporter answers.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

PROMETHEUS_URL="http://localhost:9090"

# The hosts the systemd and node-exporter jobs are meant to carry, per
# modules/gateway/monitored-hosts.nix.
MONITORED_HOSTS=(ser8 firebat)

# Physically disconnected and deliberately absent from monitored-hosts.nix;
# regressing that list back in would go unnoticed without this guard.
DISCONNECTED_HOSTS=(pi4 pi5)

ALERT_NAMES=(
	SystemdUnitFailed
	SystemdServiceCrashLooping
	SystemdServiceNotActive
	SystemdMonitoringDataMissing
)

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

# Run a command on firebat, returning its stdout. Empty output means the
# command could not be run or produced nothing; every caller treats that as a
# failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# An instant query against Prometheus's own API, run on firebat so the request
# never leaves the loopback interface Prometheus binds to.
prom_query() {
	remote curl -sf --max-time 8 -G "${PROMETHEUS_URL}/api/v1/query" --data-urlencode "query=$1"
}

# A GET against an already-formed Prometheus API path.
prom_get() {
	remote curl -sf --max-time 8 "${PROMETHEUS_URL}$1"
}

# The scalar value of an instant-vector query's first series, or empty when
# the query returned no series at all.
prom_first_value() {
	printf '%s' "$1" | jq -r '.data.result[0].value[1] // empty'
}

# How many series an instant-vector query returned.
prom_result_count() {
	printf '%s' "$1" | jq -r '.data.result | length'
}

# Test 1: both jobs are up for both monitored hosts. Passing this also proves
# the "host" label is attached, since every query below depends on it.
test_up_targets() {
	info "checking that node-exporter and systemd targets are up for every monitored host"

	local host_label job payload value missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		for job in node-exporter systemd; do
			payload=$(prom_query "up{job=\"${job}\",host=\"${host_label}\"}")
			value=$(prom_first_value "$payload")

			if [ "$value" = "1" ]; then
				pass "up{job=\"$job\",host=\"$host_label\"} == 1"
			else
				fail "up{job=\"$job\",host=\"$host_label\"} is '${value:-absent}', expected 1"
				missing=1
			fi
		done
	done
	[ "$missing" -eq 0 ]
}

# Test 2: the policy metric is present, per monitored host
test_monitoring_info_present() {
	info "checking that homelab_systemd_monitoring_info is published by every monitored host"

	local host_label payload value missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		payload=$(prom_query "homelab_systemd_monitoring_info{host=\"${host_label}\"}")
		value=$(prom_first_value "$payload")

		if [ "$value" = "1" ]; then
			pass "homelab_systemd_monitoring_info{host=\"$host_label\"} == 1"
		else
			fail "homelab_systemd_monitoring_info{host=\"$host_label\"} is '${value:-absent}', expected 1"
			missing=1
		fi
	done
	[ "$missing" -eq 0 ]
}

# Test 3: the expected-running policy carries at least one unit per host
test_expected_running_present() {
	info "checking that homelab_systemd_expected_running carries at least one unit per host"

	local host_label payload count missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		payload=$(prom_query "homelab_systemd_expected_running{host=\"${host_label}\"}")
		count=$(prom_result_count "$payload")

		if [ "$count" -gt 0 ]; then
			pass "homelab_systemd_expected_running carries $count unit(s) for host '$host_label'"
		else
			fail "homelab_systemd_expected_running carries no units for host '$host_label'"
			missing=1
		fi
	done
	[ "$missing" -eq 0 ]
}

# Test 4: restart counting is enabled and reporting on both hosts
test_restart_counting_enabled() {
	info "checking that systemd_service_restart_total is collected for every monitored host"

	local host_label payload count missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		payload=$(prom_query "systemd_service_restart_total{host=\"${host_label}\"}")
		count=$(prom_result_count "$payload")

		if [ "$count" -gt 0 ]; then
			pass "systemd_service_restart_total carries $count series for host '$host_label'"
		else
			fail "systemd_service_restart_total carries no series for host '$host_label'"
			missing=1
		fi
	done
	[ "$missing" -eq 0 ]
}

# Test 5: every unit the policy expects running actually shows active in the
# systemd exporter's own collection, on the same host. This is the join: the
# policy file and the exporter are two independent sources describing the same
# units, and neither alone proves the other agrees.
test_expected_running_matches_unit_state() {
	info "checking that every expected-running unit reports systemd_unit_state active"

	local host_label payload names name join_payload value checked=0 missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		payload=$(prom_query "homelab_systemd_expected_running{host=\"${host_label}\"}")
		names=$(printf '%s' "$payload" | jq -r '.data.result[].metric.name')

		if [ -z "$names" ]; then
			fail "no expected-running units found for host '$host_label' to join against"
			missing=1
			continue
		fi

		while IFS= read -r name; do
			[ -z "$name" ] && continue
			((checked += 1))
			join_payload=$(prom_query "systemd_unit_state{host=\"${host_label}\",name=\"${name}\",state=\"active\"}")
			value=$(prom_first_value "$join_payload")

			if [ "$value" = "1" ]; then
				pass "'$name' on '$host_label' reports systemd_unit_state{state=\"active\"} == 1"
			else
				fail "'$name' on '$host_label' has no active systemd_unit_state series"
				missing=1
			fi
		done <<<"$names"
	done

	[ "$checked" -gt 0 ] && [ "$missing" -eq 0 ]
}

# Test 6: the rule group is loaded and every alert in it is healthy. "health"
# here is Prometheus's own per-rule field: a rule that fails to evaluate
# (a typo'd label, a metric that never existed) reports its health as
# something other than "ok" while still appearing loaded.
test_service_monitoring_rules() {
	info "checking that the 'service-monitoring' rule group is loaded and healthy"

	local payload group_json name health missing=0
	payload=$(prom_get "/api/v1/rules")

	if [ -z "$payload" ]; then
		fail "Prometheus did not answer its rules endpoint on $host"
		return 1
	fi

	group_json=$(printf '%s' "$payload" | jq -c '.data.groups[] | select(.name == "service-monitoring")')

	if [ -z "$group_json" ]; then
		fail "rule group 'service-monitoring' is not loaded"
		return 1
	fi
	pass "rule group 'service-monitoring' is loaded"

	for name in "${ALERT_NAMES[@]}"; do
		health=$(printf '%s' "$group_json" | jq -r --arg n "$name" '.rules[] | select(.name == $n) | .health // empty')

		if [ -z "$health" ]; then
			fail "alert '$name' is not present in the 'service-monitoring' rule group"
			missing=1
		elif [ "$health" != "ok" ]; then
			fail "alert '$name' health is '$health', expected 'ok'"
			missing=1
		else
			pass "alert '$name' is loaded and healthy"
		fi
	done
	[ "$missing" -eq 0 ]
}

# Test 7: the pre-existing backup textfile series survives the handover to a
# second textfile directory. node-exporter reads both
# /persist/var/lib/node-exporter-textfile and /etc/node-exporter-static now;
# a flag that only pointed at the new directory would silently drop this one.
test_backup_textfile_metric_survives() {
	info "checking that backup_last_snapshot_timestamp_seconds still reaches Prometheus"

	local payload value
	payload=$(prom_query 'backup_last_snapshot_timestamp_seconds{host="ser8"}')
	value=$(prom_first_value "$payload")

	if [ -n "$value" ]; then
		pass "backup_last_snapshot_timestamp_seconds{host=\"ser8\"} = $value"
		return 0
	fi

	fail "backup_last_snapshot_timestamp_seconds{host=\"ser8\"} is absent"
	fail "  the second textfile directory may have displaced the first rather than joined it"
	return 1
}

# Test 8: scrape cost is observable for the new job. Diagnostic values are
# printed rather than bounded, because there is no known-good threshold yet --
# what matters here is that the numbers exist to look at later.
test_systemd_scrape_health_telemetry() {
	info "checking systemd job scrape health telemetry"

	local host_label payload duration samples missing=0
	for host_label in "${MONITORED_HOSTS[@]}"; do
		payload=$(prom_query "scrape_duration_seconds{job=\"systemd\",host=\"${host_label}\"}")
		duration=$(prom_first_value "$payload")

		if [ -z "$duration" ]; then
			fail "no scrape_duration_seconds for job=\"systemd\" host=\"$host_label\""
			missing=1
		else
			pass "scrape_duration_seconds{job=\"systemd\",host=\"$host_label\"} = ${duration}s"
		fi

		payload=$(prom_query "scrape_samples_scraped{job=\"systemd\",host=\"${host_label}\"}")
		samples=$(prom_first_value "$payload")

		if [ -z "$samples" ]; then
			fail "no scrape_samples_scraped for job=\"systemd\" host=\"$host_label\""
			missing=1
		else
			pass "scrape_samples_scraped{job=\"systemd\",host=\"$host_label\"} = $samples samples"
		fi
	done
	[ "$missing" -eq 0 ]
}

# Test 9: pi4/pi5 have not been reintroduced as scrape targets. Both are
# physically disconnected; a target Prometheus cannot reach just reports
# "down" forever, which pages on a host nobody can go fix.
test_no_disconnected_hosts_scraped() {
	info "checking that pi4/pi5 are not scrape targets in node-exporter or systemd"

	local payload hosts_present disconnected bad=0
	payload=$(prom_query 'up{job=~"node-exporter|systemd"}')
	hosts_present=$(printf '%s' "$payload" | jq -r '.data.result[].metric.host // empty')

	for disconnected in "${DISCONNECTED_HOSTS[@]}"; do
		if printf '%s\n' "$hosts_present" | grep -qx "$disconnected"; then
			fail "'$disconnected' is a scrape target in the node-exporter or systemd job"
			bad=1
		else
			pass "'$disconnected' is not a scrape target in the node-exporter or systemd job"
		fi
	done
	[ "$bad" -eq 0 ]
}

echo
info "=== Service Monitoring Target Tests ==="
run_test "up_targets" test_up_targets || true
run_test "monitoring_info_present" test_monitoring_info_present || true
run_test "expected_running_present" test_expected_running_present || true
run_test "restart_counting_enabled" test_restart_counting_enabled || true
run_test "expected_running_matches_unit_state" test_expected_running_matches_unit_state || true

echo
info "=== Service Monitoring Alert Tests ==="
run_test "service_monitoring_rules" test_service_monitoring_rules || true

echo
info "=== Service Monitoring Regression Guards ==="
run_test "backup_textfile_metric_survives" test_backup_textfile_metric_survives || true
run_test "systemd_scrape_health_telemetry" test_systemd_scrape_health_telemetry || true
run_test "no_disconnected_hosts_scraped" test_no_disconnected_hosts_scraped || true

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
