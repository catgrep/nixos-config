#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

# Proves that the databases inside last night's snapshot actually recover.
#
# A snapshot is only a backup if what is inside it opens. Everything here reads
# the snapshot and never the live file, so the thing being proven is the thing a
# restore would use. Nothing is registered anywhere: databases are found by
# looking for them, so a service added later is checked the first night after it
# writes its first file.
#
# The whole file is fail-closed. Absent is a failure, unreadable is a failure,
# unparseable is a failure. There is no skip.
#
# Sourced by verify.nix, which exports the binary paths and the mail
# destination below.

set -euo pipefail
umask 0077

: "${ZFS_BIN:?built without a zfs path}"
: "${SQLITE_BIN:?built without a sqlite3 path}"
: "${PG_RESTORE_BIN:?built without a pg_restore path}"
: "${FINDMNT_BIN:?built without a findmnt path}"
: "${MKTEMP_BIN:?built without a mktemp path}"
: "${CMP_BIN:?built without a cmp path}"
: "${SENDMAIL_BIN:?built without a sendmail path}"
: "${BACKUP_MAIL_TO:?built without a mail destination}"

# Thin wrappers so the operations below read as themselves. The pinned binary is
# still the only one reached; nothing falls back to whatever is on the path.
zfs() { "$ZFS_BIN" "$@"; }
sqlite3() { "$SQLITE_BIN" "$@"; }
pg_restore() { "$PG_RESTORE_BIN" "$@"; }
findmnt() { "$FINDMNT_BIN" "$@"; }
mktemp() { "$MKTEMP_BIN" "$@"; }
cmp() { "$CMP_BIN" "$@"; }

readonly DS_ROOT=rpool/safe/persist
readonly REPLICA=backup/persist-replica
readonly HOLD_TAG=last-verified

# A day plus two hours. Wide enough that a snapshot taken slightly late is not
# an alert, narrow enough that a missed night is.
readonly MAX_AGE_SECONDS=$((26 * 3600))

# Above this, the page-level check instead of the full one. The full check
# verifies every index against its table and is roughly linear in size; two of
# the databases on this host are around 175 MB and would dominate the run for
# structural news the page check already carries. Which check ran is recorded
# per file, so the evidence stays honest about what was actually proven.
readonly FULL_CHECK_MAX_BYTES=$((64 * 1024 * 1024))

start_epoch=$(date +%s)

operation="starting up"
trap 'echo "[ERROR] Verification aborted while $operation" >&2' ERR

run_status=ok
failures=()

record_failure() {
	run_status=fail
	failures+=("$1")
	echo "[FAIL] $1" >&2
}

