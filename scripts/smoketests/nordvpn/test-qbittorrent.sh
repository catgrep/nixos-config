#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "$0"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <host>"
    exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

ssh "${user}@${ipaddr}" <<'EOF'
# Check qBittorrent service is running in VPN namespace
echo "Checking qBittorrent service status..."
echo -n "  - qbittorrent-nox.service is active: "
if systemctl is-active --quiet qbittorrent-nox.service; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Verify qBittorrent is actually running in the VPN namespace
echo "Verifying qBittorrent runs in VPN namespace..."
echo -n "  - qBittorrent process in wgnord namespace: "
qbt_pid=$(systemctl show qbittorrent-nox.service -p MainPID --value)
if [ "$qbt_pid" != "0" ] && [ -n "$qbt_pid" ]; then
    # Check if the process is in the wgnord network namespace
    if sudo ls -la /proc/$qbt_pid/ns/net | grep -q "$(sudo ip netns identify $$qbt_pid 2>/dev/null || echo 'wgnord')"; then
        echo "OK"
    else
        # Alternative check: see if process can see VPN interface
        if sudo nsenter -t $qbt_pid -n ip link show wgnord >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAILED - process not in VPN namespace"
            exit 1
        fi
    fi
else
    echo "FAILED - no qBittorrent process found"
    exit 1
fi

# Check qBittorrent is listening on the correct interface in namespace
echo "Checking qBittorrent network binding..."
echo -n "  - qBittorrent listening on port 8080 in namespace: "
if sudo ip netns exec wgnord ss -tlnp | grep -q ":8080.*qbittorrent"; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Test web UI accessibility from host
echo "Testing qBittorrent web UI accessibility..."
echo -n "  - Web UI accessible from host (localhost:8080): "
response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:8080 2>/dev/null || echo "000")
if [[ "$response" =~ ^(200|401|403)$ ]]; then
    echo "OK (HTTP $response)"
else
    echo "FAILED (HTTP $response)"
    exit 1
fi

# Test web UI accessibility via veth bridge
echo -n "  - Web UI accessible via veth bridge (192.168.100.2:8080): "
response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://192.168.100.2:8080 2>/dev/null || echo "000")
if [[ "$response" =~ ^(200|401|403)$ ]]; then
    echo "OK (HTTP $response)"
else
    echo "FAILED (HTTP $response)"
    exit 1
fi

# Test qBittorrent API endpoint
echo "Testing qBittorrent API functionality..."
echo -n "  - API endpoint responds: "
response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:8080/api/v2/app/version 2>/dev/null || echo "000")
if [[ "$response" =~ ^(200|401|403)$ ]]; then
    echo "OK (HTTP $response)"
else
    echo "FAILED (HTTP $response)"
    exit 1
fi

# Test connectivity from other media services (simulate Sonarr/Radarr connection)
echo "Testing service-to-service connectivity..."
echo -n "  - qBittorrent reachable from host network: "
# Test that other services can reach qBittorrent API
api_response=$(curl -s --connect-timeout 5 --max-time 10 http://localhost:8080/api/v2/app/buildInfo 2>/dev/null || echo "")
if [ -n "$api_response" ]; then
    echo "OK"
else
    echo "FAILED - API not reachable"
    exit 1
fi

# Check qBittorrent can reach external trackers (simulated)
echo "Testing qBittorrent external connectivity..."
echo -n "  - External connectivity from qBittorrent namespace: "
# Test that qBittorrent can reach external services (like trackers)
if sudo ip netns exec wgnord curl -s --connect-timeout 5 --max-time 10 http://httpbin.org/ip >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi

# Verify qBittorrent's download directory is accessible
echo "Testing qBittorrent storage access..."
echo -n "  - Download directory accessible: "
download_dir=$(sudo -u qbittorrent ls -la /mnt/media/downloads 2>/dev/null || echo "")
if [ -n "$download_dir" ]; then
    echo "OK"
else
    echo "FAILED - download directory not accessible"
    exit 1
fi

# Check qBittorrent logs for any obvious errors
echo "Checking qBittorrent service health..."
echo -n "  - No critical errors in recent logs: "
recent_errors=$(sudo journalctl -u qbittorrent-nox.service --since "5 minutes ago" --no-pager -q | grep -i -E "(error|failed|fatal)" | wc -l)
if [ "$recent_errors" -eq 0 ]; then
    echo "OK"
else
    echo "WARNING - $recent_errors recent errors in logs"
    # Don't fail the test for this, just warn
fi
EOF

pass "$(fmt_blue "$0")"
