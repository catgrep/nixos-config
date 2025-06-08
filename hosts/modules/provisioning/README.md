# NixOS Homelab Provisioning Guide

This guide explains how to provision new NixOS hosts in your homelab using `nixos-anywhere`.

## Overview

The provisioning system uses:
- **nixos-anywhere**: Automated NixOS installation over SSH
- **disko**: Declarative disk partitioning
- **Host-specific configs**: Each host has its own `disko-config.nix`

## Prerequisites

1. **Target machine booted from NixOS installer**
   - Download ISO from nixos.org
   - Create bootable USB with `dd` or Etcher
   - Boot target machine from USB

2. **Network connectivity**
   - Ethernet connection (WiFi not supported in installer)
   - Note the IP address: `ip addr show`

3. **SSH access**
   - Set root password on target: `sudo passwd`
   - Test connection: `ssh root@<ip-address>`

## Directory Structure

```
hosts/
├── beelink/
│   ├── configuration.nix      # Full NixOS configuration
│   ├── disko-config.nix       # Disk partitioning config
│   └── hardware-configuration.nix  # Generated hardware config
├── firebat/
│   ├── configuration.nix
│   └── disko-config.nix
└── pi4/
    ├── configuration.nix
    └── disko-config.nix
```

## Step-by-Step Provisioning

### 1. Boot Target from NixOS Installer

Boot your target machine from the NixOS installer USB/ISO.

### 2. Enable SSH Access

On the target machine:
```bash
# Set a temporary root password
sudo passwd

# Get IP address
ip addr show
# Look for inet address on your ethernet interface (e.g., enp1s0, eth0)
```

### 3. Prepare Disk Configuration

Before running the provisioning, you need to identify the correct disk device.

From your deployment machine, check the target's disks:
```bash
ssh root@<target-ip> "lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL"
ssh root@<target-ip> "ls -la /dev/disk/by-id/"
```

Update `hosts/<hostname>/disko-config.nix` with the correct disk device. You can use:
- Direct device: `/dev/sda`, `/dev/nvme0n1`
- By-id (recommended): `/dev/disk/by-id/ata-Samsung_SSD_850_EVO_500GB_S1234567890`

### 4. Run the Provisioning

Use the deployment script:
```bash
# Basic provisioning
./scripts/deploy-nixos-anywhere.sh <hostname> <target-ip>

# With hardware config generation (recommended for new installs)
./scripts/deploy-nixos-anywhere.sh <hostname> <target-ip> --generate-hardware

# Examples:
./scripts/deploy-nixos-anywhere.sh beelink 192.168.1.20 --generate-hardware
./scripts/deploy-nixos-anywhere.sh firebat 192.168.1.21
./scripts/deploy-nixos-anywhere.sh pi4 192.168.1.10
```

### 5. Post-Installation

After successful provisioning:

1. **Remove old SSH key** (if reusing IP):
   ```bash
   ssh-keygen -R <ip-address>
   ```

2. **Connect as normal user**:
   ```bash
   ssh bdhill@<ip-address>
   ```

3. **Deploy full configuration with Colmena**:
   ```bash
   make apply-<hostname>
   # or
   colmena apply --on <hostname>
   ```

## Creating Disk Configurations

### Basic Single Disk (ext4)

```nix
# hosts/<hostname>/disko-config.nix
{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";  # Update this!
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
```

### ZFS Configuration

See `hosts/beelink/disko-config.nix` for a complex ZFS example with:
- Root pool with "Erase Your Darlings" snapshot
- RAID-Z2 backup pool
- Separate media drives with MergerFS

### Raspberry Pi SD Card

See `hosts/pi4/disko-config.nix` for Pi-specific configuration with:
- Firmware partition for Pi bootloader
- Optimizations for SD card longevity

## Finding Disk Identifiers

### By device name (less reliable):
```bash
lsblk -d -o NAME,SIZE,MODEL
# Shows: sda, nvme0n1, mmcblk0, etc.
```

### By ID (recommended - survives reboots):
```bash
ls -la /dev/disk/by-id/
# Shows stable identifiers like:
# ata-Samsung_SSD_850_EVO_500GB_S21PNSAG123456
# nvme-Samsung_SSD_970_EVO_Plus_1TB_S4EWNX0M123456
# mmc-SD32G_0x12345678
```

### By UUID (for existing filesystems):
```bash
blkid
# Shows filesystem UUIDs
```

## Troubleshooting

### "No such file or directory" for disk device
- The device path in disko-config.nix doesn't match actual hardware
- Run `lsblk` on target to find correct device name
- Use `/dev/disk/by-id/` paths for stability

### SSH connection refused
- Ensure you set root password: `sudo passwd`
- Check firewall isn't blocking SSH
- Verify IP address is correct

### Deployment fails with disk errors
- Existing partitions may need to be wiped
- Boot into installer and run: `wipefs -a /dev/sdX`
- Or use `dd if=/dev/zero of=/dev/sdX bs=1M count=100`

### Hardware configuration issues
- Use `--generate-hardware` flag on first install
- This creates proper hardware-configuration.nix
- Ensures all needed kernel modules are loaded

## Advanced Usage

### Custom disk layouts
- See [disko examples](https://github.com/nix-community/disko/tree/master/example)
- Supports: LUKS encryption, RAID, LVM, bcache, and more

### Repair without wiping
```bash
# Mount existing filesystems and repair
nix run github:nix-community/nixos-anywhere -- \
  --disko-mode mount \
  --flake .#provisioning-<hostname> \
  --target-host root@<ip>
```

### Debug mode
```bash
./scripts/deploy-nixos-anywhere.sh <hostname> <ip> --debug --dry-run
```

## Important Notes

1. **Disk wiping**: nixos-anywhere will WIPE all configured disks
2. **Network boot**: Installer must have ethernet (no WiFi)
3. **SSH keys**: Your key from configuration.nix will be installed
4. **Persistence**: For "Erase Your Darlings" setups, data outside /persist is ephemeral
