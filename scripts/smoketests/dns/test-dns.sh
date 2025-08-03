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
resolves() {
    local domain="$1"
    local ipaddr="$2"

    info "check that '$(fmt_bold "$domain")' resolves"
    if nslookup "$domain" "$ipaddr"; then
        pass "resolved '$(fmt_bold "$domain")'"
    else
        fail "failed to resolve '$(fmt_bold "$domain")'"
    fi
}

# should resolve
if ! resolves google.com "$ipaddr"; then
    exit 1
fi

# test rewrites for internal services
# this should catch any post-installation configuration failures
info "check that internal services resolve"
domain_rewrites=$(ssh "$user@$ipaddr" 'sudo yq -r ".filtering.rewrites[].domain" /var/lib/AdGuardHome/AdGuardHome.yaml')
for domain in $domain_rewrites; do
    resolves "$domain" "$ipaddr"
    sleep 0.5
done

echo
pass "all tests passed"
