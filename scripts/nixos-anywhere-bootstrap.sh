#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Show usage
usage() {
	echo "Usage: $0 <hostname> <target-ip> [options]"
	echo ""
	echo "Deploy NixOS to a target machine using nixos-anywhere"
	echo ""
	echo "Arguments:"
	echo "  hostname    Name of the host to deploy (beelink, firebat, pi4)"
	echo "  target-ip   IP address of the target machine"
	echo ""
	echo "Options:"
	echo "  --user              User with sudo access (defaults to 'root')"
	echo "  --env-passwd        Use password-based authentication over SSH"
	echo "  --help              Show this help message"
	echo ""
	echo "Examples:"
	echo "  $0 beelink 192.168.1.20"
	exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
	usage
fi

HOSTNAME="$1"
TARGET_IP="$2"
shift 2

# Default values
SSH_PASS_ENV_OPT=false
USER="root"

# Parse options
while [[ $# -gt 0 ]]; do
	case $1 in
	--user)
		USER="$2"
		shift
		shift
		;;
	--help)
		usage
		;;
	--env-passwd)
		SSH_PASS_ENV_OPT=true
		shift
		;;
	*)
		echo "Unknown option: $1"
		usage
		;;
	esac
done

# Validate hostname
case $HOSTNAME in
beelink | firebat | pi4) ;;
*)
	echo -e "${RED}Error: Unknown hostname '$HOSTNAME'${NC}"
	echo "Valid hostnames: beelink, firebat, pi4"
	exit 1
	;;
esac

echo -e "${GREEN}NixOS Anywhere Deployment${NC}"
echo -e "Target: ${CYAN}$HOSTNAME${NC} at ${CYAN}$TARGET_IP${NC}"
echo ""

# Check connectivity
echo -e "${YELLOW}Checking SSH connection...${NC}"
if ! ssh -o ConnectTimeout=5 "${USER}@${TARGET_IP}" "echo 'OK'" 2>/dev/null; then
	echo -e "${RED}Cannot connect to root@${TARGET_IP}${NC}"
	echo ""
	echo "On the target machine, ensure you have:"
	echo "1. Set root password: sudo passwd"
	echo "2. Started SSH (usually automatic in installer)"
	exit 1
fi
echo -e "${GREEN}✓ Connected${NC}"

# Show disk information
echo ""
echo -e "${YELLOW}Target disk configuration:${NC}"
ssh "${USER}@${TARGET_IP}" "lsblk -o NAME,SIZE,TYPE,ID-LINK"

echo ""
echo -e "${YELLOW}Disk by-id mappings:${NC}"
ssh "${USER}@${TARGET_IP}" "ls -la /dev/disk/by-id/ | grep -v 'part\|total' | grep -E 'ata-|nvme-|mmc-'" || true

echo ""
echo -e "${RED}WARNING: This will ERASE all data on the configured disks!${NC}"
echo -e "${RED}Check that hosts/${HOSTNAME}/disko-config.nix has the correct disk device (use /dev/disk/by-id/ID)${NC}"
echo ""

# Confirm
read -p "Continue with installation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
	echo "Aborted."
	exit 1
fi

# Run nixos-anywhere
echo ""
echo -e "${GREEN}Running nixos-anywhere...${NC}"

ROOTPASS=""
AUTH_OPT=""
if $SSH_PASS_ENV_OPT; then
	echo "Please enter your root password."
	read -s -p "Password: " ROOTPASS
	SSHPASS="$ROOTPASS"
	AUTH_OPT="--env-password"
fi

NIXOS_ANYWHERE="nix run github:nix-community/nixos-anywhere --
    --flake ".#provisioning-${HOSTNAME}"
    --target-host "${USER}@${TARGET_IP}"
    --build-on remote
    --generate-hardware-config nixos-generate-config ./hosts/${HOSTNAME}/hardware-configuration.nix
    $AUTH_OPT"
echo -e "${YELLOW}Running '$NIXOS_ANYWHERE'...${NC}"
$NIXOS_ANYWHERE

if [ $? -eq 0 ]; then
	echo ""
	echo -e "${GREEN}✓ Installation complete!${NC}"
	echo ""
	echo "Next steps:"
	echo "1. System will reboot automatically"
	echo "2. Remove old SSH key: ssh-keygen -R ${TARGET_IP}"
	echo "3. Connect as user: ssh bdhill@${TARGET_IP}"
	echo "4. Deploy full config: make apply-${HOSTNAME}"
else
	echo -e "${RED}Installation failed!${NC}"
	exit 1
fi
