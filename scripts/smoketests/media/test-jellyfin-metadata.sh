#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Jellyfin TV metadata smoketest for ser8.
#
# Sonarr names episode files from TheTVDB, so Jellyfin must read episode
# metadata from TheTVDB first or series whose seasons TheMovieDb splits
# differently (most anime) match nothing or the wrong episode. Three things
# have to hold for that, and only the first is enforced by the configuration:
#
# 1. hosts/ser8/media/jellyfin.nix copies exactly one TheTVDB plugin version
#    into Jellyfin's plugin directory.
# 2. Jellyfin loaded that plugin on its current start. A plugin whose target
#    ABI the running Jellyfin rejects stays on disk and is silently skipped.
# 3. The Shows library lists TheTVDB first among its metadata fetchers for
#    Series, Season and Episode. Jellyfin keeps the first value each fetcher
#    returns, so TheTVDB being merely enabled behind TheMovieDb would leave
#    TheMovieDb's wrong titles in place. This is dashboard state under
#    /var/lib/jellyfin, and nothing in the repository sets it, so this check
#    is the only guard it has.
#
# The plugin directory, the journal and the library settings are private to
# the service, so the checks run through `sudo -n`, as the Bazarr and VA-API
# checks do.

# shellcheck source=scripts/lib/all.sh
. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
	info "Usage: $0 <host>"
	exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Pinned in hosts/ser8/media/jellyfin.nix
TVDB_PLUGIN_VERSION="22.0.0.0"
PLUGINS_DIR="/var/lib/jellyfin/plugins"
TVDB_PLUGIN_DIR="$PLUGINS_DIR/TheTVDB_$TVDB_PLUGIN_VERSION"
TVDB_PLUGIN_DLL="$TVDB_PLUGIN_DIR/Jellyfin.Plugin.Tvdb.dll"
SHOWS_OPTIONS="/var/lib/jellyfin/root/default/Shows/options.xml"
TVDB_FETCHER="TheTVDB"

# The item types the Shows library fetches metadata for
SHOWS_TYPES=(
	Series
	Season
	Episode
)

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
# the command could not be run or produced nothing; every caller treats that
# as a failure rather than as an inconclusive result.
remote() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}

# Test 1: exactly the pinned plugin version is installed
test_plugin_installed() {
	info "checking the TheTVDB plugin directories under $(fmt_bold "$PLUGINS_DIR")"

	local plugin_dirs
	plugin_dirs=$(remote sudo -n find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 -name 'TheTVDB_*')

	if [ "$plugin_dirs" != "$TVDB_PLUGIN_DIR" ]; then
		fail "Expected exactly $TVDB_PLUGIN_DIR, found: '${plugin_dirs:-none}'"
		return 1
	fi

	# $1 must stay single-quoted so it expands on the remote shell, not the
	# local one.
	# shellcheck disable=SC2016
	if [ "$(remote sudo -n sh -c 'test -f "$1" && echo present' -- "$TVDB_PLUGIN_DLL")" != "present" ]; then
		fail "Missing $TVDB_PLUGIN_DLL"
		return 1
	fi

	pass "TheTVDB $TVDB_PLUGIN_VERSION is the only installed TheTVDB plugin"
	return 0
}

# Test 2: the running Jellyfin loaded the plugin
#
# Scoped to the current invocation of jellyfin.service so a load line from a
# previous start cannot vouch for a restart that rejected the plugin.
test_plugin_loaded() {
	info "checking that the current jellyfin.service start loaded TheTVDB $TVDB_PLUGIN_VERSION"

	local invocation_id
	invocation_id=$(remote systemctl show -p InvocationID --value jellyfin.service)

	if [ -z "$invocation_id" ]; then
		fail "could not read the jellyfin.service invocation id from $host"
		return 1
	fi

	local load_line
	load_line=$(remote sudo -n journalctl -q -o cat "_SYSTEMD_INVOCATION_ID=$invocation_id" |
		grep -F "Loaded plugin: $TVDB_FETCHER $TVDB_PLUGIN_VERSION" || echo "")

	if [ -z "$load_line" ]; then
		fail "jellyfin.service journal has no 'Loaded plugin: $TVDB_FETCHER $TVDB_PLUGIN_VERSION' line for its current start"
		return 1
	fi

	pass "Jellyfin loaded $TVDB_FETCHER $TVDB_PLUGIN_VERSION on its current start"
	return 0
}

# The enabled metadata fetchers of one item type in a library options.xml,
# one per line, read from stdin.
enabled_metadata_fetchers() {
	local type="$1"
	awk -v type="$type" '
		/<Type>/ { in_type = index($0, "<Type>" type "</Type>") > 0 }
		in_type && /<MetadataFetchers>/ { in_list = 1; next }
		in_list && /<\/MetadataFetchers>/ { exit }
		in_list && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print }
	'
}

# The first metadata fetcher in the fetcher order of one item type in a
# library options.xml, read from stdin.
first_metadata_fetcher() {
	local type="$1"
	awk -v type="$type" '
		/<Type>/ { in_type = index($0, "<Type>" type "</Type>") > 0 }
		in_type && /<MetadataFetcherOrder>/ { in_order = 1; next }
		in_order && /<\/MetadataFetcherOrder>/ { exit }
		in_order && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; exit }
	'
}

# Test 3: the Shows library fetches metadata from TheTVDB first
test_shows_fetcher_order() {
	info "checking the metadata fetcher order in $(fmt_bold "$SHOWS_OPTIONS")"

	local options
	options=$(remote sudo -n cat "$SHOWS_OPTIONS")

	if [ -z "$options" ]; then
		fail "could not read $SHOWS_OPTIONS from $host"
		return 1
	fi

	local type first enabled failed=0
	for type in "${SHOWS_TYPES[@]}"; do
		enabled=$(enabled_metadata_fetchers "$type" <<<"$options")
		if ! grep -qxF "$TVDB_FETCHER" <<<"$enabled"; then
			fail "$type does not have $TVDB_FETCHER enabled (enabled: $(tr '\n' ' ' <<<"$enabled"))"
			failed=1
			continue
		fi

		first=$(first_metadata_fetcher "$type" <<<"$options")
		if [ "$first" != "$TVDB_FETCHER" ]; then
			fail "$type fetches metadata from '${first:-nothing}' first, expected $TVDB_FETCHER"
			failed=1
		fi
	done

	if [ "$failed" -ne 0 ]; then
		return 1
	fi

	pass "Shows library fetches Series, Season and Episode metadata from $TVDB_FETCHER first"
	return 0
}

# Main test execution
echo
info "=== TheTVDB Plugin Tests ==="
run_test "plugin_installed" test_plugin_installed || true
run_test "plugin_loaded" test_plugin_loaded || true

echo
info "=== Shows Library Tests ==="
run_test "shows_fetcher_order" test_shows_fetcher_order || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Jellyfin metadata tests passed"
else
	fail "$tests_passed/$tests_run Jellyfin metadata tests passed"
	exit 1
fi
