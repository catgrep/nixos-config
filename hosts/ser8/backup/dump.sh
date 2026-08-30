#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Nightly portable dumps of every database this host runs.
#
# A snapshot of the data directory is a complete crash image and it restores
# perfectly onto the same server major version. It restores onto nothing else.
# A portable archive is what survives the day that major changes, and because
# it is written inside the snapshotted tree it rides every snapshot and every
# replica with no separate transport, no schedule of its own and nothing to
# remember.
#
# Sourced by dump.nix, which exports the four binary paths below from the
# pinned server package.

set -euo pipefail
umask 0077

: "${PG_DUMP_BIN:?built without a pg_dump path}"
: "${PG_DUMPALL_BIN:?built without a pg_dumpall path}"
: "${PG_RESTORE_BIN:?built without a pg_restore path}"
: "${PSQL_BIN:?built without a psql path}"

# Thin wrappers so the commands below read as the operations they are rather
# than as interpolated store paths. The pinned client is still the only one
# reached; nothing here falls back to whatever is on the path.
pg_dump() { "$PG_DUMP_BIN" "$@"; }
pg_dumpall() { "$PG_DUMPALL_BIN" "$@"; }
pg_restore() { "$PG_RESTORE_BIN" "$@"; }
psql() { "$PSQL_BIN" "$@"; }

readonly DUMP_DIR=/persist/var/lib/backup-dumps

# Named so the mail a failure sends says which step failed, not just that the
# unit did. Reassigned before each step below.
operation="starting up"
trap 'echo "[ERROR] PostgreSQL dump failed while $operation" >&2' ERR

# Deliberately in the parent dataset and not inside any service's directory. A
# per-service restore then never has to know these exist, and they ride the
# parent snapshot, which is taken whether or not a given service has a child
# dataset of its own.
operation="preparing $DUMP_DIR"
mkdir -p -- "$DUMP_DIR"
chmod 0700 -- "$DUMP_DIR"

# Debris from a run that died part-way through an archive. Everything that
# finished was renamed to its final name, so anything still carrying the
# unfinished suffix belongs to a run that is over.
operation="clearing unfinished archives left by an earlier run"
find "$DUMP_DIR" -maxdepth 1 -type f -name '*.partial' -delete

# Roles and tablespaces live in no per-database dump, so a restore built only
# from the archives below would come up with no owners and no grants.
operation="dumping the cluster globals"
pg_dumpall --globals-only >"$DUMP_DIR/globals.sql.partial"
mv -f -- "$DUMP_DIR/globals.sql.partial" "$DUMP_DIR/globals.sql"

# Enumerated from the catalog, never from a list kept in this file. A database
# created by some service added later is dumped the night it appears, with no
# edit here and nobody to remember making one.
#
# Null-delimited on both ends: a database name may legally contain whitespace,
# and a name split in two would quietly dump neither half.
operation="listing databases from the catalog"
databases=()
while IFS= read -r -d "" db; do
	databases+=("$db")
done < <(psql -At0c "select datname from pg_database where not datistemplate and datallowconn")

# A process substitution does not propagate its exit status, so a client that
# could not reach the server would be indistinguishable from a cluster with no
# databases. It is never a cluster with no databases -- a running server always
# has at least the superuser's own. Treating empty as a failure closes that gap,
# and closes it before the retirement pass below deletes an archive for every
# database it would think had disappeared.
if [ "${#databases[@]}" -eq 0 ]; then
	echo "[ERROR] The catalog query returned no databases" >&2
	exit 1
fi

for db in "${databases[@]}"; do
	target="$DUMP_DIR/$db.dump"
	partial="$target.partial"

	# Custom format, which is the only one that can be restored selectively and
	# the only one that can be listed without unpacking. No compression flag on
	# top of it: the format compresses already and the dataset underneath
	# compresses again, so a third pass spends CPU for nothing.
	operation="dumping database $db"
	pg_dump --format=custom --file="$partial" -- "$db"

	# Proving the archive lists before it is published under its final name is
	# what keeps a truncated dump out of every snapshot taken afterwards. A
	# reader of any snapshot sees a complete archive or none at all, never half
	# of one.
	operation="listing the fresh archive for $db"
	pg_restore --list -- "$partial" >/dev/null

	operation="publishing the archive for $db"
	mv -f -- "$partial" "$target"
done

# The directory should reflect the catalog rather than accumulate every database
# that ever existed here. Matched against the list already in hand rather than
# by asking the server about a name taken from a filename: a filename is not a
# trustworthy thing to put into a query, and it does not need to be one.
operation="retiring archives for databases that no longer exist"
for path in "$DUMP_DIR"/*.dump; do
	# The unmatched glob itself, when no archive exists yet.
	[ -e "$path" ] || continue

	name=${path##*/}
	db=${name%.dump}

	keep=0
	for existing in "${databases[@]}"; do
		if [ "$existing" = "$db" ]; then
			keep=1
			break
		fi
	done

	if [ "$keep" -eq 0 ]; then
		echo "Retiring $name: no database of that name exists"
		rm -f -- "$path"
	fi
done

echo "Dumped ${#databases[@]} database(s) into $DUMP_DIR"
