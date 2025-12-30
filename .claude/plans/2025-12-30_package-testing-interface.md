# Implementation Plan: Package Testing Interface

**Date**: 2025-12-30
**Goal**: Add package-level build testing and inspection commands to the Makefile and nixos-rebuild.sh
**Motivation**: Enable fast iteration when debugging dependency issues (e.g., jellyfin-ffmpeg lcevc_dec breakage)

---

## Overview

This plan adds a comprehensive package testing interface that allows:
1. **Building individual packages** - Test single package builds without full system rebuild
2. **Inspecting package versions** - Debug overlay and dependency version mismatches
3. **Listing available packages** - Discover what's available per host (overlays, system, services)
4. **Evaluating config expressions** - Inspect arbitrary NixOS configuration values

**New Makefile targets**: `pkg-list-%`, `pkg-build-%`, `pkg-version-%`, `pkg-eval-%`
**New nixos-rebuild.sh actions**: `pkg-list`, `pkg-build`, `pkg-version`, `pkg-eval`

---

## Phase 1: Core Script Infrastructure

### Step 1.1: Add pkg-build Action to nixos-rebuild.sh

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add new case in main switch statement, around line 159)

**What to add:**
```bash
pkg-build)
    # Build a specific package from a host's configuration
    local pkg="${1:-}"
    if [ -z "$pkg" ]; then
        fail "Usage: $0 pkg-build <host> <package>"
        fail "Example: $0 pkg-build ser8 jellyfin-ffmpeg"
        exit 1
    fi
    info "Building package '$pkg' for host '$host'..."
    nix build ".#nixosConfigurations.${host}.pkgs.${pkg}" -v --no-link --print-out-paths
    pass "Package '$pkg' built successfully"
    ;;
```

**Why:**
This is the core debugging command - allows building a single package to isolate build failures without waiting for the full system derivation.

**Dependencies:** None

---

### Step 1.2: Add pkg-version Action to nixos-rebuild.sh

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add after pkg-build case)

**What to add:**
```bash
pkg-version)
    # Show version of a package in host's pkgs
    local pkg="${1:-}"
    if [ -z "$pkg" ]; then
        fail "Usage: $0 pkg-version <host> <package>"
        fail "Example: $0 pkg-version ser8 lcevcdec"
        exit 1
    fi
    local version
    version=$(nix eval --raw ".#nixosConfigurations.${host}.pkgs.${pkg}.version" 2>/dev/null) || {
        fail "Package '$pkg' not found or has no version attribute"
        exit 1
    }
    info "Package '$pkg' version for host '$host': $(fmt_bold "$version")"
    ;;
```

**Why:**
Essential for debugging version mismatches like lcevcdec 3.3.5 vs 4.0.0 - allows quick version checks without building.

**Dependencies:** Step 1.1 (for consistent error handling pattern)

---

### Step 1.3: Add pkg-eval Action to nixos-rebuild.sh

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add after pkg-version case)

**What to add:**
```bash
pkg-eval)
    # Evaluate arbitrary expression against host config
    local expr="${1:-}"
    if [ -z "$expr" ]; then
        fail "Usage: $0 pkg-eval <host> <expression>"
        fail "Examples:"
        fail "  $0 pkg-eval ser8 'config.services.jellyfin.enable'"
        fail "  $0 pkg-eval ser8 'pkgs.jellyfin.version'"
        exit 1
    fi
    info "Evaluating '.#nixosConfigurations.${host}.${expr}':"
    nix eval ".#nixosConfigurations.${host}.${expr}"
    ;;
```

**Why:**
Flexible inspection of any config value - useful for debugging service options, checking if modules are enabled, etc.

**Dependencies:** None

---

## Phase 2: Flake Infrastructure for Service Discovery

### Step 2.0: Add servicePackages Output to flake.nix

**Files to modify:**
- `flake.nix` (add new output after `devShells` section, around line 266)

**What to add:**
```nix
# Service discovery - maps enabled services to their packages per host
# Query with: nix eval '.#enabledServices.ser8' --json
# Query with: nix eval '.#servicePackages.ser8' --json
enabledServices = builtins.mapAttrs (hostname: cfg:
  builtins.filter (name:
    let svc = cfg.config.services.${name};
    in (svc ? enable) && svc.enable
  ) (builtins.attrNames cfg.config.services)
) self.nixosConfigurations;

servicePackages = builtins.mapAttrs (hostname: cfg:
  let
    enabledSvcs = builtins.filter (name:
      let svc = cfg.config.services.${name};
      in (svc ? enable) && svc.enable
    ) (builtins.attrNames cfg.config.services);

    # Get package for each service (if it has one)
    getPackage = name:
      let svc = cfg.config.services.${name};
      in if svc ? package
         then svc.package.pname or svc.package.name or null
         else null;
  in
    builtins.listToAttrs (
      builtins.filter (x: x.value != null) (
        map (name: { inherit name; value = getPackage name; }) enabledSvcs
      )
    )
) self.nixosConfigurations;
```

