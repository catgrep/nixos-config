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

# test basic functionality
redirects() {
    local domain="$1"
    local expected_backend="$2"

    info "check that '$(fmt_bold "$domain")' redirects properly"

    # First check if we can resolve the domain using the AdGuard DNS server
    if ! nslookup "$domain" 192.168.0.10 >/dev/null 2>&1; then
        warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
        # Fall back to using IP with Host header
        local response
        local error_output

        if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
            response="$error_output"
            if [[ "$response" =~ ^[0-9]{3}$ ]] && [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "HTTPS redirect for '$(fmt_bold "$domain")' responded with HTTP $response (via Host header)"
                return 0
            fi
        fi

        if error_output=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$ipaddr" --connect-timeout 5 --max-time 10 2>&1); then
            response="$error_output"
            if [[ "$response" =~ ^[0-9]{3}$ ]] && [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "HTTP redirect for '$(fmt_bold "$domain")' responded with HTTP $response (via Host header)"
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
        if [[ "$response" =~ ^[0-9]{3}$ ]]; then
            if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "HTTPS redirect for '$(fmt_bold "$domain")' responded with HTTP $response"
                return 0
            else
                warn "HTTPS for '$(fmt_bold "$domain")' returned unexpected code: $response"
            fi
        else
            warn "HTTPS for '$(fmt_bold "$domain")' failed: $error_output"
        fi
    fi

    # Fallback to HTTP with forced resolution
    if error_output=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$domain:80:$ipaddr" "http://$domain" --connect-timeout 5 --max-time 10 2>&1); then
        response="$error_output"
        if [[ "$response" =~ ^[0-9]{3}$ ]]; then
            if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
                pass "HTTP redirect for '$(fmt_bold "$domain")' responded with HTTP $response"
                return 0
            else
                fail "HTTP for '$(fmt_bold "$domain")' returned unexpected code: $response"
                return 1
            fi
        else
            fail "failed to connect to '$(fmt_bold "$domain")': $error_output"
            return 1
        fi
    else
        fail "failed to connect to '$(fmt_bold "$domain")'"
        return 1
    fi
}

# test caddy proxy services
info "checking caddy proxy services"

# Extract services from Caddyfile on the remote host
caddy_services=$(ssh "$user@$ipaddr" '
    if [ -f /etc/caddy/Caddyfile ]; then
        # Parse domains from Caddyfile (lines that end with {)
        grep "^[a-zA-Z0-9.-]\+.*{$" /etc/caddy/Caddyfile | sed "s/[[:space:]]*{$//" | tr -d " "
    elif [ -f /etc/caddy/caddy_config ]; then
        # Parse from generated config file
        grep "^[a-zA-Z0-9.-]\+.*{$" /etc/caddy/caddy_config | sed "s/[[:space:]]*{$//" | tr -d " "
    else
        echo ""
    fi
' 2>/dev/null || echo "")

if [ -z "$caddy_services" ]; then
    warn "could not find caddy configuration file or parse services"
    info "attempting to test common services anyway"
    caddy_services="jellyfin.vofi.app adguard.internal grafana.vofi.app prometheus.vofi.app"
fi

# Test each service
services_tested=0
services_passed=0

for domain in $caddy_services; do
    if [ -n "$domain" ]; then
        info "testing service: $domain"
        if redirects "$domain" ""; then
            ((services_passed += 1))
        else
            # If service fails, check backend connectivity
            backend=$(ssh "$user@$ipaddr" "grep -A5 '^$domain' /etc/caddy/Caddyfile | grep 'reverse_proxy' | awk '{print \$2}'" 2>/dev/null || echo "unknown")
            if [ "$backend" != "unknown" ] && [ -n "$backend" ]; then
                warn "checking backend connectivity for $domain -> $backend"
                if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' http://$backend" >/dev/null 2>&1; then
                    warn "backend $backend is reachable, issue might be with Caddy config"
                else
                    warn "backend $backend is not reachable from $host"
                fi
            fi
        fi
        ((services_tested += 1))
        sleep 0.5
    fi
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
