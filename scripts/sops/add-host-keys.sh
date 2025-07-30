#!/usr/bin/env bash

. ./scripts/sops/common.sh

set -euo pipefail

cleanup_hook() {
	error "$0: sops failed"
}

# Collect host keys
info "Collecting host keys..."
declare -A HOST_KEYS

# Function to get host key
get_host_key() {
	local hostname=$1
	local address=$2

	if ping -c 1 -W 2 "$address" >/dev/null 2>&1; then
		local host_ssh_key
		local age_key
		host_ssh_key=$(ssh-keyscan -t ed25519 "$address" 2>/dev/null)
		mkdir -p ${SECRETS_HOST_KEYS_DIR}
		echo "$host_ssh_key" >"${SECRETS_HOST_KEYS_DIR}/${hostname}.pub"
		age_key=$(ssh-to-age -i "${SECRETS_HOST_KEYS_DIR}/${hostname}.pub")
		if [[ -n "$age_key" ]]; then
			HOST_KEYS[$hostname]=$age_key
			success "Got key for $hostname"
			return 0
		fi
	fi
	return 1
}

# Try to get keys for all hosts
if [[ -d "hosts" ]]; then
	for host_dir in hosts/*/; do
		if [[ -d "$host_dir" ]]; then
			hostname=$(basename "$host_dir")
			info "Checking $hostname..."
			get_host_key "$hostname" "${hostname}.local" ||
				error "Could not reach $hostname"
		fi
	done
fi

# Add host keys to config
HOSTS_FOUND=0
for hostname in "${!HOST_KEYS[@]}"; do
	echo "          - ${HOST_KEYS[$hostname]} # $hostname" >>"$SOPS_CONFIG"
	((HOSTS_FOUND += 1))
done

success "Generated '$SOPS_CONFIG' with '$HOSTS_FOUND' host keys"
yq -s "." "$SOPS_CONFIG"
