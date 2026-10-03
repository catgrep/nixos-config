#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Login smoketest.
#
# Checks that the deploy account opens a non-interactive ssh session, that
# its login shell is zsh and that its home directory is present. The
# account comes from deploy.yaml; NIXBUILD_USER, the Makefile's override
# for the deploy user, takes precedence so the check can follow an account
# rename before deploy.yaml does.

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

# Test 1: the key is accepted and a session opens
test_ssh_login() {
	info "checking that $user can log in to $host over ssh"
	if remote true; then
		pass "$user@$ipaddr accepted the ssh key"
		return 0
	fi
	fail "$user@$ipaddr refused the ssh login"
	fail "  if the account was renamed, set NIXBUILD_USER to the account that exists"
	return 1
}

# Test 2: the account's shell is the one the configuration declares
test_login_shell() {
	info "checking that the login shell of $user is zsh"
	local shell
	shell=$(remote getent passwd "$user" | cut -d: -f7 || true)
	case "$shell" in
	*/zsh)
		pass "login shell is $shell"
		return 0
		;;
	esac
	fail "login shell is '${shell:-unknown}', expected zsh"
	return 1
}

# Test 3: the home directory exists, so Home Manager had somewhere to activate
test_home_directory() {
	info "checking that the home directory of $user exists on $host"
	local home
	home=$(remote getent passwd "$user" | cut -d: -f6 || true)
	if [ -n "$home" ] && remote test -d "$home"; then
		pass "home directory $home is present"
		return 0
	fi
	fail "the home directory '${home:-unknown}' of $user is missing on $host"
	return 1
}

echo
info "=== Login Tests ==="
run_test "ssh_login" test_ssh_login || true
run_test "login_shell" test_login_shell || true
run_test "home_directory" test_home_directory || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run login tests passed"
else
	fail "$tests_passed/$tests_run login tests passed"
	exit 1
fi
