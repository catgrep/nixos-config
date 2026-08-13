#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
normalizer="$project_root/hosts/ser8/media/nzbget-normalize-permissions.sh"
test_root=$(mktemp -d)
media_group=$(id -gn)
directory_mode=2775

if [ "$(uname -s)" = "Darwin" ]; then
	directory_mode=0775
fi

cleanup() {
	find "$test_root" -depth -delete
}
trap cleanup EXIT

job="$test_root/complete/tv/release"
restricted_dir="$job/nested/restrictive"
mkdir -p "$restricted_dir"
touch "$restricted_dir/episode.mkv"
chmod 0755 "$restricted_dir"
chmod 0644 "$restricted_dir/episode.mkv"

set +e
NZBPP_TOTALSTATUS=SUCCESS \
	NZBPP_DIRECTORY="$job" \
	NZBGET_COMPLETE_ROOT="$test_root/complete" \
	NZBGET_MEDIA_GROUP="$media_group" \
	NZBGET_DIRECTORY_MODE="$directory_mode" \
	bash "$normalizer"
status=$?
set -e

if [ "$status" -ne 93 ]; then
	echo "Normalizer returned $status instead of 93" >&2
	exit 1
fi

bad_dir=$(find "$job" -type d ! -perm "$directory_mode" -print -quit)
bad_file=$(find "$job" -type f ! -perm 0664 -print -quit)
bad_group=$(find "$job" ! -group "$media_group" -print -quit)

if [ -n "$bad_dir" ] || [ -n "$bad_file" ] || [ -n "$bad_group" ]; then
	echo "Permission normalization failed" >&2
	exit 1
fi

outside_dir="$test_root/outside"
mkdir "$outside_dir"

set +e
NZBPP_TOTALSTATUS=SUCCESS \
	NZBPP_DIRECTORY="$outside_dir" \
	NZBGET_COMPLETE_ROOT="$test_root/complete" \
	NZBGET_MEDIA_GROUP="$media_group" \
	bash "$normalizer" >/dev/null 2>&1
outside_status=$?

NZBPP_TOTALSTATUS=FAILURE \
	NZBPP_DIRECTORY="$job" \
	NZBGET_COMPLETE_ROOT="$test_root/complete" \
	NZBGET_MEDIA_GROUP="$media_group" \
	bash "$normalizer" >/dev/null
failed_job_status=$?
set -e

if [ "$outside_status" -ne 94 ] || [ "$failed_job_status" -ne 95 ]; then
	echo "Normalizer did not reject unsafe or failed jobs" >&2
	exit 1
fi

echo "NZBGet permission normalization passed"
