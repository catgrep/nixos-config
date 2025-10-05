# Nix Overlays Pattern - Analysis & Recommendations

## What Are Overlays?

Overlays are a Nix pattern for modifying or extending the package set (nixpkgs) by:
- Customizing existing packages
- Adding new packages
- Overriding package versions
- Applying patches
- Changing build flags

## Current State in Repository

### Overlay Usage: None Found

Searching the repository:
```bash
grep -r "overlay" .
# No overlay definitions found
```

**Current approach:** Using standard nixpkgs packages without customization.

## When to Use Overlays

### Good Use Cases for This Repo

1. **Custom Package Versions**
   - Media services might need newer/older versions
   - Example: Specific Jellyfin version for stability

2. **Package Patches**
   - Apply fixes not yet in nixpkgs
   - Custom configurations for hardware

3. **Build Optimizations**
   - Enable specific features
   - Compiler optimizations for media encoding

4. **Unified Package Customization**
   - One overlay applies across all hosts
   - Consistent versions homelab-wide

### When NOT to Use Overlays

❌ **For simple configuration** - Use module options instead
❌ **For system services** - Use NixOS modules
❌ **For one-off packages** - Use `pkgs.somePackage.override { }`

## Potential Applications in This Homelab

### 1. Media Service Versions

**Problem:** Nixpkgs versions might lag behind media service releases

**Current:**
```nix
# modules/media/jellyfin.nix
services.jellyfin.enable = true;
# Uses whatever version is in nixpkgs
```

**With Overlay:**
```nix
# overlays/media-services.nix
final: prev: {
  jellyfin = prev.jellyfin.overrideAttrs (old: rec {
    version = "10.9.0";  # Pin specific version
    src = prev.fetchurl {
      url = "https://github.com/jellyfin/jellyfin/archive/v${version}.tar.gz";
      # ... hash
    };
  });

  # Or use newer version from unstable
  jellyfin = prev.unstable.jellyfin;
}
```

**Usage:**
```nix
# flake.nix
{
  nixosConfigurations.ser8 = nixpkgs.lib.nixosSystem {
    modules = [
      ./hosts/ser8/configuration.nix
      {
        nixpkgs.overlays = [ (import ./overlays/media-services.nix) ];
      }
    ];
  };
}
```

### 2. Hardware Optimizations

**Problem:** Default builds might not optimize for Intel QuickSync or specific CPU features

**With Overlay:**
```nix
# overlays/hardware-optimizations.nix
final: prev: {
  # Optimize ffmpeg for Intel QuickSync
  ffmpeg-full = prev.ffmpeg-full.override {
    withVaapi = true;  # VA-API for Intel
    withIntel = true;   # Intel Media SDK
  };

  # CPU-optimized builds for x86_64
  jellyfin = prev.jellyfin.override {
    ffmpeg = final.ffmpeg-full;
  };
}
```

### 3. Custom AllDebrid Package

**Current Problem:** AllDebrid is a local path in flake
```nix
# flake.nix
inputs.alldebrid-rs = {
  url = "/Users/bobby/github/catgrep/alldebrid-rs";
  # This won't work for others!
};
```

**With Overlay:**
```nix
# overlays/custom-packages.nix
final: prev: {
  alldebrid-proxy = prev.rustPlatform.buildRustPackage {
    pname = "alldebrid-proxy";
    version = "0.1.0";
    src = prev.fetchFromGitHub {
      owner = "catgrep";
      repo = "alldebrid-rs";
      rev = "main";
      hash = "...";
    };
    cargoHash = "...";
  };
}
```

### 4. Consistent Package Versions Across Hosts

**Problem:** Different hosts might use different package versions

**With Overlay:**
```nix
# overlays/homelab-versions.nix
final: prev: {
  # Pin versions for consistency
  prometheus = prev.prometheus.overrideAttrs (old: {
    version = "2.50.0";  # Specific version
  });

  grafana = prev.grafana.overrideAttrs (old: {
    version = "10.3.0";
  });

  # Or use unstable for latest
  caddy = prev.unstable.caddy;
}
```

## Recommended Overlay Structure

