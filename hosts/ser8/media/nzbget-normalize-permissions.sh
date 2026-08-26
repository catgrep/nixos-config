#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

### NZBGET POST-PROCESSING SCRIPT ###

set -euo pipefail

readonly POSTPROCESS_SUCCESS=93
readonly POSTPROCESS_ERROR=94
readonly POSTPROCESS_NONE=95

if [ "${NZBPP_TOTALSTATUS:-}" != "SUCCESS" ]; then
	echo "Skipping permission normalization for status ${NZBPP_TOTALSTATUS:-unknown}"
	exit "$POSTPROCESS_NONE"
fi

download_dir=${NZBPP_DIRECTORY:-}
complete_root=${NZBGET_COMPLETE_ROOT:-/mnt/downloads/complete}
media_group=${NZBGET_MEDIA_GROUP:-media}
directory_mode=${NZBGET_DIRECTORY_MODE:-2775}

if [ -z "$download_dir" ]; then
	echo "[ERROR] NZBPP_DIRECTORY is empty"
	exit "$POSTPROCESS_ERROR"
fi

trap 'echo "[ERROR] Could not normalize permissions for $download_dir"; exit 94' ERR

complete_root=$(realpath -e -- "$complete_root")
download_dir=$(realpath -e -- "$download_dir")
cd /

case "$download_dir" in
"$complete_root"/*) ;;
*)
	echo "[ERROR] Refusing to modify path outside $complete_root: $download_dir"
	exit "$POSTPROCESS_ERROR"
	;;
esac

chgrp -R -- "$media_group" "$download_dir"
find "$download_dir" -type d -exec chmod "$directory_mode" {} +
find "$download_dir" -type f -exec chmod 0664 {} +

echo "Normalized shared media permissions for $download_dir"
exit "$POSTPROCESS_SUCCESS"
