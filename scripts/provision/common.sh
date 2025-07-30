#!/usr/bin/env bash

. ./scripts/lib/all.sh

set -euo pipefail

# Show usage
usage() {
	title "Usage: $0 <hostname> <target-ip> [options]"
	echo ""
	echo "Provision NixOS to a target machine using nixos-anywhere"
	echo ""
	title "Arguments:"
	echo "  hostname    Name of the host to provision"
	echo "  target-ip   IP address of the target machine"
	echo ""
	title "Options:"
	echo "  --user      User with sudo access (defaults to 'root')"
	echo "  --help      Show this help message"
	echo ""
	title "Examples:"
	echo "$0 beelink 192.168.1.20"
}

pre_install_checks() {
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	info "NixOS Anywhere Deployment"
	info "Hostname: ${user}@${hostname}"
	info "IP Address: $target_ip"
	echo ""

	# Check connectivity
	info "Checking SSH connection..."
	if ! ssh -o ConnectTimeout=5 "${user}@${target_ip}" "echo 'OK'" 2>/dev/null; then
		error "Cannot connect to ${user}@${target_ip}"
		echo ""
		info "On the target machine, ensure you have:"
		info "1. Set root password: sudo passwd"
		info "2. Started SSH (usually automatic in installer)"
		exit 1
	fi
	info "✓ Connected"

	# Show disk information
	echo ""
	info "Target disk configuration:"
	ssh "${user}@${target_ip}" "lsblk -o NAME,SIZE,TYPE,ID-LINK"

	echo ""
	info "Disk by-id mappings:"
	ssh "${user}@${target_ip}" "ls -la /dev/disk/by-id/ | grep -v 'part\|total' | grep -E 'ata-|nvme-|mmc-|usb-'" || true

	echo ""
	info "Current root filesystem:"
	ssh "${user}@${target_ip}" "df -h /"

	echo ""
	info "Available memory (for kexec):"
	ssh "${user}@${target_ip}" "free -h"

	echo ""
	error "WARNING: This will ERASE all data on the configured disks!"
	error "Check that hosts/${hostname}/disko-config.nix has the correct disk devices (use /dev/disk/by-id/ID)"
	echo ""

	# Confirm
	read -p "Continue with installation? (y/N) " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Aborted."
		exit 1
	fi
}

menu() {
	if [ $# -lt 2 ]; then
		usage
		return 1
	fi

	user="root"
	hostname="$1"
	target_ip="$2"
	shift 2

	# Parse options
	while [[ $# -gt 0 ]]; do
		case $1 in
		--user)
			user="$2"
			shift
			shift
			;;
		--help)
			usage
			return 0
			;;
		*)
			error "Unknown option: $1"
			usage
			return 1
			;;
		esac
	done
	echo "$user" "$hostname" "$target_ip"
}

libmain() {
	local args
	if ! args=$(menu "$@"); then
		echo "$args"
		return 0
	fi

	set -- $args
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	if ! pre_install_checks "$user" "$hostname" "$target_ip"; then
		error "Pre-install Checks Failed! ${user}@${target_ip}"
		return 1
	fi
	if ! nixos_anywhere_run_hook "$user" "$hostname" "$target_ip"; then
		return 1
	fi
	install_success_msg_hook "$hostname" "$target_ip"
	return 0
}
