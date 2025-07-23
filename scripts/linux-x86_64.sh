#!/usr/bin/env bash
source ./scripts/common.sh

set -euo pipefail

install_success_msg_hook() {
	local hostname="$1"
	local target_ip="$2"

	echo ""
	infomsg "✓ x86_64 Installation complete!"
	echo ""
	infomsg "Next steps:"
	echo "1. System will reboot automatically"
	echo "2. Remove old SSH key: ssh-keygen -R ${target_ip}"
	echo "3. Connect as user: ssh bdhill@${target_ip}"
	echo "4. Deploy full config: make apply-${hostname}"
}

install_failure_msg_hook() {
	errmsg "x86_64 Installation failed!"
}

nixos_anywhere_run_hook() {
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	echo ""
	msg "Running nixos-anywhere for x86_64..."

	nixos-anywhere \
		--flake ".#provisioning-${hostname}" \
		--target-host "${user}@${target_ip}" \
		--build-on-remote \
		--generate-hardware-config nixos-generate-config "./hosts/${hostname}/hardware-configuration.nix" \
		--debug
}

infomsg "=== x86_64 Provisioning ==="
libmain "$@"
