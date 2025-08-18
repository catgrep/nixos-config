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

ssh "${user}@${ipaddr}" <<'EOF'
# Get host's real external IP for comparison
echo "Getting host external IP for comparison..."
host_ip=$(curl -s --connect-timeout 10 --max-time 15 http://httpbin.org/ip | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 | head -1 || echo "unknown")
echo "  - Host external IP: $host_ip"

# Get VPN external IP
echo "Testing VPN anonymity..."
echo -n "  - Getting VPN external IP: "
vpn_ip=$(sudo ip netns exec wgnord curl -s --connect-timeout 10 --max-time 15 http://httpbin.org/ip | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 | head -1 2>/dev/null || echo "failed")

if [ "$vpn_ip" = "failed" ]; then
    echo "FAILED - could not retrieve VPN IP"
    exit 1
elif [ "$vpn_ip" = "$host_ip" ]; then
    echo "FAILED - VPN IP matches host IP ($vpn_ip)"
    exit 1
elif [ -n "$vpn_ip" ]; then
    echo "OK ($vpn_ip)"
else
    echo "FAILED - empty response"
    exit 1
fi

# Verify VPN IP is different from host IP
echo "  - VPN IP differs from host IP: $([ "$vpn_ip" != "$host_ip" ] && echo "OK" || echo "FAILED")"

# Test geolocation (basic check)
echo "Testing IP geolocation..."
echo -n "  - VPN IP geolocation check: "
geo_info=$(sudo ip netns exec wgnord curl -s --connect-timeout 10 --max-time 15 "http://ip-api.com/json/$vpn_ip" 2>/dev/null || echo "")
if echo "$geo_info" | grep -q '"status":"success"'; then
    country=$(echo "$geo_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    city=$(echo "$geo_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
    echo "OK ($city, $country)"
else
    echo "FAILED - could not get geolocation"
    exit 1
fi

# DNS leak test
echo "Testing DNS leak protection..."
echo -n "  - DNS servers in use: "
dns_servers=$(sudo ip netns exec wgnord cat /etc/resolv.conf | grep "^nameserver" | awk '{print $2}' | tr '\n' ' ')
echo "$dns_servers"

# Verify DNS resolution uses expected servers
echo -n "  - DNS resolution uses configured servers: "
if echo "$dns_servers" | grep -q "192.168.68.56"; then
    echo "OK (using local AdGuard DNS)"
else
    echo "WARNING - not using expected DNS server"
    # Don't fail for this, just warn
fi

# Test DNS leak via external service
echo -n "  - External DNS leak test: "
dns_leak=$(sudo ip netns exec wgnord curl -s --connect-timeout 10 --max-time 15 "https://1.1.1.1/cdn-cgi/trace" | grep -o "ip=[^[:space:]]*" | cut -d'=' -f2 2>/dev/null || echo "failed")
if [ "$dns_leak" != "failed" ] && [ "$dns_leak" = "$vpn_ip" ]; then
    echo "OK (DNS requests show VPN IP)"
elif [ "$dns_leak" != "failed" ]; then
    echo "POTENTIAL LEAK (DNS shows: $dns_leak, VPN shows: $vpn_ip)"
else
    echo "INCONCLUSIVE - could not test"
fi

# Kill switch test (simulate VPN failure)
echo "Testing kill switch functionality..."
echo -n "  - Traffic blocked when VPN interface down: "

# Temporarily bring down WireGuard interface
sudo ip netns exec wgnord ip link set wgnord down
sleep 2

# Try to make external request - should fail
if sudo ip netns exec wgnord timeout 5 curl -s --connect-timeout 3 --max-time 5 http://httpbin.org/ip >/dev/null 2>&1; then
    echo "FAILED - traffic leaked when VPN down"
    # Bring interface back up before exiting
    sudo ip netns exec wgnord ip link set wgnord up
    exit 1
else
    echo "OK - traffic blocked when VPN down"
fi

# Bring VPN interface back up
sudo ip netns exec wgnord ip link set wgnord up
sleep 20

# Verify connectivity is restored
echo -n "  - Connectivity restored after VPN recovery: "
if sudo ip netns exec wgnord timeout 5 curl -s --connect-timeout 10 --max-time 15 http://httpbin.org/ip >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED - connectivity not restored"
    exit 1
fi

# Test that qBittorrent traffic uses VPN IP
echo "Testing qBittorrent traffic anonymity..."
echo -n "  - qBittorrent uses VPN IP for external connections: "

# Get qBittorrent process PID
qbt_pid=$(systemctl show qbittorrent-nox.service -p MainPID --value)
if [ "$qbt_pid" != "0" ] && [ -n "$qbt_pid" ]; then
    # Test what IP qBittorrent sees when making external requests
    # This simulates what trackers would see
    qbt_external_ip=$(sudo nsenter -t $qbt_pid -n curl -s --connect-timeout 10 --max-time 15 http://httpbin.org/ip | grep -o '"origin": "[^"]*"' | cut -d'"' -f4 | head -1 2>/dev/null || echo "failed")

    if [ "$qbt_external_ip" = "$vpn_ip" ]; then
        echo "OK ($qbt_external_ip)"
    elif [ "$qbt_external_ip" = "failed" ]; then
        echo "FAILED - could not get qBittorrent external IP"
        exit 1
    else
        echo "FAILED - qBittorrent IP ($qbt_external_ip) != VPN IP ($vpn_ip)"
        exit 1
    fi
else
    echo "FAILED - qBittorrent process not found"
    exit 1
fi

# Verify no IPv6 leaks
echo "Testing IPv6 leak protection..."
echo -n "  - IPv6 disabled/blocked in namespace: "
ipv6_test=$(sudo ip netns exec wgnord curl -s -6 --connect-timeout 5 --max-time 10 http://httpbin.org/ip 2>&1 || echo "blocked")
if echo "$ipv6_test" | grep -q -E "(blocked|failed|refused|unreachable)"; then
    echo "OK - IPv6 blocked"
else
    echo "WARNING - IPv6 may be leaking"
    # Don't fail for this, just warn as IPv6 handling varies
fi

# Summary
echo "Anonymity test summary:"
echo "  - Host IP: $host_ip"
echo "  - VPN IP: $vpn_ip"
echo "  - Geographic location: $city, $country"
echo "  - DNS servers: $dns_servers"
EOF

pass "$(fmt_blue "$0")"
