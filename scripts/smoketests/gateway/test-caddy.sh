#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Same guard as scripts/smoketests/lib/services.sh, deliberately the SAME
# variable name so one value governs every remaining pi4 lookup. 1 (the
# default) skips the retired `.vofi` DNS path; 0 attempts it. See that file
# for the full rationale.
SKIP_VOFI_DNS="${SKIP_VOFI_DNS:-1}"

# What this test asserts is that Caddy matches the route and reaches the
# upstream, so any answer from the application proves the route works. Codes
# outside the classic redirect set are the application's own behaviour, not a
# proxy fault: nzbget answers 401 (auth), sabnzbd 303 (login), and Home
# Assistant 400 (its allowed-hosts filter rejects the '.vofi' name) — each
# identical when the same upstream is queried directly. Only a 5xx, which is
# what Caddy returns when it cannot reach a backend, or 000 for no response at
# all, is a routing failure.
route_reached() {
	[[ "$1" =~ ^[1-4][0-9]{2}$ ]]
}

# test basic functionality
redirects() {
	local domain="$1"

	info "check that '$(fmt_bold "$domain")' redirects properly"

	# Exactly one of the two paths below runs, so each route contributes
	# exactly one result to the tally.
	local dns_resolved=1
	if [ "$SKIP_VOFI_DNS" != "0" ]; then
		# `curl --resolve` supplies the address itself, so no resolver is
		# consulted and pi4 is never contacted. That path is used rather than
		# the Host-header one because it sends SNI, which Caddy needs to select
		# the vhost's certificate; a Host header against the bare IP cannot
		# complete the TLS handshake at all.
		info "SKIPPED the '.vofi' DNS lookup for '$(fmt_bold "$domain")' (pi4 resolver retired, pending .vofi re-establishment); forcing the address with curl --resolve instead"
	else
		info "using host 'pi4' as the DNS server"
		dns_ipaddr=$(get_ip "pi4")
		# First check if we can resolve the domain using the AdGuard DNS server
		if ! nslookup "$domain" "$dns_ipaddr" >/dev/null 2>&1; then
			warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
			dns_resolved=0
		fi
	fi

	if [ "$dns_resolved" = "0" ]; then
		# Fall back to using IP with Host header
		local response
		local error_output

		if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
			response="$error_output"
			if route_reached "$response"; then
				pass "HTTPS for '$(fmt_bold "$domain")' responded with HTTP $response (via Host header)"
				return 0
			fi
		fi

		if error_output=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
			response="$error_output"
			if route_reached "$response"; then
				pass "HTTP for '$(fmt_bold "$domain")' responded with HTTP $response (via Host header)"
				return 0
			fi
		fi

		fail "failed to connect to '$(fmt_bold "$domain")' even with Host header fallback"
		return 1
	fi

	# DNS resolution worked, try curl with --resolve to force the IP
	local response
	local error_output

	if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$domain:443:$ipaddr" "https://$domain" --connect-timeout 5 --max-time 10 2>&1); then
		response="$error_output"
		if route_reached "$response"; then
			pass "HTTPS for '$(fmt_bold "$domain")' responded with HTTP $response"
			return 0
		else
			warn "HTTPS for '$(fmt_bold "$domain")' did not reach the upstream (HTTP $response); retrying over HTTP"
		fi
	fi

	# Fallback to HTTP with forced resolution
	if error_output=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$domain:80:$ipaddr" "http://$domain" --connect-timeout 5 --max-time 10 2>&1); then
		response="$error_output"
		if route_reached "$response"; then
			pass "HTTP for '$(fmt_bold "$domain")' responded with HTTP $response"
			return 0
		else
			fail "'$(fmt_bold "$domain")' did not reach its upstream (HTTP $response)"
			return 1
		fi
	else
		fail "failed to connect to '$(fmt_bold "$domain")'"
		return 1
	fi
}

# test caddy proxy services
info "checking caddy proxy services"

# Extract services from Caddyfile on the remote host.
#
# Temporary files rather than process substitution: `<(...)` needs /dev/fd,
# which sandboxed shells deny with "Operation not permitted", and the failure
# is reported as a test failure rather than an environment one.
deployed_caddyfile=$(mktemp)
adapted_routes=$(mktemp)
# shellcheck disable=SC2064 # expand the paths now, not at trap time
trap "rm -f '${deployed_caddyfile}' '${adapted_routes}'" EXIT

CADDYFILE_PATH=./modules/gateway/Caddyfile
ssh "${user}@${ipaddr}" 'cat /etc/caddy/caddy_config' >"${deployed_caddyfile}"
if ! diff -q "${deployed_caddyfile}" "${CADDYFILE_PATH}" >/dev/null; then
	warn "local and remote Caddyfiles differ"
	warn "testing the remote Caddyfile"
	warn "the routes below reflect what is DEPLOYED, not the working tree"
	CADDYFILE_PATH="${deployed_caddyfile}"
fi

info "extracting 'servers' and 'upstreams' from '${CADDYFILE_PATH}'..."
caddy adapt --config "${CADDYFILE_PATH}" --adapter caddyfile | jq -r '
      .apps.http.servers.srv0.routes[] as $route |
      ($route.match[].host[] | tostring) + "=" +
      ($route.handle[].routes[].handle[].upstreams[].dial | tostring)
    ' >"${adapted_routes}"
declare -A caddy_routes
while IFS='=' read -r server upstream; do
	caddy_routes["$server"]="$upstream"
done <"${adapted_routes}"
info "extracted: ${!caddy_routes[*]}"

# Test each service
services_tested=0
services_passed=0

for server in "${!caddy_routes[@]}"; do
	upstream=${caddy_routes[$server]}
	info "testing route: $server -> $upstream"
	if redirects "$server"; then
		((services_passed += 1))
	else
		# If service fails, check that host can connect to upstream
		fail "caddy failed to redirect"
		warn "checking backend connectivity for route: '$server -> $upstream'"
		# $upstream is deliberately expanded locally; the remote shell has no such variable.
		# shellcheck disable=SC2029
		if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://${upstream}" >/dev/null 2>&1; then
			fail "upstream '$upstream' is reachable, issue might be with Caddy config"
		else
			fail "upstream '$upstream' is not reachable from '$host'"
			warn "issue might be with '$host' DNS resolver"
		fi
	fi
	((services_tested += 1))
	sleep 0.5
done

echo
if [ $services_tested -eq 0 ]; then
	warn "no services were tested"
elif [ $services_passed -eq $services_tested ]; then
	pass "all $services_tested caddy proxy services passed"
else
	fail "$services_passed/$services_tested caddy proxy services passed"
	exit 1
fi

# Test that caddy is actually running
info "checking caddy service status"
if ssh "$user@$ipaddr" 'systemctl is-active --quiet caddy'; then
	pass "caddy service is running"
else
	fail "caddy service is not running"
	exit 1
fi

echo
pass "all tests passed"