# Tab-separated, six fields, and the separator is the reason: the manifest can
# be read by the tools already on this host and by a smoketest with no parser
# behind it. A result carrying a tab or a newline would silently become extra
# fields, so collapse them. The sixth field is the hold position, which applies
# only to dataset rows; every row added here carries the dash that says so.
rows=()
add_row() {
	local kind=$1 subject=$2 check=$3 result=$4 size=$5
	subject=${subject//$'\t'/ }
	subject=${subject//$'\n'/ }
	result=${result//$'\t'/ }
	result=${result//$'\n'/ }
	rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t-' "$kind" "$subject" "$check" "$result" "$size")")
}

# ---------------------------------------------------------------------------
# 1. Find the subject: the newest nightly snapshot of the tree.
# ---------------------------------------------------------------------------

operation="finding the newest nightly snapshot of $DS_ROOT"
snapshot_name=""
snapshot_epoch=0
while IFS=$'\t' read -r name created; do
	case "$name" in
	"$DS_ROOT"@autosnap_*_daily)
		snapshot_name=${name#*@}
		snapshot_epoch=$created
		;;
	esac
done < <(zfs list -H -p -t snapshot -o name,creation -s creation "$DS_ROOT")

if [ -z "$snapshot_name" ]; then
	echo "[ERROR] No nightly snapshot exists on $DS_ROOT" >&2
	exit 1
fi

# The same check that catches a snapshot job which never ran, with no extra
# plumbing: a snapshot too old to trust and a snapshot that was never taken
# produce the same answer here, and both are the same problem.
snapshot_age=$((start_epoch - snapshot_epoch))
if [ "$snapshot_age" -gt "$MAX_AGE_SECONDS" ]; then
	echo "[ERROR] The newest nightly snapshot of $DS_ROOT is ${snapshot_age}s old" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# 2. Walk the tree.
# ---------------------------------------------------------------------------

operation="listing the datasets under $DS_ROOT"
mapfile -t dataset_lines < <(zfs list -H -r -o name,mountpoint "$DS_ROOT")
if [ "${#dataset_lines[@]}" -eq 0 ]; then
	echo "[ERROR] Could not list the datasets under $DS_ROOT" >&2
	exit 1
fi

walked=()
walked_ok=()
walked_usedsnap=()
covered=()
sqlite_ok=0
sqlite_fail=0
# Files named like a database that turned out not to be one. Counted and
# reported separately rather than folded into either total above, because
# they are neither a pass nor a problem and lumping them loses that.
sqlite_other=0
pgdump_ok=0
pgdump_fail=0
written_total=0
usedsnap_total=0

for line in "${dataset_lines[@]}"; do
	IFS=$'\t' read -r dataset mountpoint <<<"$line"

	# Recorded every night, which turns an estimate of how much this tree churns
	# into an observed series with no extra tooling anywhere.
	operation="reading the space accounting of $dataset"
	written=$(zfs get -Hp -o value written "$dataset")
	usedsnap=$(zfs get -Hp -o value usedbysnapshots "$dataset")
	written_total=$((written_total + written))
	usedsnap_total=$((usedsnap_total + usedsnap))

	walked+=("$dataset")
	walked_usedsnap+=("$usedsnap")
	if [ "$dataset" != "$DS_ROOT" ]; then
		covered+=("${dataset##*/}")
	fi

	dataset_ok=1

	# A legacy mountpoint means the pool is not tracking where this dataset
	# landed; the kernel is, so ask it.
	operation="resolving the mountpoint of $dataset"
	if [ "$mountpoint" = "legacy" ]; then
		mountpoint=$(findmnt -n -o TARGET -S "$dataset" | head -1 || true)
	fi

	if [ -z "$mountpoint" ] || [ "$mountpoint" = "none" ] || [ "$mountpoint" = "-" ]; then
		record_failure "$dataset is not mounted, so its snapshot cannot be read"
		walked_ok+=(0)
		continue
	fi

	# Reachable even though the snapshot directory is hidden from listings:
	# hidden removes it from directory enumeration, not from the namespace. A
	# missing view is a failure rather than a skip, because the recursive
	# snapshot guarantees the same name exists on every dataset in the tree.
	view="$mountpoint/.zfs/snapshot/$snapshot_name"
	if [ ! -d "$view" ]; then
		record_failure "$dataset has no snapshot view at $view"
		walked_ok+=(0)
		continue
	fi

	# -----------------------------------------------------------------------
	# 3. Discover databases by kind, not by registry.
	# -----------------------------------------------------------------------

	# Null-delimited from end to end, because a path containing a space or a
	# newline that split into two fields would be two paths that do not exist
	# and one database that was never checked. No discovered path is ever
	# evaluated, only quoted.
	#
	# The write-ahead-log and shared-memory sidecars cannot match: they carry
	# their suffix after the extension, so foo.db-wal is not foo.db.
	operation="finding databases under $view"
	mapfile -d "" -t db_files < <(
		find "$view" -type f \
			\( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0
	)

	for db in "${db_files[@]}"; do
		# -------------------------------------------------------------------
		# 4. Decide what the file actually is before opening it as a database.
		# -------------------------------------------------------------------

		# The search above matches on the name, and on this host the set of
		# files called *.db is not the set of databases. Frigate's GPU driver
		# keeps fifty shader caches as mesa_cache.db, and Mosquitto's own
		# persistence file is mosquitto.db; neither is SQLite and neither ever
		# will be. Handing them to the check reports corruption on files that
		# are exactly as they should be -- which is worse than a missing check,
		# because it fails the run every night until the reader learns to
		# discount it.
		#
		# So the kind is decided by content. Every SQLite database opens with
		# the same sixteen-byte header; the comparison is on the printable
		# fifteen because a shell variable cannot carry the trailing NUL.
		# Compared with cmp rather than by capturing the header into a variable:
		# the header's sixteenth byte is a NUL, and so is much of what a
		# non-database has in those positions, which a command substitution
		# cannot carry and warns about on every file it reads.
		size=$(stat -c %s -- "$db")
		operation="reading the file header of $db"
		if ! printf 'SQLite format 3\0' | cmp -s -n 16 - "$db"; then
			# Not silently dropped. The row says which file, and what it turned
			# out to be, so a file that stops being checked is visible in the
			# manifest rather than absent from it.
			magic=$(head -c 16 -- "$db" 2>/dev/null | tr -c '[:print:]' '.' || true)

			# One exception, and it is the case that makes name-based discovery
			# worth replacing rather than merely narrowing: a write-ahead log or
			# a shared-memory sidecar is created by SQLite and by nothing else.
			# A file carrying one while not carrying the header was a database
			# and no longer opens as one, which is precisely the damage this job
			# exists to find. Treating that as "not a database" would turn the
			# worst case into a pass.
			if [ -e "$db-wal" ] || [ -e "$db-shm" ]; then
				add_row sqlite "$db" header "damaged: header is '$magic' but a sidecar exists" "$size"
				sqlite_fail=$((sqlite_fail + 1))
				dataset_ok=0
				record_failure "$db carries a SQLite sidecar but its header reads '$magic'"
			else
				add_row sqlite "$db" header "not-a-database: '$magic'" "$size"
				sqlite_other=$((sqlite_other + 1))
			fi
			continue
		fi

		# -------------------------------------------------------------------
		# 4b. Check each database the way a restore would open it.
		# -------------------------------------------------------------------

		# This is the load-bearing step in the whole engine, and the copy is
		# not a workaround for an inconvenience -- it is the claim under test.
		#
		# A write-ahead-log database is not the file alone. Its recent
		# transactions live in a sidecar log, and replaying that log needs a
		# shared-memory file created next to the database. A snapshot path is
		# read-only, so that file cannot be created there: checking in place
		# either errors outright, or -- if the database is opened as
		# unchangeable to make the error go away -- skips the log entirely and
		# certifies a stale image while reporting success. That second
		# behaviour is the dangerous one, because it looks exactly like a pass.
		#
		# Copying the database and whichever sidecars exist out to scratch and
		# opening the copy read-write replays the log exactly as crash recovery
		# would. That recovery is precisely what this design promises a restore
		# will do, so performing it here proves the promise instead of assuming
		# it.
		operation="copying $db out of the snapshot"
		scratch=$(mktemp -d)
		cp -- "$db" "$scratch/db"
		if [ -e "$db-wal" ]; then
			cp -- "$db-wal" "$scratch/db-wal"
		fi
		if [ -e "$db-shm" ]; then
			cp -- "$db-shm" "$scratch/db-shm"
		fi
		# The snapshot preserves the live mode, which is often writable by
		# nobody but the owning service. The replay needs to write.
		chmod -R u+w -- "$scratch"

		if [ "$size" -gt "$FULL_CHECK_MAX_BYTES" ]; then
			check=quick_check
		else
			check=integrity_check
		fi

		operation="running PRAGMA $check on a copy of $db"
		result=$(sqlite3 "$scratch/db" "PRAGMA $check;" 2>&1 | head -1 || true)

		# Removed however the check went, so a failing night leaves no scratch
		# behind and a second run starts where a first one does.
		rm -rf -- "$scratch"

		# Anything other than the single expected token is a failure. A check
		# that finds problems returns its first one here, which is both not the
		# token and the most useful thing to put in the mail.
		add_row sqlite "$db" "$check" "$result" "$size"
		if [ "$result" = "ok" ]; then
			sqlite_ok=$((sqlite_ok + 1))
		else
			sqlite_fail=$((sqlite_fail + 1))
			dataset_ok=0
			record_failure "$db failed PRAGMA $check: $result"
		fi
	done

	# -----------------------------------------------------------------------
	# 5. Check the portable archives that rode inside this snapshot.
	# -----------------------------------------------------------------------

	operation="finding database archives under $view"
	mapfile -d "" -t dump_files < <(find "$view" -type f -name '*.dump' -print0)

	for dump in "${dump_files[@]}"; do
		operation="listing the archive $dump"
		size=$(stat -c %s -- "$dump")
		if pg_restore --list "$dump" >/dev/null 2>&1; then
			pgdump_ok=$((pgdump_ok + 1))
			add_row pgdump "$dump" pg_restore-list ok "$size"
		else
			pgdump_fail=$((pgdump_fail + 1))
			dataset_ok=0
			record_failure "$dump could not be listed"
			add_row pgdump "$dump" pg_restore-list unlistable "$size"
		fi
	done

	walked_ok+=("$dataset_ok")
done

# ---------------------------------------------------------------------------
# 6. Check the replica by existence and freshness only.
# ---------------------------------------------------------------------------

# Deliberately not an integrity check. The pool's own checksums make an
# integrity divergence between a source and a replica essentially impossible
# without a pool error, and a pool error is what the scrub and its existing
# alert are for. Mounting a deliberately unmounted dataset every night to learn
# nothing new is a cost with no return. Checking only one side reads like an
# oversight otherwise, which is why this says so.
operation="finding the newest nightly snapshot on $REPLICA"
replica_name=""
replica_epoch=0
while IFS=$'\t' read -r name created; do
	case "$name" in
	"$REPLICA"@autosnap_*_daily)
		replica_name=${name#*@}
		replica_epoch=$created
		;;
	esac
done < <(zfs list -H -p -t snapshot -o name,creation -s creation "$REPLICA" 2>/dev/null || true)

if [ -z "$replica_name" ]; then
	record_failure "No nightly snapshot exists on $REPLICA"
	add_row replica "$REPLICA" freshness missing -
elif [ $((start_epoch - replica_epoch)) -gt "$MAX_AGE_SECONDS" ]; then
	record_failure "The newest snapshot on $REPLICA is $((start_epoch - replica_epoch))s old"
	add_row replica "$REPLICA@$replica_name" freshness stale -
else
	add_row replica "$REPLICA@$replica_name" freshness ok -
fi

# ---------------------------------------------------------------------------
# 7. Advance the last-verified hold, per dataset, only on a clean result.
# ---------------------------------------------------------------------------

# A held snapshot cannot be destroyed. So the newest snapshot that was proven
# good for a given service is structurally safe from pruning until a later one
# is proven good, which is something retention alone cannot give: a thirty-night
# window will happily age out the last healthy copy while thirty corrupt ones
# stack up on top of it. This turns "we would have noticed within a day" into
# "the good copy is pinned until something better replaces it".
#
# Per dataset rather than per run, so one failing service does not pin the whole
# tree and a healthy service is not held back by an unhealthy neighbour.

# The snapshot the tag currently sits on, or nothing. Read rather than assumed,
# because the manifest's answer to "which snapshot would a restore use" is only
# worth reading if it mirrors what the pool actually holds.
current_hold() {
	local dataset=$1 snap tag
	local -a snaps=()
	mapfile -t snaps < <(zfs list -H -t snapshot -o name "$dataset" 2>/dev/null || true)
	[ "${#snaps[@]}" -gt 0 ] || return 0
	while IFS=$'\t' read -r snap tag _; do
		if [ "$tag" = "$HOLD_TAG" ]; then
			printf '%s\n' "${snap#*@}"
		fi
	done < <(zfs holds -H "${snaps[@]}" 2>/dev/null || true)
}

hold_positions=()
for index in "${!walked[@]}"; do
	dataset=${walked[$index]}

	operation="reading the $HOLD_TAG hold on $dataset"
	mapfile -t held < <(current_hold "$dataset")

	if [ "${walked_ok[$index]}" -ne 1 ]; then
		# Left exactly where it is. Advancing it would release the only copy
		# known to be good in favour of one known to be bad, which is the single
		# move this whole mechanism exists to prevent. The row below therefore
		# names the older snapshot, which is precisely the one to restore from.
		hold_positions+=("${held[0]:--}")
		continue
	fi

	if [ "${#held[@]}" -eq 1 ] && [ "${held[0]}" = "$snapshot_name" ]; then
		# Already where it belongs, which is what a second run against the same
		# snapshot finds. Releasing and re-placing would reach the same state
		# through a window in which the snapshot is unheld, so do neither.
		hold_positions+=("$snapshot_name")
		continue
	fi

	# Release first, then place, and never the other way round. Placing before
	# releasing accumulates holds until the entire retention window is pinned
	# and nothing can be destroyed at all. More than one hold here means an
	# earlier run did exactly that, so release every one of them.
	placed=$snapshot_name
	release_failures=0
	for old in "${held[@]}"; do
		operation="releasing the $HOLD_TAG hold on $dataset@$old"
		if ! zfs release "$HOLD_TAG" "$dataset@$old"; then
			record_failure "Could not release the $HOLD_TAG hold on $dataset@$old"
			release_failures=$((release_failures + 1))
			placed=$old
		fi
	done

	if [ "$release_failures" -gt 1 ]; then
		# More than one stale hold survived this pass. Naming just the last one
		# here would understate what the pool still has pinned, and the manifest
		# format has room for exactly one snapshot per row, so record the
		# position as unresolved rather than pick an arbitrary survivor. The
		# already fail-closed restore path (manifest_hold/resolve_default_snapshot)
		# then refuses to pick a default and sends the operator to --list, which
		# is the same outcome a hard failure here would produce.
		placed=-
	fi

	if [ "$placed" = "$snapshot_name" ]; then
		operation="placing the $HOLD_TAG hold on $dataset@$snapshot_name"
		if ! zfs hold "$HOLD_TAG" "$dataset@$snapshot_name"; then
			# Worse than a stale hold: the dataset is now pinned by nothing.
			record_failure "Could not place the $HOLD_TAG hold on $dataset@$snapshot_name"
			placed=-
		fi
	fi

	hold_positions+=("$placed")
done

dataset_rows=()
for index in "${!walked[@]}"; do
	if [ "${walked_ok[$index]}" -eq 1 ]; then
		dataset_result=ok
	else
		dataset_result=fail
	fi
	dataset_rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' \
		dataset "${walked[$index]}" contents "$dataset_result" \
		"${walked_usedsnap[$index]}" "${hold_positions[$index]}")")
done

# ---------------------------------------------------------------------------
# 8. Write the manifest.
# ---------------------------------------------------------------------------

# The hold position in the sixth field is what makes this file answer the
# question an operator actually asks under pressure -- which snapshot would a
# restore use, and is it known good -- without reading pool state. On a night
# where a dataset failed, its hold position names the older snapshot the hold
# stayed on, which is exactly the snapshot to restore from.
#
# The manifest necessarily rides the *next* snapshot rather than the one it
# describes, which is expected: it is a record for an operator to read on the
# running host, not part of the snapshot's own evidence.
#
# The status field records what the verification found. The unit's own exit
# status covers one thing more -- whether the digest below could be delivered.
operation="writing the manifest"
duration_seconds=$(($(date +%s) - start_epoch))
manifest_dir=/persist/var/lib/backup-manifests
manifest="$manifest_dir/$(date -u -d "@$snapshot_epoch" +%Y-%m-%d).tsv"

{
	printf '#snapshot=%s\n' "$snapshot_name"
	printf '#snapshot_epoch=%s\n' "$snapshot_epoch"
	printf '#replica_snapshot=%s\n' "${replica_name:--}"
	printf '#replica_epoch=%s\n' "$replica_epoch"
	printf '#covered=%s\n' "${covered[*]}"
	printf '#duration_seconds=%s\n' "$duration_seconds"
	printf '#written_bytes=%s\n' "$written_total"
	printf '#usedbysnapshots_bytes=%s\n' "$usedsnap_total"
	printf '#status=%s\n' "$run_status"
	printf '%s\n' "${dataset_rows[@]}"
	[ "${#rows[@]}" -eq 0 ] || printf '%s\n' "${rows[@]}"
} >"$manifest.partial"
mv -f -- "$manifest.partial" "$manifest"
ln -sfn -- "$manifest" "$manifest_dir/latest.tsv"

# ---------------------------------------------------------------------------
# 9. Send the digest.
# ---------------------------------------------------------------------------

# Paths, check names, results and sizes. Never file contents: this walks every
# database on the host, and a digest that carried any of what it read would be
# the worst thing in the mail spool.
compose_digest() {
	local index failure
	printf 'To: %s\n' "$BACKUP_MAIL_TO"
	printf 'Subject: [backup] %s verification %s\n' "$snapshot_name" "$run_status"
	printf '\n'
	printf 'Snapshot:  %s\n' "$snapshot_name"
	printf 'Replica:   %s\n' "${replica_name:-none}"
	printf 'Duration:  %ss\n' "$duration_seconds"
	printf 'Databases: %s ok, %s failed, %s not databases\n' \
		"$sqlite_ok" "$sqlite_fail" "$sqlite_other"
	printf 'Archives:  %s ok, %s failed\n' "$pgdump_ok" "$pgdump_fail"
	printf 'Written:   %s bytes since the newest snapshot\n' "$written_total"
	printf 'Snapshots: %s bytes held\n' "$usedsnap_total"
	printf '\nHolds:\n'
	for index in "${!walked[@]}"; do
		printf '  %s\t%s\n' "${walked[$index]}" "${hold_positions[$index]}"
	done
	if [ "${#failures[@]}" -gt 0 ]; then
		printf '\nFailures:\n'
		for failure in "${failures[@]}"; do
			printf '  %s\n' "$failure"
		done
	fi
	printf '\nManifest: %s\n' "$manifest"
}

# A delivery failure is a failure of the run, and that is not circular: the
# staleness alert that notices the unstamped metric below is evaluated on
# another host entirely, so it still reaches someone on a night when mail from
# this one does not.
operation="sending the nightly digest"
if ! compose_digest | "$SENDMAIL_BIN" -t; then
	record_failure "Could not deliver the nightly digest"
fi

# ---------------------------------------------------------------------------
# 10. Write the metrics, last.
# ---------------------------------------------------------------------------

# Being last is the entire point. Under strict error handling a failure anywhere
# above aborts before this runs, and a failure that was recorded rather than
# fatal is caught by the guard here, so a fresh timestamp can never sit beside a
# run that did not pass. That is what makes the absence arm of the staleness
# rule mean something: an unstamped metric is a real answer, not a missing one.
if [ "$run_status" != "ok" ]; then
	echo "[ERROR] Verification failed; the freshness metrics were left unstamped" >&2
	exit 1
fi

operation="writing the metrics"
metrics=/persist/var/lib/node-exporter-textfile/backup.prom
{
	echo '# HELP backup_last_snapshot_timestamp_seconds Newest nightly snapshot, created.'
	echo '# TYPE backup_last_snapshot_timestamp_seconds gauge'
	echo "backup_last_snapshot_timestamp_seconds $snapshot_epoch"
	echo '# HELP backup_last_replica_timestamp_seconds Newest replica snapshot, created.'
	echo '# TYPE backup_last_replica_timestamp_seconds gauge'
	echo "backup_last_replica_timestamp_seconds $replica_epoch"
	echo '# HELP backup_last_verify_timestamp_seconds Last passing verification, finished.'
	echo '# TYPE backup_last_verify_timestamp_seconds gauge'
	echo "backup_last_verify_timestamp_seconds $(date +%s)"
	echo '# HELP backup_verified_files Files verified in the last run, by kind and result.'
	echo '# TYPE backup_verified_files gauge'
	echo "backup_verified_files{kind=\"sqlite\",result=\"ok\"} $sqlite_ok"
	echo "backup_verified_files{kind=\"sqlite\",result=\"fail\"} $sqlite_fail"
	echo "backup_verified_files{kind=\"sqlite\",result=\"not_a_database\"} $sqlite_other"
	echo "backup_verified_files{kind=\"pgdump\",result=\"ok\"} $pgdump_ok"
	echo "backup_verified_files{kind=\"pgdump\",result=\"fail\"} $pgdump_fail"
	echo '# HELP backup_persist_written_bytes Bytes written since the newest snapshot.'
	echo '# TYPE backup_persist_written_bytes gauge'
	echo "backup_persist_written_bytes $written_total"
	echo '# HELP backup_persist_usedbysnapshots_bytes Bytes held only by snapshots.'
	echo '# TYPE backup_persist_usedbysnapshots_bytes gauge'
	echo "backup_persist_usedbysnapshots_bytes $usedsnap_total"
} >"$metrics.partial"

# The mode is explicit because the umask above is not what the collector needs:
# it runs as its own user and can only read what is readable to it. The rename
# is what keeps it from ever reading half a file.
chmod 0644 -- "$metrics.partial"
mv -f -- "$metrics.partial" "$metrics"

echo "Verified $snapshot_name: $sqlite_ok database(s), $pgdump_ok archive(s), all clean ($sqlite_other named like one but are not)"
