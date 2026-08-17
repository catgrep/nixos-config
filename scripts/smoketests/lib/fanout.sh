#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Shared fan-out helper for smoketest suite entry points.
#
# Sourced, never executed: this file sets no shell options of its own,
# matching scripts/smoketests/lib/services.sh. The caller owns them.
#
# Calling contract
# ----------------
#   . ./scripts/lib/all.sh
#   . ./scripts/smoketests/lib/fanout.sh
#
#   SUITE_NAME="nordvpn"
#   TESTS=(
#       ./scripts/smoketests/nordvpn/test-veth-interfaces.sh
#   )
#   run_suite "$@"
#
# The caller defines a `TESTS` array of script paths and an optional
# `SUITE_NAME` label (defaults to "smoketest"), then calls `run_suite`
# forwarding its own arguments — conventionally the host name, which is
# passed through to every test unchanged.
#
# `run_suite` runs EVERY entry even after one fails, so a single deploy
# attempt surfaces every broken subsystem rather than only the earliest.
# It prints one summary line naming the suite and the pass tally through
# the shared logging helpers, and returns non-zero if ANY test failed.
#
# The return status is the whole deployment gate: Makefile's `smoketests-%`
# target invokes exactly one script per host and propagates its exit status.
# A suite whose status is merely that of its last test silently certifies
# activations that were never verified.

run_suite() {
	local suite="${SUITE_NAME:-smoketest}"
	local tests_run=0
	local tests_passed=0
	local failed=()
	local test

	if [ "${#TESTS[@]}" -eq 0 ]; then
		fail "suite '$suite' defines no tests"
		return 1
	fi

	for test in "${TESTS[@]}"; do
		tests_run=$((tests_run + 1))
		if "$test" "$@"; then
			tests_passed=$((tests_passed + 1))
		else
			failed+=("$test")
		fi
	done

	echo
	if [ "$tests_passed" -eq "$tests_run" ]; then
		pass "$suite suite: $tests_passed/$tests_run tests passed"
		return 0
	fi

	fail "$suite suite: $tests_passed/$tests_run tests passed"
	for test in "${failed[@]}"; do
		fail "  failed: $test"
	done
	return 1
}
