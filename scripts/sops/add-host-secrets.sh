#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/sops/__base__

set -euo pipefail

if [ $# -lt 1 ]; then
    exit 1
fi

host="$1"
if [ -f "./secrets/$host.yaml" ]; then
    fail "'./secrets/$host.yaml' already exists"
    exit 1
fi

info "adding entry for '$(fmt_blue "$host")' in '$SOPS_CONFIG'..."
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

pass "updated '$SOPS_CONFIG':"
print_yaml "$SOPS_CONFIG"

info "run '$(fmt_blue "sops edit secrets/$host.yaml")' to add secrets."
