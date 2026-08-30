#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Mealie service smoketest for ser8.
#
# Asserts the things a homepage load cannot: that PostgreSQL came up on the
# pinned major rather than the stateVersion-derived one, that Mealie's state
# landed in a real directory owned by its static user on both sides of the
# impermanence bind mount, and that BOTH of Mealie's state stores hold data.
#
# The two-store assertion is the one that earns its place. Recipe images, user
# uploads, and the session-signing secret are written to DATA_DIR on disk, not
# into PostgreSQL. A check that counts database rows alone passes while every
# recipe thumbnail is broken and every household member is logged out after a
# reboot — which is the difference between certifying persistence and
# certifying nothing.
#
# MEALIE_ALLOW_UNSEEDED
# ---------------------
# The seeded-data and recipe-persistence assertions are ON by default. Setting
# MEALIE_ALLOW_UNSEEDED=1 downgrades them to informational output, and exists
# for exactly one run: the pre-bootstrap activation in plan 10-04, before any
# Food, Unit, recipe, or image exists. It must be passed on the command line
# for that single run.
#
# Nothing committed to this repository may set it. Setting it in deploy.yaml,
# in scripts/smoketests/ser8/all.sh, or in scripts/smoketests/household/all.sh
# would turn a real deployment gate into an always-passing one — the failure
# Phase 9's gap-closure plans had to undo.

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

MEALIE_UNIT="mealie"
MEALIE_PORT="9000"

# DATA_DIR, hardcoded in the NixOS module's environment block
MEALIE_DATA_DIR="/var/lib/mealie"

# The durable state directory. Mealie's state is its own ZFS dataset mounted
# here, so the state path and the persisted path are one and the same; there is
# no longer a second copy under /persist to check separately.
MEALIE_PERSIST_DIR="$MEALIE_DATA_DIR"

# Where Mealie writes per-recipe image trees under DATA_DIR
MEALIE_PERSIST_RECIPE_DIR="$MEALIE_DATA_DIR/recipes"

# Follows services.postgresql.package = pkgs.postgresql_17
PG_DATA_DIR="/var/lib/postgresql/17"
PG_MAJOR="17"

MEALIE_DB="mealie"

# Table names confirmed against the live Mealie 3.22.0 schema on ser8 in plan
# 10-04 (alembic_version 2187537c52b8, 66 public tables), replacing RESEARCH.md
# Assumption A3. Every query still resolves the name through to_regclass first,
# so a rename in a future Mealie version reports a named failure here instead of
# a psql error.
FOODS_TABLE="ingredient_foods"
UNITS_TABLE="ingredient_units"
RECIPES_TABLE="recipes"

# Unset by default and unset in every committed file. See the header.
MEALIE_ALLOW_UNSEEDED="${MEALIE_ALLOW_UNSEEDED:-0}"

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

# Run a command on the target host, returning its exit status rather than its
# stdout. Same printf %q escaping as `remote`: probe arguments are never
# interpolated into a remote shell unescaped.
remote_ok() {
	local remote_command
	printf -v remote_command '%q ' "$@"
	# remote_command is intentionally expanded after printf %q shell escaping.
	# shellcheck disable=SC2029
	ssh "$user@$ipaddr" "$remote_command" >/dev/null 2>&1
}

# Run a psql query against the mealie database as the postgres user, relying on
# the socket peer authentication that database.createLocally sets up. Returns
# the bare value, or empty output on any failure.
mealie_psql() {
	remote sudo -u postgres psql -tAq -c "$1" "$MEALIE_DB" | tr -d '[:space:]'
}

# True when the named table resolves in the mealie database (PD-04).
mealie_table_exists() {
	local table="$1"
	[ "$(mealie_psql "SELECT to_regclass('public.${table}') IS NOT NULL")" = "t" ]
}

# Count rows in a table whose name has already been resolved. Non-numeric
# output normalises to the empty string so the caller can fail cleanly.
mealie_row_count() {
	remote sudo -u postgres psql -tAq -c "SELECT count(*) FROM ${1}" "$MEALIE_DB" |
		tr -dc '0-9'
}

# Report a zero count. Fails by default; reports informational only when the
# operator passed MEALIE_ALLOW_UNSEEDED=1 for a pre-bootstrap run.
report_empty() {
	local what="$1"
	if [ "$MEALIE_ALLOW_UNSEEDED" = "1" ]; then
		info "$what is empty (MEALIE_ALLOW_UNSEEDED=1, pre-bootstrap run)"
		return 0
	fi
	fail "$what is empty"
	return 1
}

# Test 1: the mealie unit is active
test_mealie_unit_active() {
	info "checking that the '$(fmt_bold "$MEALIE_UNIT")' unit is active"

	if remote_ok systemctl is-active --quiet "$MEALIE_UNIT"; then
		pass "'$(fmt_bold "$MEALIE_UNIT")' unit is active"
		return 0
	fi

	fail "'$(fmt_bold "$MEALIE_UNIT")' unit is not active"
	return 1
}

