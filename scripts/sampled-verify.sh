#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Sampled + metadata verification between two directory trees (D-07/D-09).
#
# Compares SOURCE against DEST using:
#   - full sha256 comparison for files under 1 MiB
#   - deterministic per-file sampling (head, tail, and roughly one sample per
#     GiB) for files 1 MiB and larger, with sample points computed from the
#     SOURCE file size only, so they are reproducible on any hop (source,
#     staging, mirror)
#   - a 100%-coverage metadata-only 'rsync --dry-run' pass covering size,
#     mtime, mode, uid, gid, type, symlink targets, hardlink grouping, ACLs,
#     and xattrs
#
# The manifest file is always written, on both PASS and FAIL. Exit status is
# derived solely from "was any difference found" -- never from a
# sub-command's own exit status, since 'rsync' exits 0 even when
# '--itemize-changes' reports differences.
#
# Usage: sampled-verify.sh <source_dir> <dest_dir> <manifest_file>

set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "Usage: $0 <source_dir> <dest_dir> <manifest_file>" >&2
	exit 2
fi

source_dir=${1%/}
dest_dir=${2%/}
manifest_file=$3

if [ ! -d "$source_dir" ]; then
	echo "Source directory does not exist: $source_dir" >&2
	exit 2
fi

if [ ! -d "$dest_dir" ]; then
	echo "Destination directory does not exist: $dest_dir" >&2
	exit 2
fi

one_mib=1048576
one_gib=1073741824
small_file_threshold=$one_mib

diff_log=$(mktemp)
files_list=$(mktemp)
trap 'rm -f "$diff_log" "$files_list"' EXIT

# Detect GNU vs BSD 'stat' once, rather than probing on every file.
if stat -c%s "$source_dir" >/dev/null 2>&1; then
	stat_size() { stat -c%s "$1"; }
else
	stat_size() { stat -f%z "$1"; }
fi

sha_of_file() {
	sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

sha_of_block() {
	# $1 = path, $2 = 1-MiB-aligned block index
	dd if="$1" bs=1M skip="$2" count=1 status=none 2>/dev/null | sha256sum | awk '{print $1}'
}

files_sampled=0

find "$source_dir" -type f -print0 >"$files_list"

while IFS= read -r -d '' src_path; do
	rel_path=${src_path#"$source_dir"/}
	dest_path="$dest_dir/$rel_path"
	files_sampled=$((files_sampled + 1))

	if [ ! -e "$dest_path" ]; then
		echo "MISSING $rel_path" >>"$diff_log"
		continue
	fi

	size=$(stat_size "$src_path")

	if [ "$size" -lt "$small_file_threshold" ]; then
		src_hash=$(sha_of_file "$src_path") || true
		dst_hash=$(sha_of_file "$dest_path") || true
		if [ "$src_hash" != "$dst_hash" ]; then
			echo "CONTENT-MISMATCH $rel_path (full hash)" >>"$diff_log"
		fi
		continue
	fi

	# Sample in 1-MiB-block-index space (not raw byte offsets) so the head
	# and tail samples always land on the file's true first and last bytes,
	# regardless of whether the file size is a multiple of 1 MiB.
	total_blocks=$(((size + one_mib - 1) / one_mib))
	last_block=$((total_blocks - 1))

	sample_points=$((size / one_gib))
	if [ "$sample_points" -lt 1 ]; then
		sample_points=1
	fi

	blocks=(0 "$last_block")
	i=0
	while [ "$i" -lt "$sample_points" ]; do
		blocks+=("$((i * total_blocks / sample_points))")
		i=$((i + 1))
	done

	unique_blocks_str=$(printf '%s\n' "${blocks[@]}" | sort -nu)
	mapfile -t unique_blocks <<<"$unique_blocks_str"

	for block in "${unique_blocks[@]}"; do
		src_hash=$(sha_of_block "$src_path" "$block") || true
		dst_hash=$(sha_of_block "$dest_path" "$block") || true
		if [ "$src_hash" != "$dst_hash" ]; then
			echo "CONTENT-MISMATCH $rel_path (sample block $block)" >>"$diff_log"
			break
		fi
	done
done <"$files_list"

# 100%-coverage metadata-only pass (no --checksum: stat-based, catches
# size/mtime/mode/uid/gid/type/symlink-target/hardlink-grouping/ACL/xattr
# differences that content sampling alone would miss).
metadata_diff=$(rsync -aHAXn --numeric-ids --itemize-changes --out-format='%i %n' "$source_dir/" "$dest_dir/" 2>&1) || true
if [ -n "$metadata_diff" ]; then
	printf 'METADATA-DIFF %s\n' "$metadata_diff" >>"$diff_log"
fi

{
	echo "sampled-verify run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "source: $source_dir"
	echo "dest:   $dest_dir"
	echo "files sampled (content pass): $files_sampled"
	echo ""
	if [ -s "$diff_log" ]; then
		echo "FAIL -- differences found:"
		cat "$diff_log"
	else
		echo "PASS -- $files_sampled files sampled, 0 differences"
	fi
} >"$manifest_file"

# The exit status is derived exclusively from "was the diff log non-empty" --
# never from rsync's or any sub-command's own exit status.
if [ -s "$diff_log" ]; then
	exit 1
fi

exit 0
