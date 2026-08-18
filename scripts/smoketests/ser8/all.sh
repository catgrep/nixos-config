#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# ser8 smoketest entry point.
#
# deploy.yaml names exactly one script per host, so this is the only path
# `make smoketests-ser8` reaches. Before it existed the entry pointed straight
# at the media suite, which left the NordVPN checks unreachable on the deploy
# path and gave ser8 no host-level coverage at all.
#
# Fan-out goes through `run_suite` (scripts/smoketests/lib/fanout.sh) rather
# than a bare loop: a loop's exit status is that of its last iteration, so a
# failing media suite followed by a passing Home Assistant check would certify
# the activation. `run_suite` runs every entry and returns non-zero if any
# failed.
#
# The disruptive NordVPN kill-switch suite is deliberately absent from this
# array — it interrupts VPN connectivity, and it lives behind its own entry
# point under scripts/smoketests/nordvpn/ that nothing on the deploy path
# reaches.
#
# The household area joined this fan-out in Phase 10; it owns the Mealie checks
# and the household services that follow it in Phases 12-13.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="ser8"
TESTS=(
	./scripts/smoketests/media/all.sh
	./scripts/smoketests/household/all.sh
	./scripts/smoketests/nordvpn/all.sh
	./scripts/smoketests/ser8/test-zfs-health.sh
	./scripts/smoketests/ser8/test-vaapi.sh
	./scripts/smoketests/ser8/test-frigate.sh
	./scripts/smoketests/ser8/test-home-assistant.sh
)

run_suite "$@"
