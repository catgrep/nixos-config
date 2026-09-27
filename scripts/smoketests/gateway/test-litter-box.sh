#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Litter-box monitoring smoketest for firebat.
#
# The litter box dashboard reads two independent paths into Frigate on ser8:
# Prometheus scrapes Frigate's own /api/metrics for the per-camera event
# count (the LitterBoxNoVisit rule and the visit-count panels), and Grafana
# queries Frigate's events API directly through the Infinity datasource (the
# visit table and last-visit panel). Neither path has a user-visible symptom
# when it breaks: a scrape that stops just freezes a counter, and a
# datasource that fails to provision leaves panels reading "no data", which
# is also what a quiet day looks like.
#
# Every check queries firebat's own Prometheus and Grafana HTTP APIs over
# loopback, so what is proven is the provisioned state those services are
# actually running with, not the configuration that was meant to produce it.
# Grafana serves dashboards, datasources and the plugin list to its anonymous
# viewer role, so no credential is needed.

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
GRAFANA_URL="http://localhost:3000"

SCRAPE_JOB="frigate-api"
EVENT_METRIC="frigate_camera_events_total"
ALERT_NAME="LitterBoxNoVisit"
RULE_GROUP="homelab"

INFINITY_PLUGIN_ID="yesoreyeram-infinity-datasource"
DATASOURCE_UID="frigate"
DASHBOARD_UID="litter-box"

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