**Why:**
- `enabledServices` - Lists all services with `enable = true` per host
- `servicePackages` - Maps service name → package name for enabled services
- Computed in Nix (single source of truth), queried from bash
- No hardcoded mappings in scripts

**Usage:**
```bash
# List all enabled services for ser8
nix eval '.#enabledServices.ser8' --json
# ["jellyfin","openssh","radarr","sabnzbd","sonarr",...]

# Get service → package mapping
nix eval '.#servicePackages.ser8' --json
# {"jellyfin":"jellyfin","radarr":"radarr","sonarr":"sonarr",...}
```

**Dependencies:** None

---

## Phase 3: Package Listing Infrastructure

### Step 3.1: Add pkg-list Action Framework to nixos-rebuild.sh

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add after pkg-eval case)

**What to add:**
```bash
pkg-list)
    # List available packages for a host
    local category="${1:-all}"

    title "Package listing for host '$host' (category: $category)"

    case "$category" in
        overlays|all)
            pkg_list_overlays "$host"
            ;;&
        system|all)
            pkg_list_system "$host"
            ;;&
        services|all)
            pkg_list_services "$host"
            ;;
        *)
            fail "Unknown category '$category'"
            fail "Valid categories: overlays, system, services, all"
            exit 1
            ;;
    esac
    ;;
```

**Why:**
Framework for the comprehensive listing feature. Uses bash `;;&` for fall-through to support `all` category showing everything.

**Dependencies:** Steps 3.2, 3.3, 3.4 (helper functions)

---

### Step 3.2: Add pkg_list_overlays Helper Function

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add as new function before main())

**What to add:**
```bash
pkg_list_overlays() {
    local host="$1"
    echo ""
    info "$(fmt_bold "Overlay packages") (custom/overridden):"

    # Extract package names from overlays
    local overlay_pkgs
    overlay_pkgs=$(nix eval ".#nixosConfigurations.${host}.config.nixpkgs.overlays" \
        --apply 'ovs: builtins.concatMap (ov: builtins.attrNames (ov (import <nixpkgs> {}) (import <nixpkgs> {}))) ovs' \
        --json 2>/dev/null | jq -r '.[]' | sort -u) || {
        echo "  (none or unable to evaluate)"
        return 0
    }

    if [ -z "$overlay_pkgs" ]; then
        echo "  (none)"
    else
        echo "$overlay_pkgs" | while read -r pkg; do
            local version
            version=$(nix eval --raw ".#nixosConfigurations.${host}.pkgs.${pkg}.version" 2>/dev/null) || version="?"
            printf "  %-30s %s\n" "$pkg" "($version)"
        done
    fi
}
```

**Why:**
Shows packages that are overridden via overlays - these are the most likely candidates for build issues and version mismatches.

**Dependencies:** None (uses nix eval directly)

---

### Step 3.3: Add pkg_list_system Helper Function

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add after pkg_list_overlays)

**What to add:**
```bash
pkg_list_system() {
    local host="$1"
    echo ""
    info "$(fmt_bold "System packages") (environment.systemPackages):"

    local sys_pkgs
    sys_pkgs=$(nix eval ".#nixosConfigurations.${host}.config.environment.systemPackages" \
        --apply 'pkgs: map (p: p.pname or p.name or "unknown") pkgs' \
        --json 2>/dev/null | jq -r '.[]' | sort -u | head -30) || {
        echo "  (unable to evaluate)"
        return 0
    }

    local count
    count=$(echo "$sys_pkgs" | wc -l | tr -d ' ')
    echo "  (showing first 30 of $count packages)"
    echo "$sys_pkgs" | while read -r pkg; do
        echo "  $pkg"
    done
}
```

**Why:**
Shows explicitly installed system packages. Limited to 30 to avoid overwhelming output.

**Dependencies:** None

---

### Step 3.4: Add pkg_list_services Helper Function

**Files to modify:**
- `scripts/nixos-rebuild.sh` (add after pkg_list_system)

