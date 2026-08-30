#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Backup engine smoketest entry point.
#
# The VM tests prove the mechanism works against a pool built from the
# declarations. These prove it is actually running on the live host, which is
# the one thing no test in tests/ can see: a snapshot that was really taken,
# a replica that really received it, a verification that really ran, and
# metrics that are really being scraped.
#
# Reached from deploy.yaml through scripts/smoketests/ser8/all.sh; there is no
# separate deploy.yaml entry for this area and none is needed.
#
# Every test here is read-only and fail-closed. An absent artifact, an
# unreachable host, empty command output or unparseable content is a failure,
# never a skip. That rule is not decoration: this repository already carries
# checks that pass while the thing they check is dead, and the entire value of
# this suite is that a backup engine which has quietly stopped cannot get a
# green deployment out of it.
#
# Fan-out goes through `run_suite` (scripts/smoketests/lib/fanout.sh) rather
# than a bare loop: a loop's exit status is that of its last iteration, so a
# failing freshness check followed by a passing metrics check would certify the
# activation. `run_suite` runs every entry and returns non-zero if any failed.

set -euo pipefail

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh
# shellcheck source=scripts/smoketests/lib/fanout.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="backup"
TESTS=(
	./scripts/smoketests/backup/test-snapshot-freshness.sh
	./scripts/smoketests/backup/test-replica-freshness.sh
	./scripts/smoketests/backup/test-dataset-properties.sh
	./scripts/smoketests/backup/test-verify-last-run.sh
	./scripts/smoketests/backup/test-manifest-coverage.sh
	./scripts/smoketests/backup/test-pgdump.sh
	./scripts/smoketests/backup/test-spot-integrity.sh
	./scripts/smoketests/backup/test-metrics.sh
	./scripts/smoketests/backup/test-no-stale-persist-dirs.sh
)

run_suite "$@"
