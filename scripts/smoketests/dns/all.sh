#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

TESTS=(
    ./scripts/smoketests/dns/test-dns.sh
    ./scripts/smoketests/dns/test-dhcp.sh
)

for test in "${TESTS[@]}"; do
    "${test}" "$@"
done
