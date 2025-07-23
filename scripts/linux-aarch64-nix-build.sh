#!/usr/bin/env bash
. ./scripts/common.sh

set -euo pipefail

cleanup_hook() {
	errmsg "$0: 'nix build' of '${nixattr}' for '${artifact}' failed!"
}

nixattr="$1"
artifact="$2"

# Disable auto GC so /nix/store binaries don't get removed from the
# docker volume
cat >/nix/nix.conf <<EOF
echo 'auto-optimise-store = false'
echo 'min-free = 0'
echo 'max-free = 0'
EOF

infomsg "$0: starting 'nix build' of '${nixattr}' for '${artifact}'..."

outlink_path=/tmp/result
infomsg "$0: out-link path: ${outlink_path}"
result_path=$(
	nix build ".#${nixattr}" \
		--extra-experimental-features 'nix-command flakes' \
		--accept-flake-config \
		--out-link "${outlink_path}" \
		--print-out-paths \
		--show-trace
)

infomsg "$0: result path: $result_path"

# We want to expand the $artifact glob (should only be one file)
artifact_path=$(find -L "${outlink_path}" -wholename "${artifact}" -type f)
infomsg "$0: found artifact: ${artifact_path}"
cp -v -L -r --no-preserve=mode,ownership "${artifact_path}" /tmp/output/
