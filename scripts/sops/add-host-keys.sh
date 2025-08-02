#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/sops/common.sh

set -euo pipefail

cleanup_hook() {
    error "$0: sops failed"
}

# Collect host keys
info "Collecting host keys..."
declare -A HOST_KEYS

cache_host_key() {
    local hostname=$1
    local address=$2

    if ! ping -c 1 -W 2 "$address" >/dev/null 2>&1; then
        error "Could not ping '$hostname' with address '$address'"
        return 1
    fi

    # Download 'ed25519' host key if host is reachable
    # NOTE: only ed25519 is supported by 'ssh-to-age'
    local host_ssh_key
    if host_ssh_key=$(ssh-keyscan -t ed25519 "$address" 2>/dev/null | grep -v "^#"); then
        mkdir -p "${HOST_KEYS_SECRETS_DIR}"
        echo "$host_ssh_key" >"${HOST_KEYS_SECRETS_DIR}/${hostname}.pub"
        success "Got key for $hostname"
        HOST_KEYS[$hostname]=true
    else
        error "Could not fetch host key for '$hostname' with address '$address'"
        return 1
    fi
}

# Try to get keys for all hosts
if [[ -d "hosts" ]]; then
    for hostname in $(list_hosts); do
        # Check if its been cached already
        if [ -f "${HOST_KEYS_SECRETS_DIR}/${hostname}.pub" ]; then
            success "Got key for $hostname"
            HOST_KEYS[$hostname]=true
        else
            # If we don't have it already, fetch and cache it
            info "Checking $hostname..."
            cache_host_key "$hostname" "$(get_ip "$hostname")" ||
                error "Could not reach $hostname"
        fi
    done
fi

# Add any new host keys to config
HOSTS_FOUND=0
for hostname in "${!HOST_KEYS[@]}"; do
    new_age_key=$(ssh-to-age -i "${HOST_KEYS_SECRETS_DIR}/${hostname}.pub")

    # Case 1: If the host exists in '.sops.yaml', get its age key
    if old_age_key=$(
        yq -e "
            .keys[] |
            select(anchor == \"server_$hostname\")
        " "$SOPS_CONFIG"
    ) >/dev/null 2>&1; then
        # 1) if the age key is unchanged, do nothing and continue
        if [ "$old_age_key" = "$new_age_key" ]; then
            info "host '$hostname' age key unchanged, skipping..."
            continue
        fi

        # 2) otherwise, update the age key and prompt 'update keys'
        yq -e -i "
            (
                .keys[] |
                select(anchor == \"server_$hostname\")
            ) |=
            (
                . |
                . head_comment=\"Updated '$hostname' SSH age key with '$0' on $(date)\" |
                . = \"$new_age_key\"
            )
        " "$SOPS_CONFIG"

        # 3) check if we should run 'sops updatekeys' on the host secrets file
        info "host '$hostname' age key updated"
        if [ ! -f "${SECRETS_DIR}/${hostname}.yaml" ]; then
            info "host '$hostname' has no secrets file to update"
        else
            info "running 'sops updatekeys ${SECRETS_DIR}/${hostname}.yaml' to persist changes..."
            sops updatekeys "${SECRETS_DIR}/${hostname}.yaml"
        fi
    else
        # Case 2: If the host doesn't exist in '.sops.yaml', add a new host
        yq -e -i "
            .keys += [ \"${new_age_key}\" ] |
            .keys[-1] anchor = \"server_${hostname}\" |
            .keys[-1] head_comment = \"Added '$hostname' SSH age key with '$0' on $(date)\" |
            .creation_rules[0].key_groups[].age += [ \"server_${hostname}\"] |
            .creation_rules[0].key_groups[].age[-1] alias = \"server_${hostname}\"
        " "$SOPS_CONFIG"

        info "new host '$hostname' age key added"
        # NOTE: we don't need to run 'sops updatekeys' since there are no
        # secrets for this host yet.
    fi
    ((HOSTS_FOUND += 1))
done

success "Updated '$SOPS_CONFIG' with '$HOSTS_FOUND' host keys:"
print_yaml "$SOPS_CONFIG"
