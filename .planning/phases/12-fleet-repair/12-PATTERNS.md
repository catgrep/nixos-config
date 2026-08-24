# Phase 12: Fleet Repair - Pattern Map

**Mapped:** 2026-08-23
**Files analyzed:** 11 modified / 3 deleted
**Analogs found:** 11 / 11

## File Classification

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `modules/common/users.nix` | config | configuration | intra-file (self) | exact |
| `modules/media/default.nix` | config | configuration | intra-file (self) | exact |
| `hosts/ser8/media/default.nix` | config | configuration | intra-file (self) | exact |
| `hosts/ser8/media/qbittorrent.nix` | config | configuration | `hosts/ser8/media/sabnzbd.nix` | role-match (delete) |
| `hosts/ser8/impermanence.nix` | config | configuration | intra-file (self) | exact |
| `modules/media/sabnzbd.nix` | config | configuration | `modules/media/radarr.nix` | exact |
| `Makefile` | build-config | configuration | intra-file (self) | exact |
| `.planning/REQUIREMENTS.md` | documentation | text | intra-file (self) | exact |
| `.planning/ROADMAP.md` | documentation | text | intra-file (self) | exact |
| `.planning/PROJECT.md` | documentation | text | intra-file (self) | exact |
| `secrets/ser8.yaml` | secrets | key-value | handled via `make sops-edit-ser8` | N/A |
| `modules/nordvpn/` | config | configuration | DELETE (entire directory) | delete |
| `scripts/smoketests/nordvpn/` | test | configuration | DELETE (entire directory) | delete |

## Pattern Assignments

### `modules/common/users.nix` (config, configuration)

**Analog:** intra-file pattern (lines 18-44)

**Current pattern** (lines 18-25):
```nix
groups.media = {
  gid = 1100;
};

# Create jellyfin group
groups.jellyfin = {
  gid = 1101;
};
```

**Current pattern** (lines 37-44):
```nix
media = {
  isNormalUser = true;
  group = "media";
  home = "/var/empty";

  description = "Media user for Samba shares";
  uid = 1100;
};
```

**Modification pattern (D-07):** Replace uid 1100 with 1002, gid 1100 with 992 in both group and user declarations. Follow the exact indentation and comment style.

---

### `modules/media/default.nix` (config, configuration)

**Analog:** intra-file pattern (lines 1-17)

**Current pattern**:
```nix
{
  imports = [
    ./jellyfin.nix
    ./jellyfin-exporter.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix     # <-- DELETE THIS LINE
    ./sabnzbd.nix
    ./nzbget.nix
  ];
}
```

**Modification pattern (D-02):** Remove the line `./qbittorrent.nix` from the imports list. Preserve formatting and alphabetical grouping of remaining imports.

---

### `hosts/ser8/media/default.nix` (config, configuration)

**Analog:** intra-file pattern (lines 1-19)

**Current pattern**:
```nix
{
  imports = [
    ./sops.nix
    ./permissions.nix
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./nzbget.nix
    ./sabnzbd.nix
    ./qbittorrent.nix     # <-- DELETE THIS LINE
    ./orchestration.nix
  ];
}
```

**Modification pattern (D-02):** Remove the line `./qbittorrent.nix` from the imports list. Preserve formatting and ordering of remaining imports.

---

### `hosts/ser8/media/qbittorrent.nix` (config, configuration)

**Status:** DELETE entire file (D-02)

**Reason:** This host-specific qBittorrent configuration file is superseded by module deletion and does not need analog extraction.

**Related files to verify:** `modules/media/qbittorrent.nix` (also deleted), `hosts/ser8/media/default.nix` (import removed)

---

### `hosts/ser8/impermanence.nix` (config, configuration)

**Analog:** intra-file persistence patterns (lines 30-215)

