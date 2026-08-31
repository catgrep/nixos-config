#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

### NZBGET POST-PROCESSING SCRIPT ###

# Some indexers wrap releases in an obfuscated outer archive. NZBGet only
# unpacks one layer, which leaves the original scene RAR or 7z set behind
# and gives Sonarr and Radarr nothing importable. This script extracts any
# archive sets still present after unpack, in place next to their volumes,
# and deletes the volumes only after their extraction succeeded.

set -euo pipefail
shopt -s nullglob

readonly POSTPROCESS_SUCCESS=93
readonly POSTPROCESS_ERROR=94
readonly POSTPROCESS_NONE=95
readonly MAX_PASSES=3

if [ "${NZBPP_TOTALSTATUS:-}" != "SUCCESS" ]; then
	echo "Skipping nested extraction for status ${NZBPP_TOTALSTATUS:-unknown}"
	exit "$POSTPROCESS_NONE"
fi

download_dir=${NZBPP_DIRECTORY:-}
complete_root=${NZBGET_COMPLETE_ROOT:-/mnt/downloads/complete}

if [ -z "$download_dir" ]; then
	echo "[ERROR] NZBPP_DIRECTORY is empty"
	exit "$POSTPROCESS_ERROR"
fi

complete_root=$(realpath -e -- "$complete_root")
download_dir=$(realpath -e -- "$download_dir")
cd /

case "$download_dir" in
"$complete_root"/*) ;;
*)
	echo "[ERROR] Refusing to touch path outside $complete_root: $download_dir"
	exit "$POSTPROCESS_ERROR"
	;;
esac

# Print the first volume of every archive set under the download directory:
# plain .rar, .part1/.part01/.part001 of part-numbered RAR sets, single .7z,
# and .001 of split 7z sets. Later volumes are handled by the extractors.
find_first_volumes() {
	local file base
	while IFS= read -r -d '' file; do
		base=$(basename "$file")
		case "$base" in
		*.part*.rar)
			case "$base" in
			*.part1.rar | *.part01.rar | *.part001.rar) printf '%s\0' "$file" ;;
			esac
			;;
		*.rar | *.7z | *.7z.001)
			printf '%s\0' "$file"
			;;
		esac
	done < <(find "$download_dir" -type f \
		\( -iname '*.rar' -o -iname '*.7z' -o -iname '*.7z.001' \) -print0)
}

extract_one() {
	local first=$1 dir
	dir=$(dirname "$first")
	echo "[INFO] Extracting nested archive $first"
	case "$first" in
	*.rar)
		unrar x -o+ -p- -idq -- "$first" "$dir/"
		;;
	*)
		7z x -y -bd -bso0 -bsp0 -o"$dir" -- "$first"
		;;
	esac
}

delete_volumes() {
	local first=$1 dir base volume
	dir=$(dirname "$first")
	base=$(basename "$first")
	case "$base" in
	*.part*.rar)
		for volume in "$dir/${base%.part*.rar}".part*.rar; do
			rm -f -- "$volume"
		done
		;;
	*.rar)
		rm -f -- "$first"
		for volume in "$dir/${base%.rar}".[r-z][0-9][0-9]; do
			rm -f -- "$volume"
		done
		;;
	*.7z.001)
		for volume in "$dir/${base%.001}".[0-9][0-9][0-9]; do
			rm -f -- "$volume"
		done
		;;
	*.7z)
		rm -f -- "$first"
		;;
	esac
}

overall_status=$POSTPROCESS_NONE
for ((pass = 1; pass <= MAX_PASSES; pass++)); do
	mapfile -d '' -t volumes < <(find_first_volumes)
	if [ "${#volumes[@]}" -eq 0 ]; then
		break
	fi
	echo "[INFO] Pass $pass: found ${#volumes[@]} nested archive set(s)"
	for first in "${volumes[@]}"; do
		if extract_one "$first"; then
			delete_volumes "$first"
			echo "[INFO] Extracted and removed archive set $(basename "$first")"
			overall_status=$POSTPROCESS_SUCCESS
		else
			echo "[ERROR] Extraction failed for $first; keeping all archive files"
			exit "$POSTPROCESS_ERROR"
		fi
	done
done

if [ "$overall_status" -eq "$POSTPROCESS_NONE" ]; then
	echo "No nested archives found in $download_dir"
else
	echo "Nested archive extraction complete for $download_dir"
fi
exit "$overall_status"
