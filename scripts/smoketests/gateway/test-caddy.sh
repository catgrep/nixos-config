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
CADDYFILE_PATH=./modules/gateway/Caddyfile
if ! diff -q <(ssh bdhill@192.168.0.88 'cat /etc/caddy/caddy_config') "${CADDYFILE_PATH}"; then
    warn "local and remote Caddyfiles differ"
    warn "fetching remote Caddyfile for testing"
    mkdir -p tmp
    ./tmp/Caddyfile <(ssh bdhill@192.168.0.88 'cat /etc/caddy/caddy_config')
    CADDYFILE_PATH=./tmp/Caddyfile
fi

info "extracting 'servers' and 'upstreams' from '${CADDYFILE_PATH}'..."
declare -A caddy_routes
while IFS='=' read -r server upstream; do
    caddy_routes["$server"]="$upstream"
done < <(
    caddy adapt --config "${CADDYFILE_PATH}" --adapter caddyfile | jq -r '
      .apps.http.servers.srv0.routes[] as $route |
      ($route.match[].host[] | tostring) + "=" +
      ($route.handle[].routes[].handle[].upstreams[].dial | tostring)
    '
)
info "extracted: ${!caddy_routes[*]}"

# Test each service
services_tested=0
services_passed=0

for server in "${!caddy_routes[@]}"; do
    upstream=${caddy_routes[$server]}
    info "testing route: $server -> $upstream"
    if redirects "$server" "$upstream"; then
        ((services_passed += 1))
    else
        # If service fails, check that host can connect to upstream
        fail "caddy failed to redirect"
        warn "checking backend connectivity for route: '$server -> $upstream'"
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
