#!/usr/bin/env bash

. ./scripts/lib/all.sh

set -euo pipefail

cleanup_hook() {
    error "$0 failed"
}

title "$(basename "$0")"

parent="$(dirname "$0" | cut -f2- -d'/')" # 'addlicense' doesn't like the leading './' in the '-ignore' pattern
args=(
    -f "${parent}/gpl-header.txt"
    # just ignore your parent, because they just won't change! :'C
    -ignore "${parent}/*"
    -ignore ".sops.yaml"
    -ignore "secrets/*"
    -ignore ".git/*"
    .
)

# add extra args
if [ "$#" -ge 0 ]; then
    args=("${@}" "${args[@]}") # prepend since 'addlicense' wants flags declared first
fi

info "Running '$(fmt_blue "addlicense ${args[*]}")'..."
addlicense "${args[@]}"
success "Done"
