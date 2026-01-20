#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

TESTS=(
    ./scripts/smoketests/gateway/test-caddy.sh
    ./scripts/smoketests/gateway/test-tailscale.sh
)

for test in "${TESTS[@]}"; do
    "${test}" "$@"
done