# Test 2: the application port is bound
#
# Probed by opening a TCP connection from the host's own login shell rather
# than through ss, netstat, or lsof: none of those is guaranteed to be in the
# system closure, and a check that silently skips when its tool is missing is
# a check that certifies nothing.
test_mealie_port_listening() {
	info "checking that port $(fmt_bold "$MEALIE_PORT") is bound on $host"

	if remote_ok timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${MEALIE_PORT}"; then
		pass "port $MEALIE_PORT accepts connections on $host"
		return 0
	fi

	fail "port $MEALIE_PORT is not accepting connections on $host"
	return 1
}

# Test 3: no error-level journal entry in the current boot
#
# This matters more for Mealie than for most units: the module runs Alembic
# migrations as an ExecStartPre on every start, and a migration that failed
# leaves the unit looking healthy on the next restart while the schema is
# half-applied. Scoped to the current boot, so an error from a previous
# generation is not carried forward as evidence about this one.
test_mealie_no_startup_errors() {
	info "checking the current boot's journal for '$(fmt_bold "$MEALIE_UNIT")' errors"

	local errors
	errors=$(remote journalctl -b -u "$MEALIE_UNIT" --priority=err --no-pager -q -o cat)

	if [ -z "$errors" ]; then
		pass "no error-level journal entries for '$(fmt_bold "$MEALIE_UNIT")' in the current boot"
		return 0
	fi

	local count
	count=$(echo "$errors" | wc -l | tr -d ' ')
	fail "$count error-level journal entries for '$(fmt_bold "$MEALIE_UNIT")' in the current boot"
	echo "$errors" | head -10 | while IFS= read -r line; do
		fail "  $line"
	done
	return 1
}

# Test 4: the mealie database answers over the postgres socket
test_mealie_database_reachable() {
	info "checking that the '$(fmt_bold "$MEALIE_DB")' database answers"

	local result
	result=$(mealie_psql "SELECT 1")

	if [ "$result" = "1" ]; then
		pass "'$(fmt_bold "$MEALIE_DB")' database answers over the postgres socket"
		return 0
	fi

	fail "'$(fmt_bold "$MEALIE_DB")' database did not answer (got '${result:-no response}')"
	return 1
}

# Test 5: the running server is the pinned major
#
# The runtime counterpart to the evaluation assertion in plan 10-01. This is
# the one that catches a data directory initialised by a different major
# before the pin landed, which no amount of eval-time checking can see.
test_postgres_major() {
	info "checking that PostgreSQL reports major $(fmt_bold "$PG_MAJOR")"

	local version
	version=$(mealie_psql "SHOW server_version")

	case "$version" in
	"${PG_MAJOR}" | "${PG_MAJOR}."*)
		pass "PostgreSQL server_version is $version"
		return 0
		;;
	esac

	fail "PostgreSQL server_version is '${version:-no response}', expected the $PG_MAJOR series"
	return 1
}

# Test 6: the PostgreSQL data directory ownership and mode
#
# 750, not 700: the upstream module sets StateDirectoryMode to 0750 for every
# major at or above 11, so a 700 expectation here would flap against systemd
# on every start. sudo is required because the deploy user cannot traverse
# /var/lib/postgresql.
test_postgres_data_dir_ownership() {
	info "checking ownership and mode of $(fmt_bold "$PG_DATA_DIR")"

	local stat_out
	stat_out=$(remote sudo stat -c '%U %G %a' "$PG_DATA_DIR")

	if [ "$stat_out" = "postgres postgres 750" ]; then
		pass "$PG_DATA_DIR is postgres:postgres mode 750"
		return 0
	fi

	fail "$PG_DATA_DIR is '${stat_out:-unreadable}', expected 'postgres postgres 750'"
	return 1
}

# Test 7: the Mealie state directory is a real directory, not a symlink
#
# A symlink here means the static-user override from plan 10-01 did not take
# effect and state is landing in /var/lib/private instead. Nothing visibly
# breaks until Phase 11's backup job silently backs up an empty tree.
test_mealie_state_dir_shape() {
	info "checking that $(fmt_bold "$MEALIE_DATA_DIR") is a real directory"

	if remote_ok test -L "$MEALIE_DATA_DIR"; then
		fail "$MEALIE_DATA_DIR is a symlink; state is landing in the private state tree"
		return 1
	fi

	if ! remote_ok test -d "$MEALIE_DATA_DIR"; then
		fail "$MEALIE_DATA_DIR is not a directory"
		return 1
	fi

	local stat_out
	stat_out=$(remote stat -c '%U %G' "$MEALIE_DATA_DIR")

	if [ "$stat_out" = "mealie mealie" ]; then
		pass "$MEALIE_DATA_DIR is a real directory owned mealie:mealie"
		return 0
	fi

	fail "$MEALIE_DATA_DIR is owned '${stat_out:-unreadable}', expected 'mealie mealie'"
	return 1
}

