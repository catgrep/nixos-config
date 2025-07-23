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

artifact_path="${outlink_path}/${artifact}"
if [ ! -f "${artifact_path}" ]; then
	errmsg "$0: artifact not found: ${artifact_path}"
	exit 1
fi

infomsg "$0: copying out artifact: ${artifact_path}"
cp -v -L -r --no-preserve=mode,ownership "${outlink_path}/${artifact}" /tmp/output/