# A GET against an already-formed Grafana API path, as the anonymous viewer.
grafana_get() {
	remote curl -sf --max-time 8 "${GRAFANA_URL}$1"
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

# Test 1: the frigate-api scrape target is up.
test_frigate_api_target_up() {
	info "checking that the '$SCRAPE_JOB' scrape target is up"

	local payload value
	payload=$(prom_query "up{job=\"${SCRAPE_JOB}\"}")
	value=$(prom_first_value "$payload")

	if [ "$value" = "1" ]; then
		pass "up{job=\"$SCRAPE_JOB\"} == 1"
		return 0
	fi

	fail "up{job=\"$SCRAPE_JOB\"} is '${value:-absent}', expected 1"
	return 1
}

# Test 2: the event count reaches Prometheus and it is the only series the
# job contributes. The endpoint also serves every metric the frigate exporter
# job already scrapes, under the same names; a second copy of those would
# double every panel on the Frigate dashboard.
test_event_metric_only() {
	info "checking that '$SCRAPE_JOB' contributes $EVENT_METRIC and nothing else"

	local payload count names
	payload=$(prom_query "${EVENT_METRIC}{job=\"${SCRAPE_JOB}\"}")
	count=$(prom_result_count "$payload")

	if [ -z "$count" ] || [ "$count" -eq 0 ]; then
		fail "$EVENT_METRIC carries no series from job '$SCRAPE_JOB'"
		return 1
	fi
	pass "$EVENT_METRIC carries $count camera/label series from job '$SCRAPE_JOB'"

	payload=$(prom_query "{job=\"${SCRAPE_JOB}\",__name__!~\"${EVENT_METRIC}|up|scrape_.*\"}")
	names=$(printf '%s' "$payload" | jq -r '.data.result[].metric.__name__' | sort -u)

	if [ -n "$names" ]; then
		fail "job '$SCRAPE_JOB' leaks metrics beyond $EVENT_METRIC:"
		while IFS= read -r name; do
			fail "  $name"
		done <<<"$names"
		return 1
	fi
	pass "job '$SCRAPE_JOB' contributes no other metric"
	return 0
}

# Test 3: the alert rule is loaded and healthy. "health" is Prometheus's own
# per-rule field: a rule that fails to evaluate reports something other than
# "ok" while still appearing loaded.
test_alert_rule_loaded() {
	info "checking that the '$ALERT_NAME' rule is loaded and healthy"

	local payload health
	payload=$(prom_get "/api/v1/rules")

	if [ -z "$payload" ]; then
		fail "Prometheus did not answer its rules endpoint on $host"
		return 1
	fi

	health=$(printf '%s' "$payload" | jq -r --arg g "$RULE_GROUP" --arg n "$ALERT_NAME" \
		'.data.groups[] | select(.name == $g) | .rules[] | select(.name == $n) | .health // empty')

	if [ -z "$health" ]; then
		fail "alert '$ALERT_NAME' is not present in the '$RULE_GROUP' rule group"
		return 1
	elif [ "$health" != "ok" ]; then
		fail "alert '$ALERT_NAME' health is '$health', expected 'ok'"
		return 1
	fi
	pass "alert '$ALERT_NAME' is loaded and healthy"
	return 0
}

# Test 4: the Infinity plugin answers a query through Grafana. Grafana hides
# external plugins from the anonymous plugin list, so the plugin is proven by
# running the smallest query the dashboard makes and reading the per-query
# status Grafana returns, which also covers the datasource's allowed-hosts list
# and the network path from firebat to Frigate.
test_infinity_query_answers() {
	info "checking that the '$DATASOURCE_UID' datasource answers a query through Grafana"

	local query payload status
	query=$(
		cat <<EOF
{"queries":[{"refId":"A","datasource":{"uid":"$DATASOURCE_UID","type":"$INFINITY_PLUGIN_ID"},
"type":"json","source":"url","format":"table","parser":"backend",
"url":"http://ser8.local/api/events",
"url_options":{"method":"GET","params":[{"key":"cameras","value":"indoor_hallway"},{"key":"limit","value":"1"}]},
"root_selector":"","columns":[{"selector":"start_time","text":"Start","type":"timestamp_epoch_s"}]}]}
EOF
	)
	payload=$(remote curl -sf --max-time 20 -H 'Content-Type: application/json' \
		"${GRAFANA_URL}/api/ds/query" -d "$query")

	if [ -z "$payload" ]; then
		fail "Grafana did not answer the datasource query on $host"
		return 1
	fi

	status=$(printf '%s' "$payload" | jq -r '.results.A.status // empty')

	if [ "$status" = "200" ]; then
		pass "datasource '$DATASOURCE_UID' answered the query with status 200"
		return 0
	fi

	fail "datasource '$DATASOURCE_UID' query returned status '${status:-none}'"
	fail "  $(printf '%s' "$payload" | jq -r '.results.A.error // .message // empty' | head -c 200)"
	return 1
}

# Test 5: the Frigate datasource is provisioned on that plugin.
test_frigate_datasource_provisioned() {
	info "checking that the '$DATASOURCE_UID' datasource is provisioned"

	local payload type
	payload=$(grafana_get "/api/datasources/uid/${DATASOURCE_UID}")

	if [ -z "$payload" ]; then
		fail "datasource uid '$DATASOURCE_UID' is not provisioned"
		return 1
	fi

	type=$(printf '%s' "$payload" | jq -r '.type // empty')

	if [ "$type" = "$INFINITY_PLUGIN_ID" ]; then
		pass "datasource '$DATASOURCE_UID' is provisioned with type '$type'"
		return 0
	fi

	fail "datasource '$DATASOURCE_UID' has type '${type:-absent}', expected '$INFINITY_PLUGIN_ID'"
	return 1
}

# Test 6: the dashboard is provisioned and every panel targets a datasource
# uid that exists. A dashboard with a dangling datasource uid still loads;
# its panels just show an error nobody sees until they open it.
test_dashboard_provisioned() {
	info "checking that the '$DASHBOARD_UID' dashboard is provisioned"

	local payload uids uid ds missing=0
	payload=$(grafana_get "/api/dashboards/uid/${DASHBOARD_UID}")

	if [ -z "$payload" ]; then
		fail "dashboard uid '$DASHBOARD_UID' is not provisioned"
		return 1
	fi
	pass "dashboard '$DASHBOARD_UID' is provisioned"

	uids=$(printf '%s' "$payload" | jq -r '.dashboard.panels[].targets[].datasource.uid' | sort -u)

	while IFS= read -r uid; do
		[ -z "$uid" ] && continue
		ds=$(grafana_get "/api/datasources/uid/${uid}")
		if [ -n "$ds" ]; then
			pass "panel datasource uid '$uid' resolves"
		else
			fail "panel datasource uid '$uid' does not resolve to a provisioned datasource"
			missing=1
		fi
	done <<<"$uids"

	[ "$missing" -eq 0 ]
}

echo
info "=== Litter Box Prometheus Tests ==="
run_test "frigate_api_target_up" test_frigate_api_target_up || true
run_test "event_metric_only" test_event_metric_only || true
run_test "alert_rule_loaded" test_alert_rule_loaded || true

echo
info "=== Litter Box Grafana Tests ==="
run_test "infinity_query_answers" test_infinity_query_answers || true
run_test "frigate_datasource_provisioned" test_frigate_datasource_provisioned || true
run_test "dashboard_provisioned" test_dashboard_provisioned || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run litter-box tests passed"
else
	fail "$tests_passed/$tests_run litter-box tests passed"
	exit 1
fi
