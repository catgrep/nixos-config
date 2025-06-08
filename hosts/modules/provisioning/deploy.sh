#!/usr/bin/env bash
set -euo pipefail

# Configuration
TARGET_HOST="your-target-host" # Change this to your target hostname or IP
TARGET_USER="root"
FLAKE_PATH="."  # Path to your flake directory

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}NixOS Deployment with ZFS and Disko${NC}"
echo "======================================"

# Check if running as root (needed for nixos-anywhere)
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root for nixos-anywhere${NC}"
   exit 1
fi

# Verify target is reachable
echo -e "${YELLOW}Checking connectivity to ${TARGET_HOST}...${NC}"
if ! ssh "${TARGET_USER}@${TARGET_HOST}" "echo 'Connection successful'"; then
    echo -e "${RED}Failed to connect to ${TARGET_HOST}${NC}"
    exit 1
fi

# Create a minimal flake.nix if it doesn't exist
if [ ! -f "flake.nix" ]; then
    echo -e "${YELLOW}Creating flake.nix...${NC}"
    cat > flake.nix << 'EOF'
{
  description = "NixOS configuration with ZFS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, disko, impermanence, ... }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        ./configuration.nix
      ];
    };
  };
}
EOF
fi

# Deploy with nixos-anywhere
echo -e "${GREEN}Starting deployment with nixos-anywhere...${NC}"
echo -e "${YELLOW}This will:${NC}"
echo "  1. Partition and format all disks according to disko-config.nix"
echo "  2. Create ZFS pools (rpool with 'Erase Your Darlings', backup with RAID-Z2)"
echo "  3. Setup ext4 filesystems for MergerFS"
echo "  4. Install NixOS"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

# Run nixos-anywhere
nix run github:numtide/nixos-anywhere -- \
  --flake "${FLAKE_PATH}#your-hostname" \
  --extra-experimental-features "nix-command flakes" \
  "${TARGET_USER}@${TARGET_HOST}"

echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Post-deployment steps:"
echo "1. The system will reboot into the new NixOS installation"
echo "2. SSH host keys will be automatically generated in /persist/etc/ssh/"
echo "3. On first boot, the root filesystem will be at the blank snapshot"
echo "4. MergerFS will automatically mount /mnt/media from both 12TB drives"
echo "5. The backup pool is available at /mnt/backups with RAID-Z2 redundancy"
echo ""
echo "To persist changes across reboots, ensure important data is in:"
echo "  - /home (preserved)"
echo "  - /persist (preserved)"
echo "  - /nix (preserved)"
echo ""
echo "Everything else in / will be reset on reboot!"