**What to add:**
```bash
pkg_list_services() {
    local host="$1"
    echo ""
    info "$(fmt_bold "Service packages") (enabled services with packages):"

    # Query the flake's servicePackages output (computed in Nix)
    local svc_pkgs
    svc_pkgs=$(nix eval ".#servicePackages.${host}" --json 2>/dev/null) || {
        echo "  (unable to evaluate servicePackages)"
        return 0
    }

    if [ "$svc_pkgs" = "{}" ]; then
        echo "  (no services with packages found)"
        return 0
    fi

    # Parse JSON and display service → package with versions
    echo "$svc_pkgs" | jq -r 'to_entries | .[] | "\(.key) \(.value)"' | while read -r svc pkg; do
        local version
        version=$(nix eval --raw ".#nixosConfigurations.${host}.pkgs.${pkg}.version" 2>/dev/null) || version="?"
        printf "  %-25s → %-20s (%s)\n" "$svc" "$pkg" "$version"
    done
}
```

**Why:**
- Uses the `servicePackages` flake output (Step 2.0) instead of hardcoded mappings
- Single source of truth - service discovery computed in Nix
- Automatically updates when services are enabled/disabled
- Shows service name → package name → version

**Example output:**
```
[info] Service packages (enabled services with packages):
  jellyfin                  → jellyfin             (10.11.5)
  radarr                    → radarr               (5.x.x)
  sonarr                    → sonarr               (4.x.x)
  sabnzbd                   → sabnzbd              (4.x.x)
```

**Dependencies:** Step 2.0 (flake.nix `servicePackages` output)

---

### Step 3.5: Update usage() Function

**Files to modify:**
- `scripts/nixos-rebuild.sh` (update usage function around line 13)

**What to add to usage():**
```bash
title "Package Operations:"
echo "  pkg-list       List available packages (categories: overlays, system, services, all)"
echo "  pkg-build      Build a specific package"
echo "  pkg-version    Show package version"
echo "  pkg-eval       Evaluate config expression"
echo ""
title "Package Examples:"
echo "  $0 pkg-list ser8                        # List all package categories"
echo "  $0 pkg-list ser8 overlays               # List only overlay packages"
echo "  $0 pkg-build ser8 jellyfin-ffmpeg       # Build single package"
echo "  $0 pkg-version ser8 lcevcdec            # Check package version"
echo "  $0 pkg-eval ser8 'config.services.jellyfin.enable'"
echo ""
```

**Why:**
Documents new functionality with concrete examples.

**Dependencies:** Steps 1.1-2.4 (all actions implemented)

---

## Phase 4: Makefile Integration

### Step 4.1: Add Package Operation Targets to Makefile

**Files to modify:**
- `Makefile` (add after deployment targets section, before SOPS section)

**What to add:**
```makefile
# =============================================================================
# Package Operations
# =============================================================================

pkg-list-%:
	@./scripts/nixos-rebuild.sh pkg-list $* $(CATEGORY)

pkg-build-%:
	@if [ -z "$(PKG)" ]; then \
		$(call error_msg,"Usage: make pkg-build-$* PKG=<package>"); \
		$(call info_msg,"Example: make pkg-build-$* PKG=jellyfin-ffmpeg"); \
		exit 1; \
	fi
	@./scripts/nixos-rebuild.sh pkg-build $* $(PKG)

pkg-version-%:
	@if [ -z "$(PKG)" ]; then \
		$(call error_msg,"Usage: make pkg-version-$* PKG=<package>"); \
		$(call info_msg,"Example: make pkg-version-$* PKG=lcevcdec"); \
		exit 1; \
	fi
	@./scripts/nixos-rebuild.sh pkg-version $* $(PKG)

pkg-eval-%:
	@if [ -z "$(EXPR)" ]; then \
		$(call error_msg,"Usage: make pkg-eval-$* EXPR='<expression>'"); \
		$(call info_msg,"Example: make pkg-eval-$* EXPR='config.services.jellyfin.enable'"); \
		exit 1; \
	fi
	@./scripts/nixos-rebuild.sh pkg-eval $* "$(EXPR)"
```

**Why:**
Provides the standard `make` interface consistent with existing host-based targets.

**Dependencies:** Phase 1 and 2 (script actions)

---

### Step 4.2: Add Help Documentation for Package Operations

**Files to modify:**
- `Makefile` (add to help target, after deployment section)

**What to add:**
```makefile
@echo
@$(call title_msg,"📦 Package Operations")
$(call help_option,"pkg-list-HOST [CATEGORY=x]","List packages (overlays/system/services/all)")
$(call help_option,"pkg-build-HOST PKG=x","Build single package for HOST")
$(call help_option,"pkg-version-HOST PKG=x","Show package version for HOST")
$(call help_option,"pkg-eval-HOST EXPR=x","Evaluate expression against HOST config")
@echo
@echo "  Examples:"
@echo "    make pkg-list-ser8                        # List all packages"
@echo "    make pkg-list-ser8 CATEGORY=overlays      # List only overlay packages"
@echo "    make pkg-build-ser8 PKG=jellyfin-ffmpeg   # Build single package"
@echo "    make pkg-version-ser8 PKG=lcevcdec        # Check version (debug overlays)"
@echo "    make pkg-eval-ser8 EXPR='config.services.jellyfin.enable'"
@echo
```

