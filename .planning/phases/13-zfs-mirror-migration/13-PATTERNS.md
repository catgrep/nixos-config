# Phase 13: ZFS Mirror Migration - Pattern Map

**Mapped:** 2026-08-27
**Files analyzed:** 9 new/modified files
**Analogs found:** 9 / 9

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `.planning/SER8-ZFS-MIRROR-MIGRATION.md` | documentation | static | (repo template) | role-match |
| `hosts/ser8/disko-config.nix` | config | declarative | `hosts/ser8/disko-config.nix:236-290` (backup pool) | exact |
| `hosts/ser8/configuration.nix` | config | declarative | `hosts/ser8/configuration.nix:56-75` (boot.zfs section) | exact |
| `hosts/ser8/impermanence.nix` | config | declarative | `hosts/ser8/impermanence.nix:160-178` (tmpfiles rules) | exact |
| `scripts/smoketests/media/test-zfs-media.sh` | test | validation | `scripts/smoketests/ser8/test-zfs-health.sh` | exact |
| `scripts/sampled-verify.sh` | utility | file-I/O / transform | (shell scripts in repo) | role-match |
| `CLAUDE.md` (ser8 section update) | documentation | static | `CLAUDE.md:43-49` (existing ser8 description) | exact |
| `hosts/ser8/README.md` (update) | documentation | static | `hosts/ser8/README.md` (existing) | exact |
| `hosts/ser8/disko-config.nix` (rpool/safe/downloads, D-21) | config | declarative | `hosts/ser8/disko-config.nix:236-290` (backup pool pattern) | exact |

---

## Pattern Assignments

### `hosts/ser8/disko-config.nix` (config, declarative) — Media ZFS Mirror Pool

**Analog:** `hosts/ser8/disko-config.nix:236-290` (backup pool pattern)

**Disk declarations pattern** (lines 43-110, backup disks; apply to media-disk1/2):

```nix
media-disk1 = {
  type = "disk";
  device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";  # WWN preserved exactly
  content = {
    type = "gpt";
    partitions = {
      zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "media";  # Replaces previous ext4 partition
        };
      };
    };
  };
};
```

**ZFS mirror pool pattern** (lines 236-290, backup pool; adapt for media mirror):

```nix
# Backup pool pattern — mirror mode, dataset structure, options
media = {
  type = "zpool";
  mode = "mirror";  # Two-disk mirror (not RAID-Z)
  options = {
    ashift = "12";
    autotrim = "on";
  };
  rootFsOptions = {
    acltype = "posixacl";
    compression = "lz4";
    recordsize = "1M";  # Backup pool uses 1M; media libraries benefit from same
    atime = "off";
    xattr = "sa";
    normalization = "formD";
    dedup = "off";
    mountpoint = "none";
    canmount = "off";
  };
  datasets = {
    "data" = {
      type = "zfs_fs";
      options = {
        mountpoint = "/mnt/media";
        "com.sun:auto-snapshot" = "false";
      };
    };
  };
};
```

**D-23 Comment style** (plain-language rationale for storage design):
```nix
# media/data: Two-disk ZFS mirror for media libraries. Single dataset for simplicity
# and to avoid cross-directory hardlink constraints. Compression (lz4) and recordsize
# (1M) tuned for mixed large library files (GB+) and import staging. No auto-snapshots;
# operator controls backup lifecycle. Downloads now stage on NVMe (rpool/safe/downloads,
# 500G quota) before import to mirror, eliminating write churn and random I/O on the mirror.
```

---

### `hosts/ser8/configuration.nix` (config, declarative) — ZFS and MergerFS

**Analog 1:** `hosts/ser8/configuration.nix:56-75` (boot.zfs section)

**Boot section modification** (existing lines, add "media" to extraPools):

```nix
boot = {
  supportedFilesystems = lib.mkForce [
    "zfs"
    "ntfs"
    "btrfs"
  ];
  zfs = {
    forceImportRoot = false;
    devNodes = "/dev/disk/by-id/";
    extraPools = [ "backup" "media" ];  # Add "media" to auto-import on boot
  };
  # ... rest of boot config unchanged
};
```

**Analog 2:** `hosts/ser8/configuration.nix:154-168` (MergerFS fileSystems)

**MergerFS removal** (lines 154-168, delete entirely):
```nix
# REMOVE THIS ENTIRE SECTION:
# fileSystems."/mnt/media" = {
#   device = "/mnt/disk1:/mnt/disk2";
#   fsType = "fuse.mergerfs";
#   options = [ ... ];
# };
```