**Persistence directories pattern** (lines 50-88):
```nix
directories = [
  # System
  "/etc/nixos"
  "/var/lib/nixos"
  "/var/lib/systemd/coredump"
  # ...
  # Services - Don't specify user/group for services that might not exist yet
  "/var/lib/jellyfin"
  "/var/lib/sonarr"
  "/var/lib/radarr"
  "/var/lib/bazarr"
  "/var/lib/prowlarr"
  "/var/lib/qbittorrent"     # <-- DELETE
  "/var/lib/sabnzbd"
  "/var/lib/nzbget"
  # ... rest
];
```

**Modification pattern (D-03):** Remove `/var/lib/qbittorrent` from the directories list (around line 56).

**Tmpfiles rules pattern** (lines 100-215):
```nix
systemd.tmpfiles.rules = [
  # ... earlier rules ...
  
  # qBittorrent download directories in media filesystem
  "d /mnt/media/downloads 2775 media media -"
  "d /mnt/media/downloads/complete 2775 media media -"
  "d /mnt/media/downloads/incomplete 2775 media media -"
  
  # qBittorrent config directories
  "d /var/lib/qbittorrent 0755 qbittorrent media -"
  "d /var/lib/qbittorrent/qBittorrent 0755 qbittorrent media -"
  "d /var/lib/qbittorrent/qBittorrent/config 0755 qbittorrent media -"
  "d /var/lib/qbittorrent/qBittorrent/data 0755 qbittorrent media -"
  
  # ... more rules ...
  "d /persist/var/lib/qbittorrent 0755 qbittorrent media -"
  
  # ... rest ...
];
```

**Modification pattern (D-03):** Delete all qBittorrent-related tmpfiles rules:
- Lines 172-175 (qBittorrent download directories)
- Lines 186-190 (qBittorrent config directories)
- Line 197 (persist sabnzbd line)

**SABnzbd tmpfiles update pattern (D-12):** Current line 198 reads:
```nix
"d /persist/var/lib/sabnzbd 0755 sabnzbd media -"
```

After D-12 static uid pin in modules/media/sabnzbd.nix, verify this rule persists with the declared uid/gid. No change needed to the tmpfiles rule itself—it references the service identity by name, not numeric id.

---

### `modules/media/sabnzbd.nix` (config, configuration)

**Analog:** `modules/media/radarr.nix` (lines 10-22) - service module user pattern

**Current radarr.nix pattern** (lines 10-22):
```nix
# Create dedicated radarr system user
users.users.radarr = lib.mkIf config.services.radarr.enable {
  isSystemUser = true;
  group = "media";
  home = "/var/lib/radarr/.config/Radarr";
  description = "Radarr";
};

services.radarr = {
  enable = lib.mkDefault false;
  user = "radarr";
  group = lib.mkForce "media";
};
```

**Current sabnzbd.nix pattern** (lines 14-19):
```nix
config = {
  services.sabnzbd.group = lib.mkIf cfg.enable (lib.mkForce "media");

  users.users.sabnzbd = lib.mkIf cfg.enable {
    group = lib.mkForce cfg.group;
  };
```

**Modification pattern (D-12):** Add static uid/gid to sabnzbd user declaration per CONTEXT.md D-12 requirement. Insert after line 17:
```nix
users.users.sabnzbd = lib.mkIf cfg.enable {
  uid = 99;                           # <-- ADD: static uid pin
  gid = 992;                          # <-- ADD: static gid pin (media group)
  group = lib.mkForce cfg.group;
};
```

**Note:** The exact uid/gid values should match the live ser8 identities discovered during diagnosis (D-11 task). These are placeholders; verify against actual values in the live system's `/etc/passwd` and `/etc/group`.

---

### `Makefile` (build-config, configuration)

**Analog:** intra-file pattern (lines 105-115 and 390-391)

**Sops help text pattern** (line 111):
```makefile
$(call help_option,"sops-gen-hash-qbittorrent","Generate PBKDF2-SHA512 hash for qBittorrent WebUI password")
```

**Sops target pattern** (lines 390-391):
```makefile
sops-gen-hash-qbittorrent:
	@./scripts/sops/gen-hash-qbittorrent.py
```

**Modification pattern (D-02):** Delete both the help text line (line 111) and the target definition (lines 390-391). Follow the spacing convention of the surrounding Makefile sections.

---

