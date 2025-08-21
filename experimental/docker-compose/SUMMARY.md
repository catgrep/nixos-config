# Docker Remote Builders for Nix - Implementation Summary

## Original Problem

The repository had a Docker-based cross-compilation system using external scripts:
- `scripts/provision/linux-aarch64-docker-build.sh` - Wrapper script for Docker builds
- `scripts/provision/linux-aarch64-nix-build.sh` - Actual Nix build inside container
- Makefile targets that called these scripts for Pi installer images
- Dependency on Determinate Systems' Native Linux Builder (not generally available)

The goal was to replace this with a proper Nix-integrated solution while maintaining the Docker caching benefits.

## Final Solution: NixOS Configuration-Based Docker Builders

**Goal**: Replace Docker scripts with Docker containers as Nix remote builders using declarative NixOS configuration

**Key Principles**:
- **Declarative**: All container configuration via NixOS modules
- **Consistent**: Same user model (`bdhill`) across physical and Docker hosts
- **Simple workflow**: `make pi5-installer` just works
- **Maintainable**: Standard NixOS patterns instead of imperative bash scripts

## Implementation Architecture

### 1. NixOS Container Configuration (`hosts/docker/configuration.nix`)

**Declarative approach** replacing complex bash scripts:
- Uses existing `users/bdhill.nix` for consistent SSH key management
- Imports `modules/common/users.nix` for proper user configuration  
- Configures SSH service with proper settings
- No manual user creation or file manipulation needed

```nix
{ config, pkgs, lib, ... }:
let
  bdhillUser = import ../../users/bdhill.nix { inherit config lib pkgs; };
in
{
  imports = [ ../../modules/common/users.nix ];
  
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };
  
  # User automatically configured via imports
  boot.isContainer = true;
  system.stateVersion = "24.05";
}
```

### 2. Docker Compose Configuration

**Simplified approach** using `nixos-rebuild`:
- Mounts NixOS configuration and user directory only
- Uses built-in nixpkgs (no channels needed)
- Direct `nixos-rebuild switch` for container initialization
- No complex bash scripts or manual service management

```yaml
x-nix-common: &nix-common
  image: nixos/nix:2.30.1
  volumes:
    - nix-store-cache:/nix
    - ./hosts/docker/configuration.nix:/tmp/docker/configuration.nix:ro
    - ./users:/tmp/users:ro
  environment:
    NIX_PATH: |
      nixpkgs=/nix/var/nix/profiles/default/share/nix/nixpkgs:nixos-config=/tmp/docker/configuration.nix
  command:
    - nix-shell
    - -p nixos-rebuild
    - --run
    - |
      nixos-rebuild switch --no-flake
      exec sleep infinity
```

### 3. Consistent User Model

**Unified SSH access** across all hosts:
- Physical hosts: `ssh bdhill@ser8.local` using `/Users/bobby/.ssh/id_rsa`
- Docker hosts: `ssh bdhill@localhost:3022` using same key
- Same `bdhill` user configuration and SSH keys everywhere

### 4. Remote Builder Configuration (`etc/nix/docker-machines`)

**Docker-only builders** for forced container usage:
```
ssh://bdhill@localhost:3022 aarch64-linux /Users/bobby/.ssh/id_rsa 4 1 big-parallel
ssh://bdhill@localhost:3023 x86_64-linux /Users/bobby/.ssh/id_rsa 4 1 big-parallel
```

### 5. Simplified Makefile Integration

**Clean single-line targets** using docker-compose wrapper:
```makefile
pi5-installer:
	@./scripts/docker-compose.sh up
	@nix build .#packages.aarch64-linux.pi5-usb-installer --max-jobs 0 --builders @etc/nix/docker-machines
```

## Architecture Flow

```
1. User runs: make pi5-installer
2. ./scripts/docker-compose.sh up ensures Docker containers are running
3. docker-compose up -d starts containers and runs nixos-rebuild switch
4. NixOS configures SSH service and bdhill user (using built-in nixpkgs)
5. nix build --builders @etc/nix/docker-machines forces Docker usage
6. Nix connects to bdhill@localhost:3022 using existing SSH key
7. Build happens inside Docker container (aarch64-linux emulation)
8. Result automatically copied back via Nix remote builder mechanism
9. USB installer image available in ./result/
```

## Key Benefits vs Original Approach

### From Imperative to Declarative
- **Before**: 183+ lines of bash scripts managing users, SSH, and services
- **After**: ~30 lines of NixOS configuration with proper service management

### From Manual to Automatic
- **Before**: Manual user creation, SSH key copying, service startup
- **After**: NixOS handles all system configuration declaratively

### From Custom to Standard  
- **Before**: Custom bash scripts for container initialization
- **After**: Standard NixOS configuration patterns and `nixos-rebuild`

### From Complex to Simple
- **Before**: Channel downloads, network dependencies, version management
- **After**: Uses built-in nixpkgs from container image (no channels needed)

### From Fragile to Robust
- **Before**: Bash scripts with manual error handling and edge cases
- **After**: NixOS service management with proper dependency handling

## Current State

**Working**:
- ✅ NixOS configuration-based container initialization
- ✅ Declarative SSH and user management via existing patterns
- ✅ Consistent `bdhill` user across physical and Docker hosts
- ✅ Docker-compose integration with `nixos-rebuild`
- ✅ Clean Makefile integration (single-line targets)
- ✅ Volume caching preserved via `nix-store-cache`

**Ready for testing**:
- Pi5 USB installer builds via `make pi5-installer`
- Arbitrary aarch64-linux builds via `make build-aarch64-linux-PACKAGE`
- Manual container management via `make start-builders`, `make stop-builders`
- SSH access: `ssh -p 3022 bdhill@localhost` using existing keys

## Files Modified/Created

**Created**:
- `hosts/docker/configuration.nix` - NixOS container configuration
- `etc/nix/docker-machines` - Docker-only remote builders
- `scripts/docker-compose.sh` - Simple container lifecycle wrapper
- `SUMMARY.md` - This document

**Modified**:
- `docker-compose.yml` - NixOS configuration mounting and `nixos-rebuild`
- `Makefile` - Simplified to use docker-compose wrapper and `--builders @file`

**Deleted**:
- All complex bash scripts for container management (~183 lines)
- Manual user management and SSH configuration scripts

**Philosophy**: Use NixOS's declarative configuration system instead of imperative bash scripts. Leverage existing user patterns and SSH configuration for consistency across all hosts (physical and containerized).