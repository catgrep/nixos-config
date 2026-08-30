#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Manifest smoketest for ser8.
#
# The nightly verification writes one tab-separated record of what it checked:
# hash-prefixed key=value headers, then one row per subject with six fields --
# kind, subject, check, result, size, and the snapshot that subject's
# last-verified hold now sits on.
#
# This test reads that record and then checks it against the pool rather than
# trusting it. Coverage and hold position are checked together because they
# come out of the same file and splitting them would mean parsing it twice.
#
# The hold cross-check is the part worth explaining. A held snapshot cannot be
# destroyed, which is what makes the newest proven-good copy of each service
# safe from the retention window rolling over it. The manifest records where
# each hold was placed; the pool records where each hold actually is. Those two
# agreeing is the guarantee. A recorded position naming a snapshot that has
# since been destroyed, or one that nothing is actually holding, means the last
# copy known to be good is not protected at all -- and the manifest alone would
# still read as healthy.

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

DS_ROOT="rpool/safe/persist"
MANIFEST="/persist/var/lib/backup-manifests/latest.tsv"
HOLD_TAG="last-verified"

# The declared covered-service set, read as data
SERVICES_NIX="./hosts/ser8/backup/services.nix"

# The token the verification writes when every check it ran came back clean
STATUS_OK="ok"

tests_run=0
tests_passed=0

