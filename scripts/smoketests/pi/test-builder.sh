#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Remote builder smoketest.
#
# etc/nix/machines lists each Pi as an aarch64-linux builder for the Mac.
# A builder needs more than a login: nix has to be on the PATH of a
# non-interactive ssh session and the store has to answer the daemon
# protocol. `nix store info` over an ssh store exercises exactly that
# path, and the system check catches a machines entry that names the
# wrong architecture.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user="${NIXBUILD_USER:-$(get_user "$host")}"

EXPECTED_SYSTEM="aarch64-linux"

tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	((tests_run += 1))
	if "$test_func" "$@"; then
		((tests_passed += 1))
		return 0
	fi
	warn "test failed: $test_name"
	return 1
}

remote() {
	ssh -o BatchMode=yes -o ConnectTimeout=10 "$user@$ipaddr" "$@"
}

# Test 1: the store answers the daemon protocol over ssh
test_store_reachable() {
	info "checking that the Nix store on $host answers over ssh"
	if nix store info --store "ssh://$user@$ipaddr" >/dev/null 2>&1; then
		pass "ssh://$user@$ipaddr serves its Nix store"
		return 0
	fi
	fail "the Nix store on $host is not reachable over ssh"
	fail "  the Mac cannot use $host as a remote builder until it is"
	return 1
}

# Test 2: the host builds for the system the machines file claims
test_builder_system() {
	info "checking that $host reports itself as $EXPECTED_SYSTEM"
	local system
	system=$(remote nix config show system 2>/dev/null || true)
	if [ "$system" = "$EXPECTED_SYSTEM" ]; then
		pass "$host builds for $system"
		return 0
	fi
	fail "$host reports system '${system:-unknown}', expected $EXPECTED_SYSTEM"
	return 1
}

echo
info "=== Remote Builder Tests ==="
run_test "store_reachable" test_store_reachable || true
run_test "builder_system" test_builder_system || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run remote builder tests passed"
else
	fail "$tests_passed/$tests_run remote builder tests passed"
	exit 1
fi
