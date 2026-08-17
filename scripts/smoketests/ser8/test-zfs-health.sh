#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ZFS health smoketest for ser8.
#
# Asserts that both pools are online and error-free, that the snapshot the
# impermanence rollback depends on still exists, and that neither pool has been
# upgraded past what the previous boot generation can import.
#
# The snapshot assertion is the load-bearing one. If rpool/local/root@blank
# disappears, the stage-1 rollback unit stops erasing the root dataset on boot
# and the impermanence guarantee silently ends, with no symptom until somebody
# notices the root filesystem accumulating state months later.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Pools declared in hosts/ser8/disko-config.nix
POOLS=(
	rpool
	backup
)

# The blank snapshot hosts/ser8/configuration.nix rolls back to in stage-1
ROLLBACK_SNAPSHOT="rpool/local/root@blank"

# Track test results
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

# Run a command on the target host, returning its stdout. Empty output means
# the command could not be run or produced nothing; every caller treats that as
# a failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Test 1: pool is online and not degraded
test_pool_healthy() {
	local pool="$1"
	info "checking ZFS pool '$(fmt_bold "$pool")' health"

	local status
	status=$(remote zpool status -x "$pool")

	if [ -z "$status" ]; then
		fail "could not read 'zpool status -x $pool' from $host"
		return 1
	fi

	if echo "$status" | grep -qE "pool '$pool' is healthy|all pools are healthy"; then
		pass "ZFS pool '$(fmt_bold "$pool")' is healthy"
		return 0
	fi

	fail "ZFS pool '$(fmt_bold "$pool")' is NOT healthy"
	fail "  $(echo "$status" | tr '\n' ' ')"
	return 1
}

# Test 2: pool reports no data errors
test_pool_no_data_errors() {
	local pool="$1"
	info "checking ZFS pool '$(fmt_bold "$pool")' for data errors"

	local errors
	errors=$(remote zpool status "$pool" | grep 'errors:' || echo "")

	if [ -z "$errors" ]; then
		fail "could not read the error line of 'zpool status $pool' from $host"
		return 1
	fi

	if echo "$errors" | grep -q 'No known data errors'; then
		pass "ZFS pool '$(fmt_bold "$pool")' reports no known data errors"
		return 0
	fi

	fail "ZFS pool '$(fmt_bold "$pool")' reports data errors: $errors"
	return 1
}

# Test 3: the impermanence rollback snapshot still exists
test_rollback_snapshot() {
	info "checking the impermanence rollback snapshot '$(fmt_bold "$ROLLBACK_SNAPSHOT")'"

	local listed
	listed=$(remote zfs list -t snapshot -H -o name "$ROLLBACK_SNAPSHOT")

	if [ "$listed" = "$ROLLBACK_SNAPSHOT" ]; then
		pass "rollback snapshot '$(fmt_bold "$ROLLBACK_SNAPSHOT")' exists"
		return 0
	fi

	fail "rollback snapshot '$(fmt_bold "$ROLLBACK_SNAPSHOT")' is MISSING"
	fail "  the stage-1 rollback unit cannot erase the root dataset; impermanence is off"
	return 1
}

# Test 4: the pool has not been upgraded past the previous generation's ZFS
#
# `zpool upgrade` enables every feature the running ZFS supports, after which
# an older ZFS can no longer import the pool. During a channel bump that is
# precisely the action that removes the ability to boot the previous
# generation, so the safe state is the one where features remain available but
# not enabled — which is what the upgrade prompt in `zpool status` reports.
#
# The assertion is therefore that the prompt is still present. It is inverted
# on purpose: a check demanding the prompt's absence would only go green after
# somebody ran `zpool upgrade`, which is the one thing not to do mid-bump.
# Flip this assertion in the phase that deliberately upgrades the pools.
test_pool_not_upgraded() {
	local pool="$1"
	info "checking that ZFS pool '$(fmt_bold "$pool")' has not been feature-upgraded"

	local status
	status=$(remote zpool status "$pool")

	if [ -z "$status" ]; then
		fail "could not read 'zpool status $pool' from $host"
		return 1
	fi

	if echo "$status" | grep -q 'features are not enabled'; then
		pass "ZFS pool '$(fmt_bold "$pool")' is not feature-upgraded; an older ZFS can still import it"
		return 0
	fi

	fail "ZFS pool '$(fmt_bold "$pool")' has been feature-upgraded ('zpool upgrade' was run)"
	fail "  the previous boot generation's ZFS may no longer be able to import it"
	return 1
}

# Main test execution
echo
info "=== ZFS Pool Health Tests ==="
for pool in "${POOLS[@]}"; do
	run_test "pool_healthy_${pool}" test_pool_healthy "$pool" || true
	run_test "pool_no_data_errors_${pool}" test_pool_no_data_errors "$pool" || true
done

echo
info "=== Impermanence Rollback Tests ==="
run_test "rollback_snapshot" test_rollback_snapshot || true

echo
info "=== Pool Feature-Flag Tests ==="
for pool in "${POOLS[@]}"; do
	run_test "pool_not_upgraded_${pool}" test_pool_not_upgraded "$pool" || true
done

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run ZFS health tests passed"
else
	fail "$tests_passed/$tests_run ZFS health tests passed"
	exit 1
fi
