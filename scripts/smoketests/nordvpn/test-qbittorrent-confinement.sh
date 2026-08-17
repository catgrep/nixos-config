#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# qBittorrent VPN-confinement smoketest.
#
# Asserts that the torrent client is confined to the wgnord network namespace
# and egresses through the VPN rather than the household's home connection.
#
# This check is READ-ONLY by construction: it brings no interface down,
# restarts no unit, and alters no route. That is precisely why it is safe on
# the routine deploy path, where the kill-switch test in ./disruptive.sh is
# not.
#
# The egress comparison is the assertion that matters. Reporting both
# addresses would not be a test — equal addresses mean the torrent client is
# talking to trackers over the home connection, so this script compares them
# and fails when they match. An address it cannot obtain is treated as a
# FAILURE, never a skip: from the caller's point of view an unreadable
# namespace is indistinguishable from a broken one, and a check that passes
# when it cannot see is worse than no check at all.

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

# Namespace holding the WireGuard tunnel, per modules/nordvpn/.
NETNS="wgnord"
QBT_UNIT="qbittorrent-nox.service"
QBT_PORT="8080"

# Reports the caller's public address as a bare string. A hostname, never a
# literal address, so deploy.yaml stays the only source of address truth.
EGRESS_URL="https://ipinfo.io/ip"

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

# Runs a read-only command on the target host with arguments escaped.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command"
}

# Test 1: qBittorrent's process is inside the VPN namespace.
test_process_in_namespace() {
	info "checking that $QBT_UNIT runs inside the '$(fmt_bold "$NETNS")' namespace"

	local qbt_pid
	qbt_pid=$(remote systemctl show "$QBT_UNIT" -p MainPID --value 2>/dev/null || echo "0")
	qbt_pid=${qbt_pid//[[:space:]]/}

	if [ -z "$qbt_pid" ] || [ "$qbt_pid" = "0" ]; then
		fail "$QBT_UNIT has no running process on $host"
		return 1
	fi

	local observed_ns
	observed_ns=$(remote sudo -n ip netns identify "$qbt_pid" 2>/dev/null || echo "")
	observed_ns=${observed_ns//[[:space:]]/}

	if [ -z "$observed_ns" ]; then
		fail "could not identify the network namespace of $QBT_UNIT (pid $qbt_pid)"
		return 1
	fi

	if [ "$observed_ns" != "$NETNS" ]; then
		fail "$QBT_UNIT runs in namespace '$observed_ns', expected '$NETNS'"
		return 1
	fi

	pass "$QBT_UNIT (pid $qbt_pid) is confined to the '$NETNS' namespace"
	return 0
}

# Test 2: the namespace egresses somewhere other than the home connection.
# This is the leak check.
test_egress_differs_from_host() {
	info "comparing '$(fmt_bold "$NETNS")' egress against the host's own egress"

	local host_egress
	host_egress=$(remote curl -s --connect-timeout 10 --max-time 15 "$EGRESS_URL" 2>/dev/null || echo "")
	host_egress=${host_egress//[[:space:]]/}

	local netns_egress
	netns_egress=$(
		remote sudo -n ip netns exec "$NETNS" \
			curl -s --connect-timeout 10 --max-time 15 "$EGRESS_URL" 2>/dev/null || echo ""
	)
	netns_egress=${netns_egress//[[:space:]]/}

	# An address we cannot read is a failure, not a skip.
	if [ -z "$host_egress" ]; then
		fail "could not obtain the host egress address for $host"
		return 1
	fi

	if [ -z "$netns_egress" ]; then
		fail "could not obtain the '$NETNS' namespace egress address; the tunnel is down or the namespace is broken"
		return 1
	fi

	if [ "$host_egress" = "$netns_egress" ]; then
		fail "VPN LEAK: '$NETNS' egress address equals the host egress address ($netns_egress); qBittorrent is talking to the internet over the home connection"
		return 1
	fi

	pass "'$NETNS' egresses from $netns_egress, host egresses from $host_egress (addresses differ)"
	return 0
}

# Test 3: the confined web UI is reachable through the host's nginx proxy.
test_webui_reachable() {
	info "checking the qBittorrent web UI on localhost port $QBT_PORT"

	local response
	response=$(
		remote curl -s -o /dev/null -w '%{http_code}' \
			--connect-timeout 5 --max-time 10 "http://localhost:$QBT_PORT" 2>/dev/null || echo "000"
	)
	response=${response//[[:space:]]/}

	if [[ "$response" =~ ^(200|401|403)$ ]]; then
		pass "qBittorrent web UI responded with HTTP $response through the nginx proxy"
		return 0
	fi

	fail "qBittorrent web UI on localhost port $QBT_PORT returned HTTP $response"
	return 1
}

echo
info "=== qBittorrent Confinement Tests ==="
run_test "process_in_namespace" test_process_in_namespace || true
run_test "egress_differs_from_host" test_egress_differs_from_host || true
run_test "webui_reachable" test_webui_reachable || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run qBittorrent confinement tests passed"
else
	fail "$tests_passed/$tests_run qBittorrent confinement tests passed"
	exit 1
fi
