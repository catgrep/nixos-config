#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Raspberry Pi smoketest entry point.
#
# The Pis have no services of their own to probe beyond what the base
# configuration promises every host: an account that can log in over ssh,
# sudo without a password for that account, and a Nix store the Mac can
# use as a remote builder. Each check is its own script so a failure names
# the layer that broke.
#
# Fan-out goes through `run_suite` (scripts/smoketests/lib/fanout.sh) so
# every check runs and the suite fails if any of them did.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

# shellcheck disable=SC2034 # read by run_suite in scripts/smoketests/lib/fanout.sh
SUITE_NAME="pi"
# shellcheck disable=SC2034 # read by run_suite in scripts/smoketests/lib/fanout.sh
TESTS=(
	./scripts/smoketests/pi/test-login.sh
	./scripts/smoketests/pi/test-sudo.sh
	./scripts/smoketests/pi/test-builder.sh
)

run_suite "$@"