### `.planning/REQUIREMENTS.md` (documentation, text)

**Analog:** intra-file pattern (lines 7-14)

**Current FLEET-01 requirement** (lines 11-11):
```markdown
- [ ] **FLEET-01**: The wgnord/qBittorrent restart loop is diagnosed and durably fixed in Nix; qBittorrent stays active with a working internet path through the NordVPN namespace
```

**Modification pattern (D-05):** Replace with rescoped text per D-01. New text:
```markdown
- [ ] **FLEET-01**: Torrents are retired; the download path is usenet-only (SABnzbd/NZBGet). The NordVPN + qBittorrent stack is removed entirely from code and state with no restart loop recurrence
```

**Context:** This requirement was rescoped from "fix the loop and keep qBittorrent active" to "retire torrents and remove the stack entirely" per D-01 decision.

---

### `.planning/ROADMAP.md` (documentation, text)

**Analog:** intra-file pattern (lines 55-76)

**Current Phase 12 success criteria** (lines 72-72):
```markdown
  1. qBittorrent stays active with a working internet path through the NordVPN namespace, with no recurring wgnord restart loop
```

**Modification pattern (D-05):** Replace with rescoped text per D-01. New text:
```markdown
  1. The NordVPN + qBittorrent stack is removed from code and state; the download path is usenet-only (SABnzbd/NZBGet) with no drift or restart-loop recurrence
```

**Related change:** Line 86 also contains a qBittorrent reference. Current text:
```markdown
  4. MergerFS is gone from the active configuration, disko defines the mirror, and the full media stack (Jellyfin, Sonarr, Radarr, Bazarr, qBittorrent, SABnzbd, NZBGet, Samba) runs healthy on ZFS...
```

Update to Phase 13 context (not Phase 12). No change needed for Phase 12; this is Phase 13 scope. Keep as-is for now—Phase 13's planner will adjust when they own Phase 13 success criteria.

---

### `.planning/PROJECT.md` (documentation, text)

**Analog:** intra-file Key Decisions table pattern (lines 144-167)

**Key Decisions table format** (lines 146-167):
```markdown
| Decision | Rationale | Outcome |
|----------|-----------|---------|
| MQTT auto-discovery over HACS integration | HACS requires... | ✓ Good |
| Push notifications via HA Companion app | Already have mobile_app... | ✓ Good |
| All automations in Nix | Matches repo pattern... | ✓ Good |
```

**Modification pattern (D-06):** Add new row after the existing entries (after line 167), before the phase-specific evidence sections. New row:
```markdown
| [Phase 12, D-07/D-08] Media user/group identities: uid 1002, gid 992 (live ser8 values) declared in `modules/common/users.nix`, replacing prior repo declaration of 1100/1100 | Live ser8 media tree (~7.8 TB) is never re-chowned; moving to any other uid later would require the mass chown this decision avoids; identity audit extended beyond media to discover any other uid/gid drift (jellyfin, sonarr, radarr, bazarr, sabnzbd, nzbget) | ✓ Adopted (recorded to unblock Phase 13) |
```

---

### `secrets/ser8.yaml` (secrets, key-value)

**Status:** Handled via `make sops-edit-ser8` (D-03)

**Modification pattern:** Do not edit directly; use the Makefile target to avoid plaintext exposure in git history.

**Keys to delete per D-03:**
- NordVPN access token (exact key name to be confirmed during diagnosis)
- `qbittorrent_admin_password_hash` (if present; may have been generated separately)

**Reference:** See `hosts/ser8/media/qbittorrent.nix` lines 50-62 for the secrets this service expected. After deletion of that file and removal from host configuration, the secrets are orphaned and must be removed.

---

## Files to DELETE (Entire Directories)

### `modules/nordvpn/` (D-02)

**Status:** DELETE entire directory and all contents

**Contents to be removed:**
- `modules/nordvpn/default.nix`
- `modules/nordvpn/service.nix` (~324 lines)
- `modules/nordvpn/template.conf`

**Verification:** After deletion, confirm that no remaining Nix files import from `modules.nordvpn` or reference NordVPN configuration.