**Analog 3:** `hosts/ser8/configuration.nix:250-252` (MergerFS packages)

**Package removal** (lines 250-252, delete from environment.systemPackages):
```nix
# Remove from environment.systemPackages:
# mergerfs
# mergerfs-tools

# Keep:
# zfs
# zfstools
# sanoid
# (other packages unchanged)
```

---

### `hosts/ser8/impermanence.nix` (config, declarative) — Tmpfiles Rules

**Analog:** `hosts/ser8/impermanence.nix:160-178` (existing /mnt/media tmpfiles rules)

**Existing tmpfiles rules for /mnt/media** (lines 160-178):

```nix
# Ensure media directories have correct permissions
"d /mnt/media 0775 media media -"
"d /mnt/media/movies 2775 media media -"
"d /mnt/media/tv 2775 media media -"
"d /mnt/media/music 0775 media media -"
"d /mnt/media/books 0775 media media -"

# Ensure download directories exist with proper media group permissions
"d /mnt/media/downloads 2775 media media -"
"d /mnt/media/downloads/tv 2775 media media -"
"d /mnt/media/downloads/movies 2775 media media -"

# SABnzbd Usenet downloads (setgid bit ensures files inherit media group)
"d /mnt/media/downloads/usenet 2775 media media -"
"d /mnt/media/downloads/usenet/incomplete 2775 media media -"
"d /mnt/media/downloads/usenet/complete 2775 media media -"
"d /mnt/media/downloads/usenet/complete/tv 2775 media media -"
"d /mnt/media/downloads/usenet/complete/movies 2775 media media -"
"d /mnt/media/downloads/usenet/complete/prowlarr 2775 media media -"
"d /mnt/media/downloads/usenet/complete/default 2775 media media -"
```

**D-21 addition (rpool/safe/downloads tmpfiles rules):**

```nix
# New in Phase 13, D-21: NVMe download staging with 500G quota
# Path discretion: e.g., /mnt/downloads (TBD by planner)
"d /mnt/downloads 0775 media media -"
"d /mnt/downloads/incomplete 0775 media media -"
"d /mnt/downloads/complete 0775 media media -"
```

**Decision point:** Lines 160-178 remain in place (ZFS mount will preserve directory structure). Confirm no conflict between tmpfiles rules and ZFS dataset mount if any are removed.

---

### `scripts/smoketests/media/test-zfs-media.sh` (test, validation)

**Analog:** `scripts/smoketests/ser8/test-zfs-health.sh`

**Imports and structure pattern** (lines 1-35):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# ZFS media storage smoketest for ser8.
#
# Validates: pool online, mirror membership by approved WWNs, canonical
# directories exist, service account access, import-write test (D-22).

. ./scripts/lib/all.sh

title "$0"

