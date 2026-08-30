#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Backup metrics smoketest for ser8.
#
# The metrics are the only evidence an outside observer has that this engine
# ran, and the staleness alerts on the monitoring host are built entirely on
# them. A metric that is written but not served is invisible to those alerts,
# and the failure is completely silent: the file is on disk, the job reports
# success, and the alert fires forever on a series nobody is publishing.
#
# So this queries the exporter's endpoint rather than reading the file. Reading
# the file would prove the job wrote it, which is the half already covered by
# the verification's own result. Querying the endpoint proves the collector
# found it, parsed it, and is serving it -- which is what actually has to be
# true for the alerts to work.
#
# The collector's own error counter is checked alongside the values, because a
# malformed file makes the collector drop every metric in the directory while
# the endpoint keeps answering normally.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# The node exporter's port, matching modules/servers/monitoring.nix
METRICS_URL="http://localhost:9100/metrics"

# Every series the nightly verification publishes
EXPECTED_METRICS=(
	backup_last_snapshot_timestamp_seconds
	backup_last_replica_timestamp_seconds
	backup_last_verify_timestamp_seconds
	backup_verified_files
	backup_persist_written_bytes
	backup_persist_usedbysnapshots_bytes
)

# The same day-plus-two-hours window the alert rules use
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

# The sample lines this suite cares about, filtered on the host so the whole
# exporter payload does not cross the link. Comment lines are excluded by the
# anchors, so only real samples come back.
scrape_backup_samples() {
	# The URL is expanded by the remote shell, not this one.
	# shellcheck disable=SC2016
	remote sh -c \
		'curl -fsS --max-time 10 "$1" | grep -E "^(backup_|node_textfile_scrape_error)" || true' \
		_ "$METRICS_URL"
}

# The value of a sample with no labels, or empty output when it is absent.
sample_value() {
	local payload="$1" metric="$2"
	printf '%s\n' "$payload" | awk -v m="$metric" '$1 == m { print $2; exit }'
}

# Test 1: the exporter serves every series the verification publishes
test_all_metrics_served() {
	info "checking that the exporter serves all ${#EXPECTED_METRICS[@]} backup series"

	local payload
	payload=$(scrape_backup_samples)

	if [ -z "$payload" ]; then
		fail "the exporter at '$METRICS_URL' served no backup series on $host"
		fail "  the collector is not reading the directory the verification writes to,"
		fail "  the exporter is down, or the verification has never written a metric"
		return 1
	fi

	local missing=()
	local metric
	for metric in "${EXPECTED_METRICS[@]}"; do
		# Matched with the metric name anchored so a labelled series such as
		# backup_verified_files{kind="sqlite"} still counts as present.
		if ! printf '%s\n' "$payload" | grep -qE "^${metric}([{ ])"; then
			missing+=("$metric")
		fi
	done

	if [ "${#missing[@]}" -gt 0 ]; then
		fail "${#missing[@]} backup series are not being served by $host"
		local entry
		for entry in "${missing[@]}"; do
			fail "  $entry"
		done
		return 1
	fi

	pass "the exporter serves all ${#EXPECTED_METRICS[@]} backup series"
	return 0
}

# Test 2: the collector parsed the file without error
test_textfile_collector_healthy() {
	info "checking that the textfile collector reports no parse error"

	local payload errors
	payload=$(scrape_backup_samples)

	if [ -z "$payload" ]; then
		fail "the exporter at '$METRICS_URL' returned nothing on $host"
		return 1
	fi

	errors=$(sample_value "$payload" node_textfile_scrape_error)

	if [ -z "$errors" ]; then
		fail "the exporter does not report 'node_textfile_scrape_error' on $host"
		fail "  the textfile collector is not enabled, so nothing in the directory is served"
		return 1
	fi

	if [ "$errors" != "0" ]; then
		fail "the textfile collector reports a scrape error ($errors) on $host"
		fail "  a malformed file makes the collector drop every metric in the directory"
		return 1
	fi

	pass "the textfile collector reports no parse error"
	return 0
}

# Test 3: the snapshot freshness series is inside the alert window
#
# The value is a timestamp, so this is the same assertion the staleness alert
# makes, evaluated here against the served series rather than against pool
# state. It catches the case where the series exists but has stopped advancing:
# the exporter answers, the collector is healthy, and the number underneath is
# from last week.
test_snapshot_metric_fresh() {
	info "checking that the served snapshot timestamp is under $((MAX_AGE_SECONDS / 3600))h old"

	local payload
	payload=$(scrape_backup_samples)
	if [ -z "$payload" ]; then
		fail "the exporter at '$METRICS_URL' returned nothing on $host"
		return 1
	fi

	local stamp
	stamp=$(sample_value "$payload" backup_last_snapshot_timestamp_seconds)

	if [ -z "$stamp" ]; then
		fail "'backup_last_snapshot_timestamp_seconds' is not being served by $host"
		return 1
	fi

	local now
	now=$(remote date +%s)
	if [ -z "$now" ]; then
		fail "could not read the current time from $host"
		return 1
	fi

	# The exporter renders gauge values in floating point, and for a number this
	# large that means exponent notation -- a Unix timestamp comes back as
	# 1.788026403e+09. Trimming at the first dot, which is enough for a plain
	# decimal, turns that into 1, and the age then reads as the entire span
	# since the epoch: a failure that looks like a stopped series rather than
	# like a parsing mistake. Normalising through awk handles integers,
	# decimals and exponents alike.
	stamp=$(printf '%s\n' "$stamp" | awk '{printf "%.0f", $1}')

	case "$now$stamp" in
	*[!0-9]*)
		fail "unparseable timestamps from $host: now='$now' metric='$stamp'"
		return 1
		;;
	esac

	local age=$((now - stamp))
	if [ "$age" -gt "$MAX_AGE_SECONDS" ]; then
		fail "the served snapshot timestamp is ${age}s old"
		fail "  the series is being published but has stopped advancing"
		return 1
	fi

	pass "the served snapshot timestamp is ${age}s old, inside the $((MAX_AGE_SECONDS / 3600))h window"
	return 0
}

echo
info "=== Metric Publication Tests ==="
run_test "all_metrics_served" test_all_metrics_served || true
run_test "textfile_collector_healthy" test_textfile_collector_healthy || true

echo
info "=== Metric Freshness Tests ==="
run_test "snapshot_metric_fresh" test_snapshot_metric_fresh || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run metric tests passed"
else
	fail "$tests_passed/$tests_run metric tests passed"
	exit 1
fi
