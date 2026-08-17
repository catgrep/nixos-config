#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Routine NordVPN suite. Every test here is read-only: nothing brings an
# interface down, restarts a unit, or alters a route. That is what makes it
# safe to run on every deploy.
#
# The kill-switch test is deliberately NOT here — it interrupts VPN
# connectivity and lives in ./disruptive.sh, invoked by hand.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="nordvpn"
TESTS=(
	./scripts/smoketests/nordvpn/test-veth-interfaces.sh
	./scripts/smoketests/nordvpn/test-forwarding.sh
	./scripts/smoketests/nordvpn/test-qbittorrent.sh
	./scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh
)

run_suite "$@"
