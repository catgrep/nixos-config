#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

TESTS=(
    ./scripts/smoketests/nordvpn/test-veth-interfaces.sh
    ./scripts/smoketests/nordvpn/test-forwarding.sh
    ./scripts/smoketests/nordvpn/test-qbittorrent.sh
    ./scripts/smoketests/nordvpn/test-anonymity.sh
)

for test in "${TESTS[@]}"; do
    "${test}" "$@"
done