**Why:**
Documents the new targets with practical examples directly in `make help` output.

**Dependencies:** Step 3.1

---

## Phase 5: Testing & Validation

### Step 5.0: Test Flake Outputs

**Commands to run:**
```bash
# Test enabledServices output
nix eval '.#enabledServices.ser8' --json 2>/dev/null | jq

# Test servicePackages output
nix eval '.#servicePackages.ser8' --json 2>/dev/null | jq

# Test for other hosts
nix eval '.#enabledServices.firebat' --json 2>/dev/null | jq
nix eval '.#servicePackages.pi4' --json 2>/dev/null | jq
```

**Expected output:**
```json
// enabledServices.ser8
["adguardhome","declarative-jellyfin","home-manager","jellyfin","openssh",...]

// servicePackages.ser8
{"jellyfin":"jellyfin","radarr":"radarr","sonarr":"sonarr",...}
```

---

### Step 5.1: Test pkg-list Functionality

**Commands to run:**
```bash
# Test listing all categories
./scripts/nixos-rebuild.sh pkg-list ser8

# Test individual categories
./scripts/nixos-rebuild.sh pkg-list ser8 overlays
./scripts/nixos-rebuild.sh pkg-list ser8 system
./scripts/nixos-rebuild.sh pkg-list ser8 services

# Test via Makefile
make pkg-list-ser8
make pkg-list-ser8 CATEGORY=overlays
```

**Expected output:**
- Overlay packages should show jellyfin, jellyfin-web, jellyfin-ffmpeg, lcevcdec with versions
- System packages should show first 30 installed packages
- Service packages should show media-related packages based on host tags

---

### Step 5.2: Test pkg-build Functionality

**Commands to run:**
```bash
# Test building overlay package
./scripts/nixos-rebuild.sh pkg-build ser8 lcevcdec

# Test via Makefile
make pkg-build-ser8 PKG=lcevcdec

# Test error handling
make pkg-build-ser8  # Should show usage error
```

**Expected output:**
- Successful build with store path printed
- Proper error message when PKG is missing

---

### Step 5.3: Test pkg-version Functionality

**Commands to run:**
```bash
# Test version check
./scripts/nixos-rebuild.sh pkg-version ser8 lcevcdec
./scripts/nixos-rebuild.sh pkg-version ser8 jellyfin

# Test via Makefile
make pkg-version-ser8 PKG=lcevcdec

# Test nonexistent package
./scripts/nixos-rebuild.sh pkg-version ser8 nonexistent-pkg
```

**Expected output:**
- lcevcdec should show 4.0.4 (from unstable overlay)
- Nonexistent package should show error message

---

### Step 5.4: Test pkg-eval Functionality

**Commands to run:**
```bash
# Test config evaluation
./scripts/nixos-rebuild.sh pkg-eval ser8 'config.services.jellyfin.enable'
./scripts/nixos-rebuild.sh pkg-eval ser8 'config.networking.hostName'

# Test via Makefile
make pkg-eval-ser8 EXPR='config.services.jellyfin.enable'
```

**Expected output:**
- Should return `true` for jellyfin.enable
- Should return `"ser8"` for hostName

---

## Summary

| Phase | Steps | Complexity | Description |
|-------|-------|------------|-------------|
| 1: Core Script | 3 steps | Low | `pkg-build`, `pkg-version`, `pkg-eval` actions |
| 2: Flake Infrastructure | 1 step | Low | `enabledServices` + `servicePackages` outputs |
| 3: Package Listing | 5 steps | Medium | `pkg-list` with overlays/system/services |
| 4: Makefile Integration | 2 steps | Low | `make pkg-*-HOST` targets |
| 5: Testing | 4 steps | Low | Validation commands |

**Total new lines of code:** ~180-220 lines
**Files modified:** 3 (`flake.nix`, `scripts/nixos-rebuild.sh`, `Makefile`)

**Key Benefits:**
- Fast iteration on build failures (build single package vs full system)
- Easy version debugging (overlay mismatches like lcevcdec)
- Discoverable interface (pkg-list shows what's available)
- Single source of truth - service discovery in Nix, not hardcoded in bash
- Consistent with existing patterns (same host-based targeting)

**New Flake Outputs:**
```bash
# List enabled services
nix eval '.#enabledServices.ser8' --json

# Get service → package mapping
nix eval '.#servicePackages.ser8' --json
```
