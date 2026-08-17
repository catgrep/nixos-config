#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Common service testing functions for media smoketests

# Guard for the retired `.vofi` DNS path.
#
# pi4 runs the AdGuard resolver that answers the `.vofi` names, and it is
# physically disconnected pending retirement or repurposing. While this guard
# is active nothing here contacts pi4; every service is tested through the
# Host-header path the helper already falls back to.
#
#   SKIP_VOFI_DNS=1  (default) skip the pi4 lookup entirely
#   SKIP_VOFI_DNS=0            attempt the pi4 lookup, as before
#
# Phase 10 re-enables the DNS path by setting this to 0 once `.vofi` ownership
# is re-established. The gateway's Caddy test reads the SAME variable, so one
# value governs every remaining pi4 lookup — do not add a second name.
SKIP_VOFI_DNS="${SKIP_VOFI_DNS:-1}"

# Reaches the gateway by address and names the vhost in a Host header, which
# does not need the `.vofi` resolver to answer.
_try_host_header() {
	local domain="$1"
	local service_name="$2"
	local response

	if response=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
		if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
			pass "$service_name HTTPS responded with HTTP $response (via Host header)"
			return 0
		fi
	fi

	if response=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
		if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
			pass "$service_name HTTP responded with HTTP $response (via Host header)"
			return 0
		fi
	fi

	fail "failed to connect to $service_name at '$(fmt_bold "$domain")' even with Host header fallback"
	return 1
}

# Connects to the address the `.vofi` resolver actually returned, so a pass
# here attributes to the resolver under test rather than to the system one.
_try_resolved_address() {
	local domain="$1"
	local service_name="$2"
	local resolved="$3"
	local response

	if response=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$domain:443:$resolved" "https://$domain" --connect-timeout 5 --max-time 10 2>&1); then
		if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
			pass "$service_name HTTPS responded with HTTP $response (resolved to $resolved)"
			return 0
		fi
		warn "$service_name HTTPS returned unexpected code: $response"
	fi

	if response=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$domain:80:$resolved" "http://$domain" --connect-timeout 5 --max-time 10 2>&1); then
		if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
			pass "$service_name HTTP responded with HTTP $response (resolved to $resolved)"
			return 0
		fi
		fail "$service_name HTTP returned unexpected code: $response"
		return 1
	fi

	fail "failed to connect to $service_name at '$(fmt_bold "$domain")'"
	return 1
}

test_service() {
	local domain="$1"
	local service_name="$2"

	info "testing $service_name connectivity at '$(fmt_bold "$domain")'"

	# Exactly one of the two paths below runs, so each service contributes
	# exactly one result to the caller's tally.
	if [ "$SKIP_VOFI_DNS" != "0" ]; then
		info "$service_name: SKIPPED the '.vofi' DNS path (pi4 resolver retired, pending .vofi re-establishment); testing via Host header instead"
		_try_host_header "$domain" "$service_name"
		return
	fi

	info "using host 'pi4' as the DNS server"
	local dns_ipaddr resolved
	dns_ipaddr=$(get_ip "pi4")

	resolved=$(nslookup "$domain" "$dns_ipaddr" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
	if [ -z "$resolved" ]; then
		warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
		_try_host_header "$domain" "$service_name"
		return
	fi

	_try_resolved_address "$domain" "$service_name" "$resolved"
}

test_media_service() {
	local service_name="$1"
	local domain="$2"
	local port="$3"
	local systemd_service="$4"
	local host="$5"
	local ipaddr="$6"
	local user="$7"

	info "testing $service_name media service"

	# If no domain is provided, skip the gateway test and only test local service
	if [[ -z "$domain" ]]; then
		warn "$service_name not exposed via gateway, testing local service only"
		# $port is deliberately expanded locally; the remote shell has no such variable.
		# shellcheck disable=SC2029
		if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:$port" >/dev/null 2>&1; then
			pass "$service_name backend is running locally on port $port"
		else
			fail "$service_name backend is not running on $host"
			warn "check $service_name service status: systemctl status $systemd_service"
			return 1
		fi
	else
		# Test via gateway
		if test_service "$domain" "$service_name"; then
			pass "$service_name connectivity test passed"
		else
			# Check if the backend service is running on the host
			warn "checking if $service_name backend is running on $host"
			# $port is deliberately expanded locally; the remote shell has no such variable.
			# shellcheck disable=SC2029
			if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://localhost:$port" >/dev/null 2>&1; then
				fail "$service_name backend is reachable locally, issue might be with gateway routing"
			else
				fail "$service_name backend is not running on $host"
				warn "check $service_name service status: systemctl status $systemd_service"
			fi
			return 1
		fi
	fi

	return 0
}
