#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/sops/common.sh

set -euo pipefail

cleanup_hook() {
    error "$0: sops failed"
}

if [ $# -lt 1 ]; then
    exit 1
fi

host="$1"
if [ -f "./secrets/$host.yaml" ]; then
    error "'./secrets/$host.yaml' already exists"
    exit 1
fi

# Update .sops.yaml
yq -e -i "
    .creation_rules +=
    {
    \"path_regex\": \"^secrets/$host.yaml$\",
        \"key_groups\": [
            {
                \"pgp\": [],
                \"age\": []
            }
        ]
    } |
    .creation_rules[-1].key_groups[].pgp = [ \"admin_$USER\" ] |
    .creation_rules[-1].key_groups[].pgp[0] alias = \"admin_$USER\" |
    .creation_rules[-1].key_groups[].age = [ \"server_$host\" ] |
    .creation_rules[-1].key_groups[].age[0] alias = \"server_$host\" |
    .creation_rules[-1] head_comment = \"Added '$host' secrets file with '$0' on $(date)\"
" "$SOPS_CONFIG"

success "Updated '$SOPS_CONFIG':"
print_yaml "$SOPS_CONFIG"

info "Run 'sops edit secrets/$host.yaml' to add secrets."
