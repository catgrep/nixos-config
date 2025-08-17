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
echo "1. WireGuard Interface Status:"
sudo ip netns exec wgnord wg show
echo ""

echo "2. IP Addresses in namespace:"
sudo ip netns exec wgnord ip addr show
echo ""

echo "3. Routing table in namespace:"
sudo ip netns exec wgnord ip route show
echo ""

echo "4. DNS Config:"
sudo ip netns exec wgnord cat /etc/resolv.conf
echo ""

echo "5. Ping tests:"
echo -n "  - Ping VPN interface (10.5.0.2): "
sudo ip netns exec wgnord ping -c 1 -W 2 10.5.0.2 &>/dev/null && echo "OK" || echo "FAILED"

echo -n "  - Ping veth bridge (192.168.100.1): "
sudo ip netns exec wgnord ping -c 1 -W 2 192.168.100.1 &>/dev/null && echo "OK" || echo "FAILED"

echo -n "  - Ping local DNS (192.168.68.56): "
sudo ip netns exec wgnord ping -c 1 -W 2 192.168.68.56 &>/dev/null && echo "OK" || echo "FAILED"

echo -n "  - Ping 8.8.8.8: "
sudo ip netns exec wgnord ping -c 1 -W 2 8.8.8.8 &>/dev/null && echo "OK" || echo "FAILED"
echo ""

echo "6. Checking if packets are being sent through WireGuard:"
sudo ip netns exec wgnord wg show wgnord latest-handshakes
echo ""

echo "7. Testing with tcpdump (5 seconds):"
echo "Starting packet capture on wgnord interface..."
sudo timeout 5 ip netns exec wgnord tcpdump -i wgnord -c 5 -n &
sleep 1
sudo ip netns exec wgnord ping -c 3 -W 1 8.8.8.8 &>/dev/null
wait
echo ""

echo "8. Host-side veth status:"
ip addr show veth-host
echo ""

echo "9. IPTables NAT rules:"
sudo iptables -t nat -L PREROUTING -n -v | grep 192.168.100.2
sudo iptables -t nat -L OUTPUT -n -v | grep 192.168.100.2
echo ""

echo "10. Testing DNS resolution:"
sudo ip netns exec wgnord nslookup google.com 2>&1 | head -10
echo ""

echo "11. WireGuard config file:"
sudo grep -E '^(PrivateKey|Address|PublicKey|Endpoint)' /var/lib/wgnord/wgnord.conf | sed 's/PrivateKey.*/PrivateKey = [REDACTED]/'

echo "12. wgnord.service logs"
sudo journalctl -u wgnord.service --no-pager -n 50

echo "13. wgnord-monitor.service logs"
sudo journalctl -u wgnord-monitor.service --no-pager -n 50

echo "14. Connect to qBitTorrent"
curl -v http://localhost:8080

echo "15. NordVPN Status"
sudo nordvpn-status
EOF
