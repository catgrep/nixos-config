#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

TESTS=(
    ./scripts/smoketests/nordvpn/test-netns.sh
)

for test in "${TESTS[@]}"; do
    "${test}" "$@"
done
