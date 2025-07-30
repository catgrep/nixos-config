#!/usr/bin/env bash

. ./scripts/provision/common.sh

set -euo pipefail

cleanup_hook() {
	install_failure_msg_hook
}

install_success_msg_hook() {
	local hostname="$1"
	local target_ip="$2"

	echo ""
	info "$0: pi installation complete!"
	echo ""
	info "Next steps:"
	echo "1. System will reboot automatically"
	echo "2. Remove old SSH key: ssh-keygen -R ${target_ip}"
	echo "3. Connect as user: ssh bdhill@${target_ip}"
	echo "4. Deploy full config: make apply-${hostname}"
	echo ""
	info "Pi4 specific notes:"
	echo "- The SD card has been repartitioned with your disko config"
	echo "- Boot firmware is on the FIRMWARE partition"
	echo "- Root filesystem is on the NIXOS_SD partition"
}

install_failure_msg_hook() {
	error "$0: installation failed!"
	echo ""
	info "Troubleshooting:"
	echo "1. Check if the Pi is still responsive via SSH"
	echo "2. If not, re-flash the installer image to SD card"
	echo "3. Verify your disko-config.nix uses correct device paths"
	echo "4. Ensure sufficient RAM is available for kexec"
}

nixos_anywhere_run_hook() {
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	if [ ! -f "./result/nixos-kexec-installer-aarch64-linux.tar.gz" ]; then
		error "$0: could not find kexec installer. Please run 'make aarch64-kexec'."
		exit 1
	fi

	echo ""
	info "$0: running nixos-anywhere with kexec for the Raspberry Pi..."
	info "This will:"
	echo "1. Upload and execute kexec to load minimal system into RAM"
	echo "2. Repartition the SD card using disko"
	echo "3. Install NixOS to the new partitions"
	echo ""

	nixos-anywhere \
		--flake ".#provisioning-${hostname}" \
		--target-host "$user@$target_ip" \
		--kexec "./result/nixos-kexec-installer-aarch64-linux.tar.gz" \
		--build-on-remote \
		--print-build-logs \
		--generate-hardware-config nixos-generate-config "./hosts/${hostname}/hardware-configuration.nix" \
		--debug
}

title "aarch64 pi-visioning"
libmain "$@"