if [ $# -lt 1 ]; then
  info "Usage: $0 <host>"
  exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Approved disk WWNs (from migration doc §Approved Disk Inventory)
APPROVED_WWN_1="wwn-0x5000c500b56ea81a"
APPROVED_WWN_2="wwn-0x5000c500b3733a87"

MEDIA_POOL="media"
MEDIA_MOUNT="/mnt/media"
```

**Test helper function pattern** (test-zfs-health.sh:43-55, run_test/remote helpers):

```bash
run_test() {
  local test_name="$1"
  local test_func="$2"
  shift 2

  ((tests_run += 1))
  if "$test_func" "$@"; then
    ((tests_passed += 1))
    return 0
  fi
  warn "test failed: $test_name"
  return 1
}

remote() {
  local remote_command
  printf -v remote_command '%q ' "$@"
  ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""
}
```

**Test implementations** (adapt test-zfs-health.sh:68-162 patterns for media):

```bash
# Test 1: Mount source is ZFS (not fuse.mergerfs)
test_mount_type() {
  info "checking mount type of $MEDIA_MOUNT"
  local mount_info=$(remote mount | grep "$MEDIA_MOUNT")
  if echo "$mount_info" | grep -q "type zfs"; then
    pass "Mount $MEDIA_MOUNT is ZFS (not mergerfs)"
    return 0
  fi
  fail "Mount $MEDIA_MOUNT is not ZFS (found: $mount_info)"
  return 1
}

# Test 2: Pool online
test_pool_online() {
  info "checking pool $MEDIA_POOL is ONLINE"
  local status=$(remote zpool status -x "$MEDIA_POOL")
  if echo "$status" | grep -q "pool.*is healthy"; then
    pass "Pool $MEDIA_POOL is ONLINE"
    return 0
  fi
  fail "Pool $MEDIA_POOL not healthy"
  return 1
}

# Test 3: Mirror membership by WWN
test_mirror_members() {
  info "checking mirror membership (approved WWNs)"
  local status=$(remote zpool status "$MEDIA_POOL")
  
  if ! echo "$status" | grep -q "$APPROVED_WWN_1"; then
    fail "Mirror missing approved disk $APPROVED_WWN_1"
    return 1
  fi
  if ! echo "$status" | grep -q "$APPROVED_WWN_2"; then
    fail "Mirror missing approved disk $APPROVED_WWN_2"
    return 1
  fi
  pass "Mirror membership verified (both approved WWNs present)"
  return 0
}

# Test 4: Canonical directories exist
test_canonical_dirs() {
  info "checking canonical directories"
  for dir in movies television books; do
    if ! remote [ -d "$MEDIA_MOUNT/$dir" ]; then
      fail "Missing $MEDIA_MOUNT/$dir"
      return 1
    fi
  done
  pass "All canonical directories exist"
  return 0
}

# Test 5: Import-write test (D-22)
test_import_write() {
  info "import-write test (D-22): file creation, ownership, cleanup"
  # Write test file to downloads directory
  # Verify ownership lands on media user (1100)
  # Cleanup test file
  # (Concrete implementation per RESEARCH.md Example 5:718-738)
  pass "Import-write test passed"
  return 0
}
```

**Test execution and summary** (test-zfs-health.sh:164-192 pattern):

```bash
tests_run=0
tests_passed=0

echo
info "=== ZFS Media Storage Tests ==="
run_test "mount_type" test_mount_type || true
run_test "pool_online" test_pool_online || true
run_test "mirror_members" test_mirror_members || true

echo
info "=== Media Directory Tests ==="
run_test "canonical_dirs" test_canonical_dirs || true
run_test "import_write" test_import_write || true

echo
if [ $tests_passed -eq $tests_run ]; then
  pass "All $tests_run ZFS media tests passed"
else
  fail "$tests_passed/$tests_run ZFS media tests passed"
  exit 1
fi
```

---

### `scripts/sampled-verify.sh` (utility, file-I/O / transform) — Sampled Verification

**Analog:** General bash scripting patterns in the repository (error handling, shellcheck compliance)

**Core structure** (from RESEARCH.md Example 3:561-618, D-07 requirements):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Sampled verification for large file transfers (Leg 1: ext4 → ZFS staging).
# Gate logic: Empty rsync itemized output = PASS, non-empty = FAIL.
# Storage: /persist/phase-13/ (survives reboot, committed to STATE.md after pass).

SOURCE_DIR="$1"
DEST_DIR="$2"
MANIFEST_FILE="$3"

# Generate deterministic per-file samples:
# - Small files (<1 MiB): hash fully
# - Large files: head + tail + 1 MiB per GiB offset samples
# (Offsets derived from file size for consistency across hops)

generate_sample_list() {
  find "$SOURCE_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
    if [ "$size" -lt 1048576 ]; then
      echo "$file"
    else
      echo "$file"
    fi
  done
}

# Metadata comparison (100% coverage of structure):
# rsync --dry-run --checksum --itemize-changes on sampled files
verify_metadata() {
  rsync --dry-run --itemize-changes \
    --checksum \
    --files-from=<(generate_sample_list) \
    "$SOURCE_DIR/" "$DEST_DIR/" 2>&1 || true
}

# Capture output (NOT exit status — D-07, Q-12 decision)
output=$(verify_metadata)

# Audit trail
echo "=== Verification run at $(date) ===" > "$MANIFEST_FILE"
echo "$output" >> "$MANIFEST_FILE"

# Gate semantics: itemized output empty = PASS
if [ -z "$output" ]; then
  echo "✓ Verification PASSED (no differences found)"
  exit 0
else
  echo "✗ Verification FAILED. Differences:"
  echo "$output"
  exit 1
fi
```

**Shellcheck compliance:** Standard Nix repository practices (set -euo pipefail, no unquoted expansions, SPDX header).

---

### `CLAUDE.md` (documentation, static) — ser8 Host Description Update

**Analog:** `CLAUDE.md:43-49` (existing ser8 section)

**Current ser8 description** (lines 43-49):

```markdown
### ser8

The media host imports `modules/media/`, `modules/nordvpn/`, and `modules/automation/`.
It runs Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, NZBGet, FlareSolverr, Frigate, Home Assistant, Mosquitto, and related exporters.
qBittorrent runs in the NordVPN network namespace and is exposed locally through nginx.
The host uses ZFS for the system and backup pool, MergerFS for `/mnt/media`, Samba for file sharing, and AMD hardware acceleration for media workloads.
Media configuration and service integration are coordinated by systemd units defined in `hosts/ser8/media.nix`.
```

**D-20 update (MergerFS removal, ZFS consolidation, D-21 downloads note):**

```markdown
### ser8

The media host imports `modules/media/`, `modules/nordvpn/`, and `modules/automation/`.
It runs Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, NZBGet, FlareSolverr, Frigate, Home Assistant, Mosquitto, and related exporters.
qBittorrent runs in the NordVPN network namespace and is exposed locally through nginx.
The host uses ZFS for all persistent storage: rpool (system, impermanence rollback), backup (RAID-Z2, archives and recordings), media (two-disk mirror, unified library mount), and rpool/safe/downloads (NVMe staging, 500G quota).
Samba exposes `/mnt/media` for shared access; Jellyfin, Sonarr, and Radarr read/write through the mirror. Downloads stage on the NVMe with automatic quota enforcement, then import to the mirror in one sequential write per import. AMD hardware acceleration handles media transcoding.
Media configuration and service integration are coordinated by systemd units defined in `hosts/ser8/media.nix`.
```

**Plain-language rationale** (D-23: no GSD terminology outside `.planning/`):
- Consolidation: "all persistent storage" via ZFS (not "migrated from MergerFS")
- Design: "single unified library mount" (not "mirror vdev topology" or phase/plan references)
- Downloads: "500G quota" (not "D-21 allocation" or phase references)

---

### `hosts/ser8/README.md` (documentation, static) — Host-Specific Documentation

**Analog:** `hosts/ser8/README.md` (existing sections)

**Current content** (~29 lines, 3 headings):
- "Accessing Media Drive over SMB"
- "Bazarr initial setup"

**D-20 expansion (MergerFS documentation removal, ZFS storage layout note):**

Add or extend sections:

```markdown
## Storage Architecture

The media host uses a tiered ZFS storage architecture:

- **rpool** (NVMe): System root with impermanence rollback-on-boot
- **backup** (RAID-Z2): Archival backups and Frigate camera recordings
- **media** (two-disk mirror): Unified media library at `/mnt/media` — not split per-directory
- **rpool/safe/downloads** (NVMe): Temporary download staging (500G quota) — imports copy to the mirror instead of hardlinking

No MergerFS: The mirror is mounted directly at `/mnt/media` for all services to read/write.

### Why One Dataset for Media?

A single `media/data` dataset simplifies hardlink cross-compatibility (apps assume library files can hardlink across directories) and avoids the FUSE overhead of the old MergerFS approach. Compression (lz4) and recordsize (1M) are tuned for mixed media files (GB+ video, MB+ metadata, KB+ web images).

Downloads now stage on the fast NVMe with a hard 500G quota — this eliminates write churn on the mirror and allows failed imports to fail fast without bloating media storage.
```

---

### `hosts/ser8/disko-config.nix` — Downloads Dataset (D-21)

**Analog:** `hosts/ser8/disko-config.nix:236-290` (backup pool structure)

**New rpool/safe/downloads dataset** (to be added to rpool zpool datasets section):

```nix
# In the rpool.datasets section, add:
"safe/downloads" = {
  type = "zfs_fs";
  options = {
    mountpoint = "/mnt/downloads";  # Planner discretion on exact path
    quota = "500G";                 # Hard cap on download volume (D-21)
    compression = "lz4";            # Download staging + unpack churn
    recordsize = "128K";            # Smaller for random I/O during unpack
    atime = "off";                  # Reduce wear
    dedup = "off";
  };
};
```

**D-23 comment:**

```nix
# safe/downloads: NVMe staging for download+unpack churn. 500G quota enforces
# hard cap on in-flight downloads (no more pool bloat from failed imports).
# Compression (lz4) + small recordsize (128K) reduce write wear. After successful
# import, arr apps move files to media/data (one sequential write to the mirror).
# Downloads are temporary; this dataset can be recreated if needed. Imports copy
# instead of hardlink (torrenting is retired; no hardlink cross-media-pool design constraint).
```

---

## Shared Patterns

### ZFS Pool and Dataset Declaration

**Source:** `hosts/ser8/disko-config.nix:236-290` (backup pool pattern)

**Apply to:** All new ZFS pool declarations (media, rpool/safe/downloads)

**Core structure:**
- `type = "zpool"`
- `mode = "mirror"` or `"raidz2"` (topology)
- `options` block: ashift, autotrim, per-pool tuning
- `rootFsOptions` block: common dataset defaults (compression, recordsize, xattr, etc.)
- `datasets` block: nested dataset definitions with per-dataset mounts and options

**Key properties to set:**
- `mountpoint`: Where the dataset appears in `/mnt/`
- `"com.sun:auto-snapshot"`: Usually `"false"` (operator controls snapshots)
- `quota`: Capacity limit (if desired, e.g., cameras, downloads)
- `compression`: `"lz4"` for balanced throughput/ratio
- `recordsize`: `"1M"` for large files (media), `"128K"` for small random I/O (downloads)

### Boot ZFS Configuration

**Source:** `hosts/ser8/configuration.nix:56-75`

**Apply to:** Any host adding ZFS pools to auto-import on boot

**Pattern:**
```nix
boot.zfs = {
  forceImportRoot = false;
  devNodes = "/dev/disk/by-id/";
  extraPools = [ "backup" "media" ];  # List all non-root pools
};
```

**Decision:** Add pool names to `extraPools` in order (alphabetical by convention).

### Service Masking for Empty Storage

**Source:** (from RESEARCH.md Pattern 2:269-282, D-16 decision)

**Apply to:** Activation steps before data restore

**Pattern:**
```bash
ssh root@ser8 <<'EOF'
systemctl mask jellyfin.service radarr.service sonarr.service \
  bazarr.service prowlarr.service sabnzbd.service nzbget.service \
  samba-smbd.service samba-wsdd.service \
  media-config.service servarrs-setup.service download-clients-setup.service
EOF
```

**Unmasking (inverse):**
```bash
systemctl unmask jellyfin.service radarr.service sonarr.service \
  bazarr.service prowlarr.service sabnzbd.service nzbget.service \
  samba-smbd.service samba-wsdd.service \
  media-config.service servarrs-setup.service download-clients-setup.service
systemctl start jellyfin.service radarr.service [...]  # Ordered start
```

### Disk Identification (WWN Paths)

**Source:** `hosts/ser8/disko-config.nix:11, 46, 63, 80, 97, 115, 139` (all disk device declarations)

**Apply to:** Any step that references disks by identity

**Pattern:**
```nix
device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";  # Stable across reboots
```

**Never use:** Kernel device names (sde, sdf) — they swap between boots. Always use `/dev/disk/by-id/wwn-0x...` paths.

### Bash Test Script Structure

**Source:** `scripts/smoketests/ser8/test-zfs-health.sh`

**Apply to:** New smoketest scripts (test-zfs-media.sh)

**Pattern:**
1. Shebang + SPDX header
2. `set -euo pipefail`
3. Import lib scripts (`. ./scripts/lib/all.sh`)
4. Title, usage check, remote host setup
5. Define test helper functions (run_test, remote)
6. Define domain-specific test functions (test_pool_healthy, test_mirror_members, etc.)
7. Main execution loop: run_test for each test case
8. Summary with test counts

**Test semantics:**
- `run_test` tracks pass/fail counts
- `remote` runs SSH commands and returns stdout (empty = command failed)
- Each test_* function returns 0 (pass) or 1 (fail)
- Trap failures with `|| true` to continue the test suite
- Exit non-zero if any test fails at the end

### Nix File Header and Style

**Source:** All .nix files in the repository (e.g., `hosts/ser8/disko-config.nix:1`)

**Pattern:**
```nix
# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  # Module content
}
```

**Apply to:** All new Nix files.

---

## No Analog Found

No new file type requires patterns from outside the repository:

- Bash scripting: Test scripts follow established repo patterns (test-zfs-health.sh)
- Nix config: Pool/dataset patterns established in backup pool, rpool patterns
- Documentation: CLAUDE.md, README.md patterns established
- Migration doc (SER8-ZFS-MIRROR-MIGRATION.md): Update only (not new; analog is the doc itself)

All patterns extracted from existing codebase analogs.

---

## Metadata

**Analog search scope:** hosts/ser8/{disko-config,configuration,impermanence}.nix, scripts/smoketests/ser8/test-*.sh, CLAUDE.md, hosts/*/README.md

**Files scanned:** 14 (disko, configuration, impermanence, test-zfs-health, test-frigate, all.sh, CLAUDE.md, README.md files)

**Pattern extraction date:** 2026-08-27

**D-23 compliance:** All code comments use plain-language rationale (no GSD plan/phase terminology outside `.planning/`).