---

### `scripts/smoketests/nordvpn/` (D-02)

**Status:** DELETE entire directory and all contents

**Contents to be removed:**
- `scripts/smoketests/nordvpn/all.sh` (entry point)
- `scripts/smoketests/nordvpn/disruptive.sh`
- `scripts/smoketests/nordvpn/test-anonymity.sh`
- `scripts/smoketests/nordvpn/test-forwarding.sh`
- `scripts/smoketests/nordvpn/test-netns.sh`
- `scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh`
- `scripts/smoketests/nordvpn/test-qbittorrent.sh`
- `scripts/smoketests/nordvpn/test-veth-interfaces.sh`

**Verification:** After deletion, verify that `scripts/smoketests/ser8/all.sh` (line 36) no longer references `./scripts/smoketests/nordvpn/all.sh`.

---

## Shared Patterns

### NixOS Module Structure (all `.nix` files)

**Header pattern** (preserve on all Nix module files):
```nix
# SPDX-License-Identifier: GPL-3.0-or-later
```

**Module parameter pattern** (preserve on all Nix module files):
```nix
{ config, lib, pkgs, ... }:
```

or for host-specific:

```nix
{ config, lib, ... }:
```

---

### Tmpfiles Rules Pattern (systemd.tmpfiles.rules)

**Standard directory creation** (preserve existing format):
```nix
"d /persist/var/lib/service 0755 service_user service_group -"
```

Format: `d <path> <mode> <user> <group> -`

**Setgid bit for group inheritance** (preserve on media directories):
```nix
"d /mnt/media/downloads/complete 2775 media media -"
```

Mode `2775` sets the setgid bit (2) + rwxrwxr_x (775).

---

### User/Group Declaration Pattern (modules/common/users.nix and service modules)

**System user pattern** (from radarr.nix):
```nix
users.users.SERVICE_NAME = lib.mkIf config.services.SERVICE_NAME.enable {
  isSystemUser = true;
  group = "media";
  home = "/var/lib/SERVICE_NAME/...";
  description = "Service Description";
};
```

**Static uid/gid assignment** (D-12, for sabnzbd only):
```nix
users.users.sabnzbd = lib.mkIf cfg.enable {
  uid = NN;  # numeric static uid
  gid = 992; # numeric static gid (media group)
  group = lib.mkForce cfg.group;
};
```

---

## Verification Checklist (for Planner)

After applying all patterns, verify:

1. ✓ All qBittorrent imports removed from `modules/media/default.nix` and `hosts/ser8/media/default.nix`
2. ✓ `modules/nordvpn/` directory deleted entirely
3. ✓ `scripts/smoketests/nordvpn/` directory deleted entirely
4. ✓ `hosts/ser8/media/qbittorrent.nix` deleted
5. ✓ `modules/common/users.nix` updated: media uid 1002, gid 992
6. ✓ `hosts/ser8/impermanence.nix` qBittorrent entries removed
7. ✓ `modules/media/sabnzbd.nix` static uid/gid added
8. ✓ `Makefile` sops-gen-hash-qbittorrent target and help text removed
9. ✓ `.planning/REQUIREMENTS.md` FLEET-01 text updated (torrents retired)
10. ✓ `.planning/ROADMAP.md` Phase 12 success criteria text updated
11. ✓ `.planning/PROJECT.md` Key Decisions row added for FLEET-03
12. ✓ `secrets/ser8.yaml` NordVPN/qBittorrent secrets removed via `make sops-edit-ser8`

---

## Metadata

**Pattern mapping scope:** Codebase-wide: `modules/`, `hosts/`, `scripts/`, `Makefile`, `.planning/`
**Files examined:** 15 key analogs (users.nix, media services, impermanence.nix, documentation, Makefile)
**Pattern extraction date:** 2026-08-23
**Deletion scope:** 1 directory (nordvpn), 1 smoketest directory (nordvpn), 1 file (qbittorrent.nix)
**Modification scope:** 10 files (users, imports, impermanence, service config, docs, Makefile, secrets)
