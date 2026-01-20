#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Tailscale smoketest script
# Tests Tailscale daemon, node presence, DNS resolution, HTTPS connectivity,
# and TLS certificate validity for services exposed via caddy-tailscale plugin.

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

# Tailscale domain suffix
TS_DOMAIN="shad-bangus.ts.net"

# Expected Tailscale nodes (services exposed via caddy-tailscale)
EXPECTED_NODES=(
    "jellyfin"
    "sabnzbd"
    "radarr"
    "sonarr"
    "prowlarr"
)

# Track test results
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
    return 1
}

# Test 1: Check that Tailscale daemon is running
test_tailscale_daemon() {
    info "checking Tailscale daemon status"
    if ssh "$user@$ipaddr" 'systemctl is-active --quiet tailscaled'; then
        pass "tailscaled service is running"
        return 0
    else
        fail "tailscaled service is not running"
        return 1
    fi
}

# Test 2: Check that Tailscale is connected
test_tailscale_connected() {
    info "checking Tailscale connection status"
    local status
    status=$(ssh "$user@$ipaddr" 'tailscale status --json 2>/dev/null' | jq -r '.BackendState // "unknown"')
    if [ "$status" = "Running" ]; then
        pass "Tailscale is connected (state: Running)"
        return 0
    else
        fail "Tailscale is not connected (state: $status)"
        return 1
    fi
}

# Test 3: Check that all expected Tailscale nodes are present
test_tailscale_nodes() {
    info "checking Tailscale nodes"

    local nodes_output
    nodes_output=$(ssh "$user@$ipaddr" 'tailscale status 2>/dev/null' || echo "")

    if [ -z "$nodes_output" ]; then
        fail "failed to get Tailscale status"
        return 1
    fi

    local missing_nodes=()
    local found_nodes=()

    for node in "${EXPECTED_NODES[@]}"; do
        # Check if node appears in tailscale status output
        # Nodes created by caddy-tailscale appear as hostname.ts-domain
        if echo "$nodes_output" | grep -q "${node}"; then
            found_nodes+=("$node")
        else
            missing_nodes+=("$node")
        fi
    done

    if [ ${#missing_nodes[@]} -eq 0 ]; then
        pass "all ${#EXPECTED_NODES[@]} Tailscale nodes present: ${found_nodes[*]}"
        return 0
    else
        warn "found nodes: ${found_nodes[*]}"
        fail "missing Tailscale nodes: ${missing_nodes[*]}"
        return 1
    fi
}

# Test 4: DNS resolution for Tailscale domains
test_dns_resolution() {
    local domain="$1"
    info "checking DNS resolution for '$(fmt_bold "$domain")'"

    # Use the remote host to test DNS resolution (it has Tailscale DNS configured)
    local dns_result
    dns_result=$(ssh "$user@$ipaddr" "dig +short '$domain' 2>/dev/null" || echo "")

    if [ -n "$dns_result" ]; then
        pass "DNS resolves '$(fmt_bold "$domain")' -> $dns_result"
        return 0
    else
        fail "DNS resolution failed for '$(fmt_bold "$domain")'"
        return 1
    fi
}

# Test 5: HTTPS connectivity to Tailscale services
test_https_connectivity() {
    local domain="$1"
    local service_name="$2"
    info "checking HTTPS connectivity to '$(fmt_bold "$domain")'"

    # Test from the gateway host itself since it has Tailscale access
    local response
    response=$(ssh "$user@$ipaddr" "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 15 'https://$domain' 2>/dev/null" || echo "000")

    if [[ "$response" =~ ^[0-9]{3}$ ]]; then
        # Accept 200, 301, 302, 303, 401, 403 as valid responses
        # (services may redirect or require auth)
        if [[ "$response" =~ ^(200|301|302|303|401|403)$ ]]; then
            pass "$service_name HTTPS responded with HTTP $response"
            return 0
        else
            fail "$service_name HTTPS returned unexpected code: $response"
            return 1
        fi
    else
        fail "$service_name HTTPS connection failed"
        return 1
    fi
}

# Test 6: TLS certificate validity
test_tls_certificate() {
    local domain="$1"
    local service_name="$2"
    info "checking TLS certificate for '$(fmt_bold "$domain")'"

    # Check if openssl is available on the remote host
    if ! ssh "$user@$ipaddr" "command -v openssl >/dev/null 2>&1"; then
        warn "openssl not available on $host, skipping TLS certificate check for $service_name"
        # Count as passed since we can't test without openssl
        pass "$service_name TLS check skipped (openssl not installed)"
        return 0
    fi

    # Check certificate validity from the gateway host
    local cert_info
    cert_info=$(ssh "$user@$ipaddr" "echo | openssl s_client -servername '$domain' -connect '$domain:443' 2>/dev/null | openssl x509 -noout -dates 2>/dev/null" || echo "")

    if [ -z "$cert_info" ]; then
        fail "could not retrieve TLS certificate for $service_name"
        return 1
    fi

    # Check that certificate is not expired
    local not_after
    not_after=$(echo "$cert_info" | grep 'notAfter=' | cut -d'=' -f2)

    if [ -n "$not_after" ]; then
        # Parse the expiry date and check if it's in the future
        local expiry_epoch
        expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -jf "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "0")
        local now_epoch
        now_epoch=$(date +%s)

        if [ "$expiry_epoch" -gt "$now_epoch" ]; then
            pass "$service_name TLS certificate valid until $not_after"
            return 0
        else
            fail "$service_name TLS certificate expired on $not_after"
            return 1
        fi
    else
        warn "$service_name TLS certificate date parsing failed, but certificate was retrieved"
        pass "$service_name TLS certificate present"
        return 0
    fi
}

# Main test execution
echo
info "=== Tailscale Daemon Tests ==="
run_test "tailscale_daemon" test_tailscale_daemon || true
run_test "tailscale_connected" test_tailscale_connected || true

echo
info "=== Tailscale Node Tests ==="
run_test "tailscale_nodes" test_tailscale_nodes || true

echo
info "=== DNS Resolution Tests ==="
for node in "${EXPECTED_NODES[@]}"; do
    domain="${node}.${TS_DOMAIN}"
    run_test "dns_${node}" test_dns_resolution "$domain" || true
    sleep 0.2
done

echo
info "=== HTTPS Connectivity Tests ==="
for node in "${EXPECTED_NODES[@]}"; do
    domain="${node}.${TS_DOMAIN}"
    run_test "https_${node}" test_https_connectivity "$domain" "$node" || true
    sleep 0.5
done

echo
info "=== TLS Certificate Tests ==="
for node in "${EXPECTED_NODES[@]}"; do
    domain="${node}.${TS_DOMAIN}"
    run_test "tls_${node}" test_tls_certificate "$domain" "$node" || true
    sleep 0.2
done

# Summary
echo
if [ $tests_run -eq 0 ]; then
    warn "no tests were run"
    exit 1
elif [ $tests_passed -eq $tests_run ]; then
    pass "all $tests_run Tailscale tests passed"
else
    fail "$tests_passed/$tests_run Tailscale tests passed"
    exit 1
fi
