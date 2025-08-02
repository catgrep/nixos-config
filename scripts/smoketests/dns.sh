#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh

set -euo pipefail

title "$0"

cleanup_hook() {
    error "$0: failed"
}

if [ $# -lt 1 ]; then
    info "Usage: $0 <host>"
    exit 1
fi

host="$1"
dns_ip=$(get_ip "$host")
user=$(get_user "$host")

# test basic functionality
resolves() {
    local domain="$1"
    local dns_ip="$2"

    info "check that '$domain' resolves"
    if nslookup "$domain" "$dns_ip"; then
        success "resolved '$domain'"
    else
        error "failed to resolve '$domain'"
    fi
}

# should resolve
if ! resolves google.com "$dns_ip"; then
    exit 1
fi

# test rewrites for internal services
# this should catch any post-installation configuration failures
info "check that internal services resolve"
domain_rewrites=$(ssh "$user@$dns_ip" 'sudo yq -r ".filtering.rewrites[].domain" /var/lib/AdGuardHome/AdGuardHome.yaml')
for domain in $domain_rewrites; do
    resolves "$domain" "$dns_ip"
    sleep 0.5
done

echo
success "all tests passed"