run_test() {
	local test_name="$1"
	local test_func="$2"
	shift 2

	tests_run=$((tests_run + 1))
	if "$test_func" "$@"; then
		tests_passed=$((tests_passed + 1))
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

# The newest manifest, or empty output on any failure. Root-owned and written
# under a restrictive umask, because its rows name every database path on the
# host, so reading it needs elevation.
read_manifest() {
	remote sudo cat "$MANIFEST"
}

# One hash-prefixed header value out of a manifest, or empty output when the
# header is absent.
manifest_header() {
	local manifest="$1" key="$2"
	printf '%s\n' "$manifest" | awk -v k="#$key=" '
		index($0, k) == 1 { print substr($0, length(k) + 1); exit }
	'
}

# The declared covered-service set, one name per line, or empty output on any
# failure.
covered_services() {
	nix eval --raw --file "$SERVICES_NIX" \
		--apply 'set: builtins.concatStringsSep "\n" (builtins.attrNames set)' 2>/dev/null ||
		echo ""
}

# Test 1: the manifest exists, is readable, and parses
test_manifest_readable() {
	info "checking that '$(fmt_bold "$MANIFEST")' exists and parses"

	local manifest
	manifest=$(read_manifest)

	if [ -z "$manifest" ]; then
		fail "could not read '$MANIFEST' on $host"
		fail "  the verification has never written a manifest, or the file is unreadable"
		return 1
	fi

	local snapshot
	snapshot=$(manifest_header "$manifest" snapshot)

	if [ -z "$snapshot" ]; then
		fail "'$MANIFEST' carries no '#snapshot=' header"
		fail "  the file exists but is not a manifest this test can read"
		return 1
	fi

	local rows
	rows=$(printf '%s\n' "$manifest" | grep -cv '^#' || true)
	if [ -z "$rows" ] || [ "$rows" -eq 0 ]; then
		fail "'$MANIFEST' has headers but no rows; nothing was actually checked"
		return 1
	fi

	pass "'$(fmt_bold "$MANIFEST")' describes snapshot '$snapshot' with $rows row(s)"
	return 0
}

# Test 2: the run the manifest describes reported success
test_manifest_status_ok() {
	info "checking that the manifest's run status is '$(fmt_bold "$STATUS_OK")'"

	local manifest
	manifest=$(read_manifest)
	if [ -z "$manifest" ]; then
		fail "could not read '$MANIFEST' on $host"
		return 1
	fi

	local status
	status=$(manifest_header "$manifest" status)

	if [ -z "$status" ]; then
		fail "'$MANIFEST' carries no '#status=' header"
		return 1
	fi

	if [ "$status" != "$STATUS_OK" ]; then
		fail "the run described by '$MANIFEST' reported status '$status'"
		local row
		while IFS= read -r row; do
			[ -n "$row" ] || continue
			fail "  $row"
		done < <(printf '%s\n' "$manifest" | awk -F'\t' '$4 != "ok" && $0 !~ /^#/ { print }')
		return 1
	fi

	pass "the run described by the manifest reported status '$STATUS_OK'"
	return 0
}

# Test 3: the manifest's coverage set matches the declared covered-service set
#
# This assertion is inverted on purpose, and the inversion is the point. It
# compares against the set declared in the repository rather than against
# whatever the manifest happens to contain, so a service silently dropped from
# coverage fails here instead of quietly narrowing the manifest and taking the
# check down with it. Comparing the manifest to itself would go green on a host
# backing up nothing at all.
#
# Change this assertion only for a deliberate coverage change -- a service
# genuinely added to or removed from the backup set. Such a change updates both
# sides: hosts/ser8/backup/services.nix and the dataset tree the verification
# walks. If only one side moved, that is the drift this test exists to catch,
# and the fix belongs in the configuration rather than here.
test_manifest_coverage_matches_declaration() {
	info "checking that the manifest's coverage matches the declared service set"

	local manifest
	manifest=$(read_manifest)
	if [ -z "$manifest" ]; then
		fail "could not read '$MANIFEST' on $host"
		return 1
	fi

	local covered_field
	covered_field=$(manifest_header "$manifest" covered)

	if [ -z "$covered_field" ]; then
		fail "'$MANIFEST' carries no '#covered=' header, or it is empty"
		fail "  the verification walked no child datasets at all"
		return 1
	fi

	local declared recorded
	declared=$(covered_services | LC_ALL=C sort)
	recorded=$(printf '%s' "$covered_field" | tr ' ' '\n' | grep -v '^$' | LC_ALL=C sort)

	if [ -z "$declared" ]; then
		fail "could not read the covered-service set from $SERVICES_NIX"
		return 1
	fi

	if [ "$declared" = "$recorded" ]; then
		local count
		count=$(printf '%s\n' "$declared" | grep -c .)
		pass "the manifest covers all $count declared services"
		return 0
	fi

	fail "the manifest's coverage does not match the declared service set"
	local entry
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		fail "  declared but not in the manifest: $entry"
	done < <(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$recorded"))
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		fail "  in the manifest but not declared: $entry"
	done < <(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$recorded"))
	return 1
}

# Test 4: every recorded hold position is a real, still-held snapshot
test_hold_positions_are_real() {
	info "checking that every recorded hold position exists and is held"

	local manifest
	manifest=$(read_manifest)
	if [ -z "$manifest" ]; then
		fail "could not read '$MANIFEST' on $host"
		return 1
	fi

	local dataset_rows
	dataset_rows=$(printf '%s\n' "$manifest" | awk -F'\t' '$1 == "dataset" { print $2 "\t" $6 }')

	if [ -z "$dataset_rows" ]; then
		fail "'$MANIFEST' contains no dataset rows"
		fail "  the verification recorded no hold position for anything"
		return 1
	fi

	local snapshots holds
	snapshots=$(remote zfs list -H -r -t snapshot -o name "$DS_ROOT")
	if [ -z "$snapshots" ]; then
		fail "could not list the snapshots under '$DS_ROOT' on $host"
		return 1
	fi

	# Every hold on the tree in one call, rather than one call per dataset.
	holds=$(remote sudo sh -c \
		"zfs list -H -r -t snapshot -o name '$DS_ROOT' | xargs -r zfs holds -H")
	if [ -z "$holds" ]; then
		fail "no snapshot under '$DS_ROOT' carries any hold on $host"
		fail "  the last proven-good copy of every service is exposed to the retention window"
		return 1
	fi

	local bad=()
	local dataset hold_at
	while IFS=$'\t' read -r dataset hold_at; do
		[ -n "$dataset" ] || continue

		if [ -z "$hold_at" ] || [ "$hold_at" = "-" ]; then
			bad+=("$dataset: no hold position recorded; its last good snapshot is unpinned")
			continue
		fi

		local snapshot="$dataset@$hold_at"

		if ! printf '%s\n' "$snapshots" | grep -qxF "$snapshot"; then
			bad+=("$snapshot: recorded as held but no longer exists on the pool")
			continue
		fi

		if ! printf '%s\n' "$holds" |
			awk -F'\t' -v s="$snapshot" -v t="$HOLD_TAG" '$1 == s && $2 == t { found = 1 } END { exit !found }'; then
			bad+=("$snapshot: exists but carries no '$HOLD_TAG' hold; pruning can destroy it")
		fi
	done <<<"$dataset_rows"

	if [ "${#bad[@]}" -gt 0 ]; then
		fail "${#bad[@]} recorded hold position(s) are not backed by pool state"
		local entry
		for entry in "${bad[@]}"; do
			fail "  $entry"
		done
		return 1
	fi

	local count
	count=$(printf '%s\n' "$dataset_rows" | grep -c .)
	pass "all $count recorded hold positions exist and carry a '$HOLD_TAG' hold"
	return 0
}

echo
info "=== Manifest Integrity Tests ==="
run_test "manifest_readable" test_manifest_readable || true
run_test "manifest_status_ok" test_manifest_status_ok || true

echo
info "=== Coverage Tests ==="
run_test "manifest_coverage_matches_declaration" test_manifest_coverage_matches_declaration || true

echo
info "=== Hold Position Tests ==="
run_test "hold_positions_are_real" test_hold_positions_are_real || true

echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run manifest tests passed"
else
	fail "$tests_passed/$tests_run manifest tests passed"
	exit 1
fi
