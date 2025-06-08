# Provisioning a New NixOS Host using nixos-anywhere

The provisioning module is used for provisioning a new NixOS host using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere/blob/main/docs/quickstart.md).

## Prerequisites

### On Your Local Machine
- A flake that controls the actions to be performed
- A disk configuration containing details of the file system that will be created on the new server.
- A target machine that is reachable via SSH, either using keys or a password, and the privilege to either log in directly as root or a user with password-less sudo.

### On the Target Machine
- NixOS installer ISO (download from nixos.org)
- All disks connected and recognized
- Network connection (wifi not supported)

## Step 1: Prepare Target Machine

1. **Boot from NixOS installer ISO**

2. **Enable SSH access**
   ```bash
   # Set root password (temporary, just for installation)
   sudo passwd

   # Start SSH service (usually already running)
   sudo systemctl start sshd

   # Note your IP address
   ip addr show
   ```
