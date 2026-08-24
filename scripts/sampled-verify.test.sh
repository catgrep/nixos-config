#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Local self-tests for scripts/sampled-verify.sh (D-07). Exercises all five
# behavior cases using 'mktemp -d' fixtures -- no network or SSH required.

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
script="$project_root/scripts/sampled-verify.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

pass_count=0
fail_count=0

report() {
	# $1 = test name, $2 = expected exit, $3 = actual exit
	if [ "$2" -eq "$3" ]; then
		echo "PASS: $1"
		pass_count=$((pass_count + 1))
	else
		echo "FAIL: $1 (expected exit $2, got $3)" >&2
		fail_count=$((fail_count + 1))
	fi
}

## Test 1: identical trees -> exit 0, manifest reports no differences
t1_src=$(mktemp -d)
t1_dst=$(mktemp -d)
mkdir -p "$t1_src/nested"
echo "hello world" >"$t1_src/small.txt"
echo "hello world" >"$t1_src/nested/small2.txt"
cp -a "$t1_src/." "$t1_dst/"
t1_manifest="$work_dir/t1-manifest.txt"
set +e
bash "$script" "$t1_src" "$t1_dst" "$t1_manifest"
t1_status=$?
set -e
report "identical trees" 0 "$t1_status"
if grep -q "PASS" "$t1_manifest" && ! grep -qE 'CONTENT-MISMATCH|METADATA-DIFF|MISSING' "$t1_manifest"; then
	echo "PASS: identical trees manifest has no diff lines"
	pass_count=$((pass_count + 1))
else
	echo "FAIL: identical trees manifest unexpectedly reports a diff" >&2
	fail_count=$((fail_count + 1))
fi
rm -rf "$t1_src" "$t1_dst"

## Test 2: large file (>1 MiB), last byte differs -> tail sample catches it
t2_src=$(mktemp -d)
t2_dst=$(mktemp -d)
head -c 2000000 /dev/urandom >"$t2_src/large.bin"
cp -a "$t2_src/large.bin" "$t2_dst/large.bin"
printf '\x00' | dd of="$t2_dst/large.bin" bs=1 seek=1999999 count=1 conv=notrunc status=none
t2_manifest="$work_dir/t2-manifest.txt"
set +e
bash "$script" "$t2_src" "$t2_dst" "$t2_manifest"
t2_status=$?
set -e
report "large file, last-byte mismatch caught by tail sample" 1 "$t2_status"
if grep -q "large.bin" "$t2_manifest"; then
	echo "PASS: manifest names the differing large file"
	pass_count=$((pass_count + 1))
else
	echo "FAIL: manifest does not name the differing large file" >&2
	fail_count=$((fail_count + 1))
fi
rm -rf "$t2_src" "$t2_dst"

## Test 3: small file (<1 MiB), one byte differs anywhere -> full hash catches it
t3_src=$(mktemp -d)
t3_dst=$(mktemp -d)
echo "content-a" >"$t3_src/small.txt"
echo "content-b" >"$t3_dst/small.txt"
t3_manifest="$work_dir/t3-manifest.txt"
set +e
bash "$script" "$t3_src" "$t3_dst" "$t3_manifest"
t3_status=$?
set -e
report "small file content mismatch caught by full hash" 1 "$t3_status"
rm -rf "$t3_src" "$t3_dst"

## Test 4: identical content, differing mode -> metadata dry run catches it
t4_src=$(mktemp -d)
t4_dst=$(mktemp -d)
echo "same content" >"$t4_src/file.txt"
cp -a "$t4_src/file.txt" "$t4_dst/file.txt"
chmod 0644 "$t4_src/file.txt"
chmod 0600 "$t4_dst/file.txt"
t4_manifest="$work_dir/t4-manifest.txt"
set +e
bash "$script" "$t4_src" "$t4_dst" "$t4_manifest"
t4_status=$?
set -e
report "metadata-only mismatch (mode) caught by rsync dry run" 1 "$t4_status"
rm -rf "$t4_src" "$t4_dst"

## Test 5: empty source and destination -> exit 0, no files is not an error
t5_src=$(mktemp -d)
t5_dst=$(mktemp -d)
t5_manifest="$work_dir/t5-manifest.txt"
set +e
bash "$script" "$t5_src" "$t5_dst" "$t5_manifest"
t5_status=$?
set -e
report "empty source and destination" 0 "$t5_status"
rm -rf "$t5_src" "$t5_dst"

echo ""
echo "$pass_count passed, $fail_count failed"

if [ "$fail_count" -ne 0 ]; then
	exit 1
fi

exit 0
