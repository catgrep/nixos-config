#!/usr/bin/env bash

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

	if ping -c 1 -W 2 "$address" >/dev/null 2>&1; then
		local host_ssh_key
		host_ssh_key=$(ssh-keyscan -t ed25519 "$address" 2>/dev/null | grep -v "^#")
		mkdir -p "${HOST_KEYS_SECRETS_DIR}"
		echo "$host_ssh_key" >"${HOST_KEYS_SECRETS_DIR}/${hostname}.pub"
		success "Got key for $hostname"
		HOST_KEYS[$hostname]=true
	fi
	return 1
}

# Try to get keys for all hosts
if [[ -d "hosts" ]]; then
	for host_dir in hosts/*/; do
		# If we don't have it already, cache it
		hostname=$(basename "$host_dir")
		if [ -f "${HOST_KEYS_SECRETS_DIR}/${hostname}.pub" ]; then
			success "Got key for $hostname"
			HOST_KEYS[$hostname]=true
			continue
		fi
		info "Checking $hostname..."
		cache_host_key "$hostname" "${hostname}.local" ||
			error "Could not reach $hostname"
	done
fi

# Add host keys to config
HOSTS_FOUND=0
for hostname in "${!HOST_KEYS[@]}"; do
	age_key=$(ssh-to-age -i "${HOST_KEYS_SECRETS_DIR}/${hostname}.pub")
	yq -i "
        .keys += [ \"${age_key}\" ] |
        .keys[-1] anchor = \"server_${hostname}\"
    " "$SOPS_CONFIG"
	yq -i "
    .creation_rules[].key_groups[].age += [ \"server_${hostname}\"] |
    .creation_rules[].key_groups[].age[-1] alias = \"server_${hostname}\"
    " "$SOPS_CONFIG"
	((HOSTS_FOUND += 1))
done

success "Generated '$SOPS_CONFIG' with '$HOSTS_FOUND' host keys:"
yq eval -P "$SOPS_CONFIG"
