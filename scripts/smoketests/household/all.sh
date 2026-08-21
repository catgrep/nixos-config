#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Household services smoketest entry point.
#
# Covers the household-facing services that live on ser8 from Phase 10 onward:
# Mealie today, growing to Homebox, Actual, and Donetick in Phases 12-13. New
# household service checks belong in the TESTS array below rather than in the
# ser8 array, so the ser8 entry point stays a list of areas rather than a list
# of every individual script on the host.
#
# Reached from deploy.yaml through scripts/smoketests/ser8/all.sh; there is no
# separate deploy.yaml entry for this area and none is needed.
#
# Fan-out goes through `run_suite` (scripts/smoketests/lib/fanout.sh) rather
# than a bare loop: a loop's exit status is that of its last iteration, so a
# failing service check followed by a passing endpoint check would certify the
# activation. `run_suite` runs every entry and returns non-zero if any failed.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="household"
TESTS=(
	./scripts/smoketests/household/test-mealie-service.sh
	./scripts/smoketests/household/test-mealie-endpoint.sh
	./scripts/smoketests/household/test-homebox-service.sh
	./scripts/smoketests/household/test-homebox-endpoint.sh
	./scripts/smoketests/household/test-actual-service.sh
	./scripts/smoketests/household/test-actual-endpoint.sh
)

run_suite "$@"
