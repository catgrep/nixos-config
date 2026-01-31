#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Add/update shared secrets file rule in .sops.yaml
# This file is readable by ALL hosts (all age keys included)

. ./scripts/sops/__base__

set -euo pipefail

SHARED_REGEX="^secrets/shared.yaml\$"

# Check if shared rule already exists
if yq -e ".creation_rules[] | select(.path_regex == \"$SHARED_REGEX\")" "$SOPS_CONFIG" &>/dev/null; then
    info "Shared secrets rule already exists in $SOPS_CONFIG"
    info "Edit with: $(fmt_blue "make sops-edit-shared")"
    exit 0
fi

info "Adding shared secrets rule to '$SOPS_CONFIG'"

# Get admin user anchor name
admin_anchor="admin_$USER"
info "Using admin key: $(fmt_blue "$admin_anchor")"

# Get all server age key anchors from .sops.yaml
server_anchors=$(yq -e '.keys[] | anchor | select(. == "server_*")' "$SOPS_CONFIG" 2>/dev/null || true)
if [ -z "$server_anchors" ]; then
    fail "No server age keys found in $SOPS_CONFIG"
    fail "Run '$(fmt_blue "make sops-add-host-keys")' first"
    exit 1
fi

info "Found server keys: $(fmt_blue "$(echo "$server_anchors" | tr '\n' ' ')")"

# Add the creation rule using yq with aliases
# This mirrors the structure of the global secrets rule but with explicit path
yq -e -i "
    .creation_rules +=
    {
        \"path_regex\": \"$SHARED_REGEX\",
        \"key_groups\": [
            {
                \"pgp\": [],
                \"age\": []
            }
        ]
    } |
    .creation_rules[-1].key_groups[].pgp = [ \"$admin_anchor\" ] |
    .creation_rules[-1].key_groups[].pgp[0] alias = \"$admin_anchor\" |
    .creation_rules[-1].key_groups[].age = [ $(echo "$server_anchors" | while read anchor; do printf '"%s", ' "$anchor"; done | sed 's/, $//') ] |
    .creation_rules[-1] head_comment = \"Shared secrets file (all hosts) added with '$0' on $(date)\"
" "$SOPS_CONFIG"

# Set aliases for all age keys
idx=0
for anchor in $server_anchors; do
    yq -e -i ".creation_rules[-1].key_groups[].age[$idx] alias = \"$anchor\"" "$SOPS_CONFIG"
    idx=$((idx + 1))
done

pass "Added shared secrets rule to '$SOPS_CONFIG'"
print_yaml "$SOPS_CONFIG"

info "Create/edit shared secrets with: $(fmt_blue "make sops-edit-shared")"
