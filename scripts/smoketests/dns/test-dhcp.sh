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

info "check if DHCP port is open on firewall..."
ssh "$user@$ipaddr" 'sudo iptables -L -n -v | grep -E "dpt:67|dpt:68"'

info "check if AdGuard is listening on port 67..."
ssh "$user@$ipaddr" 'sudo ss -ulnp | grep :67'

# This test is inaccurate and will always fail if both DHCP servers are running
# on the same network at the same time.
#
# If I want to test this accurately, I should setup infra for creating a
# lightweight VM that can target specific DHCP server + virtual network.
# info "testing DHCP discover..."
# sudo dhcping -s "$ipaddr" -c "$(ipconfig getifaddr en0)" -t 5 -V

info "check that AdGuard logs DHCP requests..."
ssh "$user@$ipaddr" 'sudo journalctl -u adguardhome -n 20 | grep -i dhcp'

pass "all tests passed"
