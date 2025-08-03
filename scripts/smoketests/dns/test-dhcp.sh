#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "$0"

# Build and run with host networking
docker build --platform=linux/arm64 -f ./scripts/smoketests/dns/Dockerfile -t dhcp-test .
docker run -i --rm --entrypoint sh --network host --privileged dhcp-test <<'EOF'
#!/usr/bin/env bash
set -e

echo "Requesting DHCP lease..."
dhclient -v eth0

echo "Current network config:"
ip addr show
cat /etc/resolv.conf

echo "Testing DNS resolution..."
nslookup google.com
nslookup jellyfin.homelab
nslookup pi4.internal

echo "Testing ad blocking..."
nslookup doubleclick.net
EOF

pass "all tests passed"
