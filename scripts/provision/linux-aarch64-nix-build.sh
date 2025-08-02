#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/provision/common.sh

set -euo pipefail

cleanup_hook() {
    fail "$0: 'nix build' of '${nixattr}' for '${artifact}' failed!"
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

info "$0: starting 'nix build' of '${nixattr}' for '${artifact}'..."

outlink_path=/tmp/result
info "$0: out-link path: ${outlink_path}"
result_path=$(
    nix build ".#${nixattr}" \
        --extra-experimental-features 'nix-command flakes' \
        --accept-flake-config \
        --out-link "${outlink_path}" \
        --print-out-paths \
        --show-trace
)

info "$0: result path: $result_path"

artifact_path="${outlink_path}/${artifact}"
if [ ! -f "${artifact_path}" ]; then
    fail "$0: artifact not found: ${artifact_path}"
    exit 1
fi

info "$0: copying out artifact: ${artifact_path}"
cp -v -L -r --no-preserve=mode,ownership "${outlink_path}/${artifact}" /tmp/output/
