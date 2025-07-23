#!/usr/bin/env bash
set -euo pipefail

cleanup() {
	ec=$?
	if [ $ec -ne 0 ]; then
		cleanup_hook || errmsg "$0: script failed with exit code: $ec"
	fi
}
trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

infomsg() {
	echo -e "${CYAN}$1${NC}"
}

errmsg() {
	echo -e "${RED}$1${NC}"
}

warnmsg() {
	echo -e "${YELLOW}$1${NC}"
}

msg() {
	echo -e "${GREEN}$1${NC}"
}

# Show usage
usage() {
	infomsg "Usage: $0 <hostname> <target-ip> [options]"
	echo ""
	echo "Provision NixOS to a target machine using nixos-anywhere"
	echo ""
	infomsg "Arguments:"
	echo "  hostname    Name of the host to provision"
	echo "  target-ip   IP address of the target machine"
	echo ""
	infomsg "Options:"
	echo "  --user      User with sudo access (defaults to 'root')"
	echo "  --help      Show this help message"
	echo ""
	infomsg "Examples:"
	echo "$0 beelink 192.168.1.20"
}

pre_install_checks() {
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	msg "NixOS Anywhere Deployment"
	infomsg "Hostname: ${user}@${hostname}"
	infomsg "IP Address: $target_ip"
	echo ""

	# Check connectivity
	warnmsg "Checking SSH connection..."
	if ! ssh -o ConnectTimeout=5 "${user}@${target_ip}" "echo 'OK'" 2>/dev/null; then
		errmsg "Cannot connect to ${user}@${target_ip}"
		echo ""
		warnmsg "On the target machine, ensure you have:"
		warnmsg "1. Set root password: sudo passwd"
		warnmsg "2. Started SSH (usually automatic in installer)"
		exit 1
	fi
	msg "✓ Connected"

	# Show disk information
	echo ""
	warnmsg "Target disk configuration:"
	ssh "${user}@${target_ip}" "lsblk -o NAME,SIZE,TYPE,ID-LINK"

	echo ""
	warnmsg "Disk by-id mappings:"
	ssh "${user}@${target_ip}" "ls -la /dev/disk/by-id/ | grep -v 'part\|total' | grep -E 'ata-|nvme-|mmc-|usb-'" || true

	echo ""
	warnmsg "Current root filesystem:"
	ssh "${user}@${target_ip}" "df -h /"

	echo ""
	warnmsg "Available memory (for kexec):"
	ssh "${user}@${target_ip}" "free -h"

	echo ""
	errmsg "WARNING: This will ERASE all data on the configured disks!"
	errmsg "Check that hosts/${hostname}/disko-config.nix has the correct disk devices (use /dev/disk/by-id/ID)"
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
			errmsg "Unknown option: $1"
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
		return 1
	fi

	set -- $args
	local user="$1"
	local hostname="$2"
	local target_ip="$3"

	if ! pre_install_checks "$user" "$hostname" "$target_ip"; then
		errmsg "Pre-install Checks Failed! ${user}@${target_ip}"
		return 1
	fi
	if ! nixos_anywhere_run_hook "$user" "$hostname" "$target_ip"; then
		install_failure_msg_hook "$hostname" "$target_ip"
		return 1
	fi
	install_success_msg_hook "$hostname" "$target_ip"
	return 0
}
