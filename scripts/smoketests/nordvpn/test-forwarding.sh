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
# Check veth bridge connectivity
echo "Testing veth bridge connectivity..."
echo -n "  - Host to VPN namespace (192.168.100.2): "
if ping -c 1 -W 2 192.168.100.2 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - VPN namespace to host (192.168.100.1): "
if sudo ip netns exec wgnord ping -c 1 -W 2 192.168.100.1 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check DNS resolution in namespace
echo "Testing DNS resolution in VPN namespace..."
echo -n "  - Local AdGuard DNS (192.168.68.56): "
if sudo ip netns exec wgnord ping -c 1 -W 2 192.168.68.56 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - DNS resolution test (google.com): "
if sudo ip netns exec wgnord nslookup google.com >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check external connectivity through VPN
echo "Testing external connectivity through VPN..."
echo -n "  - External ping (8.8.8.8): "
if sudo ip netns exec wgnord ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check WireGuard handshake
echo "Testing WireGuard handshake..."
echo -n "  - Recent WireGuard handshake: "
latest_handshake=$(sudo ip netns exec wgnord wg show wgnord latest-handshakes | awk '{print $2}')
current_time=$(date +%s)
time_diff=$((current_time - latest_handshake))

if [ $time_diff -lt 300 ]; then  # Less than 5 minutes ago
    echo "OK (${time_diff}s ago)"
else
    echo "STALE (${time_diff}s ago)"
    # Try to trigger handshake
    sudo ip netns exec wgnord ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || true
    sleep 2
    latest_handshake=$(sudo ip netns exec wgnord wg show wgnord latest-handshakes | awk '{print $2}')
    time_diff=$((current_time - latest_handshake))
    if [ $time_diff -lt 60 ]; then
        echo "OK after refresh (${time_diff}s ago)"
    else
        echo "FAILED - no recent handshake"
        exit 1
    fi
fi

# Check port forwarding rules
echo "Testing port forwarding configuration..."
echo -n "  - IPTables PREROUTING rule for port 8080: "
if sudo iptables -t nat -L PREROUTING -n -v | grep -q "192.168.100.2.*:8080"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - IPTables OUTPUT rule for port 8080: "
if sudo iptables -t nat -L OUTPUT -n -v | grep -q "192.168.100.2.*:8080"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test that port 8080 is being forwarded
echo "Testing port forwarding functionality..."
echo -n "  - Port 8080 forwarding to VPN namespace: "
# Check if something is listening on 8080 in the namespace
if sudo ip netns exec wgnord ss -tlnp | grep -q ":8080"; then
    # Try to connect from host to test forwarding
    if timeout 5 bash -c '</dev/tcp/192.168.100.2/8080' 2>/dev/null; then
        echo "OK"
    else
        echo "PARTIAL (service in namespace but forwarding issue)"
    fi
else
    echo "NO SERVICE (nothing listening on 8080 in namespace)"
fi

# Check routing table in namespace
echo "Verifying VPN namespace routing..."
echo "  - Routing table in namespace:"
sudo ip netns exec wgnord ip route show | sed 's/^/    /'

# Test traffic actually goes through VPN
echo "Testing traffic routing through VPN..."
echo -n "  - Traffic uses VPN interface: "
# Capture packets on WireGuard interface while doing external request
capture_output=$(sudo timeout 3 ip netns exec wgnord tcpdump -i wgnord -c 1 -n 2>/dev/null &
sleep 0.5
sudo ip netns exec wgnord curl -s --max-time 2 http://httpbin.org/ip >/dev/null 2>&1 || true
wait) 2>/dev/null

if echo "$capture_output" | grep -q "packets captured"; then
    echo "OK"
else
    echo "FAILED - no traffic on VPN interface"
    exit 1
fi
EOF

pass "$(fmt_blue "$0")"
