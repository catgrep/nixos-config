#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="gateway"
TESTS=(
	./scripts/smoketests/gateway/test-caddy.sh
	./scripts/smoketests/gateway/test-subgen.sh
	./scripts/smoketests/gateway/test-tailscale.sh
	./scripts/smoketests/gateway/test-alertmanager.sh
)

run_suite "$@"
