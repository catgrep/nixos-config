#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

# shellcheck disable=SC2034 # read by run_suite in scripts/smoketests/lib/fanout.sh
SUITE_NAME="gateway"
# shellcheck disable=SC2034 # read by run_suite in scripts/smoketests/lib/fanout.sh
TESTS=(
	./scripts/smoketests/gateway/test-caddy.sh
	./scripts/smoketests/gateway/test-subgen.sh
	./scripts/smoketests/gateway/test-tailscale.sh
	./scripts/smoketests/gateway/test-alertmanager.sh
	./scripts/smoketests/gateway/test-service-monitoring.sh
	./scripts/smoketests/gateway/test-litter-box.sh
)

run_suite "$@"
