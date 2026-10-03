#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Sudo smoketest.
#
# The deploy account is in wheel and wheelNeedsPassword is off, so sudo
# must work without a prompt; `-n` turns a prompt into a failure instead
# of a hang. The group check comes first so a sudo failure can be read as
# either a missing membership or a broken sudoers rule.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user="${NIXBUILD_USER:-$(get_user "$host")}"

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

# Test 1: the account is in wheel
test_wheel_member() {
	info "checking that $user is in the wheel group on $host"
	if remote id -nG | tr ' ' '\n' | grep -qx wheel; then
		pass "$user is a member of wheel"
		return 0
	fi
	fail "$user is not a member of wheel on $host"
	return 1
}

# Test 2: sudo grants root without asking for a password
test_sudo_without_password() {
	info "checking that $user can sudo without a password on $host"
	local who
	who=$(remote sudo -n id -un 2>/dev/null || true)
	if [ "$who" = "root" ]; then
		pass "sudo -n runs as root"
		return 0
	fi
	fail "sudo -n did not run as root for $user (got '${who:-nothing}')"
	return 1
}

echo
info "=== Sudo Tests ==="
run_test "wheel_member" test_wheel_member || true
run_test "sudo_without_password" test_sudo_without_password || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run sudo tests passed"
else
	fail "$tests_passed/$tests_run sudo tests passed"
	exit 1
fi