```
overlays/
├── default.nix              # Exports all overlays
├── hardware-optimizations.nix  # Intel QuickSync, etc.
├── media-services.nix       # Jellyfin, ffmpeg, etc.
├── custom-packages.nix      # AllDebrid, etc.
└── version-pins.nix         # Pin versions across hosts
```

### Example: `overlays/default.nix`

```nix
{
  # Import all overlays
  hardware-optimizations = import ./hardware-optimizations.nix;
  media-services = import ./media-services.nix;
  custom-packages = import ./custom-packages.nix;
  version-pins = import ./version-pins.nix;

  # Or as a single overlay that combines all
  homelab = final: prev:
    (import ./hardware-optimizations.nix final prev)
    // (import ./media-services.nix final prev)
    // (import ./custom-packages.nix final prev)
    // (import ./version-pins.nix final prev);
}
```

### Integration with Flake

```nix
# flake.nix
{
  description = "NixOS homelab configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # ... other inputs
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }@inputs:
    let
      # Define overlays
      overlays = [
        # Add unstable channel
        (final: prev: {
          unstable = import nixpkgs-unstable {
            system = prev.system;
            config.allowUnfree = true;
          };
        })

        # Import homelab overlays
        (import ./overlays).homelab
      ];
    in
    {
      nixosConfigurations = {
        ser8 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/ser8/configuration.nix
            { nixpkgs.overlays = overlays; }
          ];
        };

        firebat = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/firebat/configuration.nix
            { nixpkgs.overlays = overlays; }
          ];
        };

        # ... other hosts
      };
    };
}
```

## Specific Recommendations for This Repo

### Immediate: Fix AllDebrid Input

**Priority:** High
**Complexity:** Low

Replace local path with proper Git URL:

```nix
# flake.nix
inputs.alldebrid-rs = {
  url = "github:catgrep/alldebrid-rs";  # Or your fork
  flake = false;  # If it's not a flake
};
```

Or use an overlay instead:

```nix
# overlays/custom-packages.nix
final: prev: {
  alldebrid-proxy = final.rustPlatform.buildRustPackage {
    pname = "alldebrid-proxy";
    version = "0.1.0";

    src = final.fetchFromGitHub {
      owner = "catgrep";
      repo = "alldebrid-rs";
      rev = "v0.1.0";  # Or commit hash
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    cargoLock = {
      lockFile = "${src}/Cargo.lock";
    };
  };
}
```

### Short-term: Hardware Optimizations

**Priority:** Medium
**Benefit:** Better Jellyfin transcoding performance

```nix
# overlays/hardware-optimizations.nix
final: prev: {
  # Optimize ffmpeg for Intel QuickSync (ser8)
  ffmpeg-full = prev.ffmpeg-full.override {
    withVaapi = true;
    withVdpau = true;
    withIntel = true;
    # Enable all hardware acceleration
  };

  # Ensure Jellyfin uses optimized ffmpeg
  jellyfin = prev.jellyfin.override {
    ffmpeg = final.ffmpeg-full;
  };

  # Jellyfin-web with specific version (if needed)
  jellyfin-web = prev.jellyfin-web.overrideAttrs (old: {
    # Custom version or patches if needed
  });
}
```

### Long-term: Version Management

**Priority:** Low
**Benefit:** Consistency and stability

```nix
# overlays/version-pins.nix
# Pin critical service versions for stability
final: prev: {
  # Media stack - pin to known working versions
  sonarr = prev.sonarr.overrideAttrs (old: {
    version = "4.0.0.746";  # Specific stable version
  });

  radarr = prev.radarr.overrideAttrs (old: {
    version = "5.2.6.8376";
  });

  # Monitoring stack - use unstable for latest features
  prometheus = final.unstable.prometheus;
  grafana = final.unstable.grafana;

  # Gateway - stable
  caddy = prev.caddy;  # Use stable version
}
```

## Alternative: Per-Host Overlays

If some optimizations only apply to specific hosts:

```nix
# hosts/ser8/configuration.nix
{
  nixpkgs.overlays = [
    # Global overlays
    (import ../../overlays).homelab

    # ser8-specific overlay
    (final: prev: {
      # Intel-specific optimizations only for ser8
      jellyfin = prev.jellyfin.override {
        ffmpeg = final.ffmpeg-full;
      };
    })
  ];
}
```

## Comparison: Overlays vs Alternatives

### Overlays vs Package Overrides

**Override (inline):**
```nix
# Good for one-off changes
environment.systemPackages = [
  (pkgs.jellyfin.override {
    ffmpeg = pkgs.ffmpeg-full;
  })
];
```

**Overlay (reusable):**
```nix
# Good for multiple uses
nixpkgs.overlays = [
  (final: prev: {
    jellyfin = prev.jellyfin.override {
      ffmpeg = final.ffmpeg-full;
    };
  })
];
```

### Overlays vs NixOS Modules

**Module:**
```nix
# For service configuration
services.jellyfin = {
  enable = true;
  openFirewall = true;
  # ... service options
};
```

**Overlay:**
```nix
# For package customization
nixpkgs.overlays = [
  (final: prev: {
    jellyfin = prev.jellyfin.override {
      # ... package build options
    };
  })
];
```

**Use both together:**
```nix
# Overlay customizes package
nixpkgs.overlays = [ (import ./overlays).homelab ];

# Module configures service using customized package
services.jellyfin.enable = true;
```

## Implementation Plan

### Phase 1: Create Overlay Infrastructure (1-2 hours)

1. Create `overlays/` directory
2. Create `overlays/default.nix`
3. Create empty overlay files
4. Update `flake.nix` to use overlays

### Phase 2: Fix AllDebrid (30 minutes)

1. Create `overlays/custom-packages.nix`
2. Add AllDebrid package definition
3. Update module to use overlay package
4. Test build

### Phase 3: Add Hardware Optimizations (1-2 hours)

1. Create `overlays/hardware-optimizations.nix`
2. Add Intel QuickSync ffmpeg optimization
3. Test Jellyfin transcoding performance

### Phase 4: Optional Version Pins (as needed)

1. Create `overlays/version-pins.nix`
2. Pin critical service versions
3. Document version decisions

## Testing Procedure

```bash
# After creating overlays
make check

# Build specific host to test overlay
make build-ser8

# Check that overlay is applied
nix eval .#nixosConfigurations.ser8.config.nixpkgs.overlays --json

# Deploy and test
make test-ser8

# Verify package versions
make ssh-ser8
jellyfin --version
ffmpeg -version | grep "configuration:"
```

## Potential Issues and Solutions

### Issue: Overlay Order Matters

Overlays are applied in sequence. Later overlays can override earlier ones.

**Solution:** Order overlays appropriately in flake:
```nix
overlays = [
  overlay1  # Applied first
  overlay2  # Can override overlay1
  overlay3  # Can override overlay1 and overlay2
];
```

### Issue: Rebuild Times

Custom overlays require rebuilding packages from source if not in cache.

**Solution:**
- Use cachix for custom builds
- Or use `override` instead of `overrideAttrs` when possible

### Issue: Maintenance Burden

Custom overlays need updates when nixpkgs changes.

**Solution:**
- Only customize what's necessary
- Document why each overlay exists
- Regular testing with nixpkgs updates

## Summary

**Current State:** No overlays used
**Recommendation:** Start small with specific use cases
**Priority:**
1. High: Fix AllDebrid local path issue
2. Medium: Add hardware optimizations for Jellyfin
3. Low: Add version pins for consistency

**Files to Create:**
```
overlays/
├── default.nix
├── custom-packages.nix    (AllDebrid)
└── hardware-optimizations.nix  (Intel QuickSync)
```

**Benefits:**
- ✅ Better performance (hardware acceleration)
- ✅ Consistent versions across homelab
- ✅ Easier to share configuration (no local paths)
- ✅ Centralized package customization

**Trade-offs:**
- ⚠️ More complexity
- ⚠️ Potential rebuild times
- ⚠️ Need to maintain overlays

**Recommendation:** Implement overlays gradually, starting with AllDebrid fix and hardware optimizations.