# Test 8: the persisted path is its own mounted ZFS dataset
#
# Since the dataset migration, MEALIE_PERSIST_DIR and MEALIE_DATA_DIR are the
# same path (see the definition above), so this no longer compares two
# directories against each other -- it proves the one path really is a mounted
# ZFS dataset rather than a plain directory riding the parent dataset's
# storage, which is what would let a reboot silently discard everything Mealie
# wrote.
test_mealie_persist_dir() {
	info "checking that $(fmt_bold "$MEALIE_PERSIST_DIR") is a mounted ZFS dataset"

	if remote_ok findmnt -rn -t zfs "$MEALIE_PERSIST_DIR"; then
		pass "$MEALIE_PERSIST_DIR is a mounted ZFS dataset"
		return 0
	fi

	fail "$MEALIE_PERSIST_DIR is not a mounted ZFS dataset"
	return 1
}

# Tests 9, 10, and 11: the Foods table, the Units table, and the database half
# of MEAL-05. All three differ only in which table they name and which metric
# key they print, so they share one assertion rather than three copies of it.
#
# The name is resolved through to_regclass before it is queried (PD-04). The
# names were confirmed against the live 3.22.0 schema in plan 10-04, so the
# resolution now guards against a rename in a future Mealie version rather than
# against a wrong guess: a bare query against a table that does not exist
# reports a psql error rather than a named failure.
assert_table_non_empty() {
	local table="$1"
	local metric_key="$2"

	info "checking that the '$(fmt_bold "$table")' table is populated"

	if ! mealie_table_exists "$table"; then
		fail "table '$table' does not exist in the $MEALIE_DB database; confirm the name against the live schema"
		return 1
	fi

	local count
	count=$(mealie_row_count "$table")

	if [ -z "$count" ]; then
		fail "could not count rows in '$table'"
		return 1
	fi

	info "${metric_key}=$count"

	if [ "$count" -gt 0 ]; then
		pass "'$table' holds $count rows"
		return 0
	fi

	report_empty "'$table'"
}

# Test 12: the on-disk half of MEAL-05
#
# Asserted alongside the recipe row count rather than instead of it. The row
# count alone is green while every thumbnail under the state directory is
# gone, because Mealie's images never enter PostgreSQL. sudo is required
# because the recipe tree is mode 0750 mealie:mealie.
test_mealie_recipe_images_present() {
	info "checking the persisted recipe image tree $(fmt_bold "$MEALIE_PERSIST_RECIPE_DIR")"

	# grep -c counts non-empty lines and reports 0 with a non-zero status, so a
	# missing or unreadable tree lands on the same "no images" path as an empty
	# one rather than aborting the run.
	local count
	count=$(remote sudo find "$MEALIE_PERSIST_RECIPE_DIR" -type f | grep -c . || true)

	info "mealie_recipe_image_files=$count"

	if [ "$count" -gt 0 ]; then
		pass "$MEALIE_PERSIST_RECIPE_DIR holds $count files"
		return 0
	fi

	report_empty "the recipe image tree under $MEALIE_PERSIST_RECIPE_DIR"
}

# Main test execution
echo
info "=== Mealie Service Tests ==="
run_test "mealie_unit_active" test_mealie_unit_active || true
run_test "mealie_port_listening" test_mealie_port_listening || true
run_test "mealie_no_startup_errors" test_mealie_no_startup_errors || true

echo
info "=== PostgreSQL Tests ==="
run_test "mealie_database_reachable" test_mealie_database_reachable || true
run_test "postgres_major" test_postgres_major || true
run_test "postgres_data_dir_ownership" test_postgres_data_dir_ownership || true

echo
info "=== State Directory Tests ==="
run_test "mealie_state_dir_shape" test_mealie_state_dir_shape || true
run_test "mealie_persist_dir" test_mealie_persist_dir || true

echo
info "=== Seeded Data Tests ==="
run_test "mealie_foods_seeded" assert_table_non_empty "$FOODS_TABLE" mealie_foods_count || true
run_test "mealie_units_seeded" assert_table_non_empty "$UNITS_TABLE" mealie_units_count || true

echo
info "=== Persistence Tests ==="
run_test "mealie_recipes_present" assert_table_non_empty "$RECIPES_TABLE" mealie_recipe_count || true
run_test "mealie_recipe_images_present" test_mealie_recipe_images_present || true

# Summary
echo
if [ $tests_run -eq 0 ]; then
	warn "no tests were run"
	exit 1
elif [ $tests_passed -eq $tests_run ]; then
	pass "all $tests_run Mealie service tests passed"
else
	fail "$tests_passed/$tests_run Mealie service tests passed"
	exit 1
fi
