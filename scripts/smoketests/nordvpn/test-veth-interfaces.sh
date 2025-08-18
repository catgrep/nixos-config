#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

cleanup_hook() {
    fail "VPN interface infrastructure test failed"
}

title "$0"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <host>"
    exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

ssh "${user}@${ipaddr}" <<'EOF'
# Check systemd services are running
echo "Checking systemd service states..."

echo -n "  - wgnord.service: "
if systemctl is-active --quiet wgnord.service; then
    echo "ACTIVE"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - wgnord-monitor.service: "
if systemctl is-active --quiet wgnord-monitor.service; then
    echo "ACTIVE"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - netns@wgnord.service: "
if systemctl is-active --quiet netns@wgnord.service; then
    echo "ACTIVE"
else
    echo "FAILED"
    exit 1
fi

# Check network namespace exists
echo "Checking network namespace..."
echo -n "  - wgnord namespace exists: "
if sudo ip netns list | grep -q "wgnord"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check veth interfaces exist
echo "Checking veth bridge interfaces..."
echo -n "  - veth-host interface exists: "
if ip link show veth-host >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - veth-vpn interface exists in namespace: "
if sudo ip netns exec wgnord ip link show veth-vpn >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check WireGuard interface exists
echo "Checking WireGuard interface..."
echo -n "  - wgnord interface exists in namespace: "
if sudo ip netns exec wgnord ip link show wgnord >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check IP addresses are assigned correctly
echo "Checking IP address assignments..."
echo -n "  - veth-host has IP 192.168.100.1: "
if ip addr show veth-host | grep -q "192.168.100.1/24"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - veth-vpn has IP 192.168.100.2 in namespace: "
if sudo ip netns exec wgnord ip addr show veth-vpn | grep -q "192.168.100.2/24"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - wgnord has VPN IP assigned: "
if sudo ip netns exec wgnord ip addr show wgnord | grep -q "10.5.0.2/32"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check WireGuard is actually configured
echo "Checking WireGuard configuration..."
echo -n "  - WireGuard interface is up: "
if sudo ip netns exec wgnord wg show wgnord >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Check basic connectivity within namespace
echo "Checking basic namespace connectivity..."
echo -n "  - Loopback ping in namespace: "
if sudo ip netns exec wgnord ping -c 1 -W 2 127.0.0.1 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

echo -n "  - Self ping (VPN interface): "
if sudo ip netns exec wgnord ping -c 1 -W 2 10.5.0.2 >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi
EOF

pass "$(fmt_blue "$0")"
