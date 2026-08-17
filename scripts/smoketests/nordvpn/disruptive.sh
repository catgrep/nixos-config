#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# DISRUPTIVE NordVPN suite — invoked by hand, never by a deploy.
#
# The kill-switch test in here brings the `wgnord` WireGuard interface DOWN
# and holds it down while it checks that traffic is blocked, then restores it
# and waits for the tunnel to re-establish. Expect VPN connectivity — and
# therefore qBittorrent's egress — to be interrupted for roughly twenty
# seconds per run.
#
# This suite is deliberately absent from deploy.yaml and from every Makefile
# target. Running it on every deploy would make a household outage part of the
# normal path. Run it only when the kill switch specifically needs verifying:
#
#     ./scripts/smoketests/nordvpn/disruptive.sh ser8
#
# The routine leak coverage lives in ./all.sh, whose confinement check proves
# qBittorrent egresses through the namespace without mutating anything.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="nordvpn-disruptive"
TESTS=(
	./scripts/smoketests/nordvpn/test-anonymity.sh
)

warn "this suite interrupts VPN connectivity for roughly 20 seconds"

run_suite "$@"
