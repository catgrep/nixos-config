---
phase: 12-fleet-repair
reviewed: 2026-08-23T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - Makefile
  - flake.nix
  - hosts/ser8/configuration.nix
  - hosts/ser8/impermanence.nix
  - hosts/ser8/media/default.nix
  - hosts/ser8/media/orchestration-helpers.sh
  - hosts/ser8/media/orchestration.nix
  - hosts/ser8/media/permissions.nix
  - modules/gateway/prometheus.nix
  - modules/media/default.nix
  - modules/media/sabnzbd.nix
  - modules/servers/monitoring.nix
  - scripts/smoketests/media/all.sh
  - scripts/smoketests/ser8/all.sh
  - secrets/ser8.yaml
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-08-23T00:00:00Z
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

This phase removes the NordVPN + qBittorrent stack, pins the SABnzbd account to a static
uid, and cleans up monitoring/smoketest references to the removed services. The mechanical
removal itself is clean: every module import, systemd unit dependency, tmpfiles rule,
Prometheus target, and helper-script function tied to `qbittorrent`/`nordvpn` was found and
deleted with no dangling references inside the reviewed file set (confirmed by a repo-wide
grep for `qbittorrent`, `nordvpn`, and port `8080` across the changed files). No leftover
files (`modules/nordvpn/`, `modules/media/qbittorrent.nix`,
`scripts/sops/gen-hash-qbittorrent.py`, `scripts/smoketests/nordvpn/`) remain on disk. The
new SABnzbd `uid = 985` pin in `modules/media/sabnzbd.nix` is well-justified, does not
collide with any other statically-pinned uid in the repo, and does not conflict with the
host-level `hosts/ser8/media/sabnzbd.nix`, which declares no uid.

`secrets/ser8.yaml` was not decrypted. Diffing it against the pre-phase commit shows only
`qbittorrent_admin_password`, `qbittorrent_admin_password_hash`, three SOPS comment blobs,
and `nordvpn_access_token` were removed; every remaining value is still a well-formed
`ENC[AES256_GCM,...]` blob and the `sops.mac`/`lastmodified` metadata was re-issued
consistently. No plaintext leaked.

Two issues surfaced from cross-referencing the removal against files that were *not*
touched by this phase but depend on what it deleted: a stale firewall port and a smoketest
that still asserts on a directory this phase stopped provisioning.

## Warnings

### WR-01: Firewall keeps port 8080 open for a backend this phase removed

**File:** `hosts/ser8/configuration.nix:28`
**Issue:** `networking.firewall.allowedTCPPorts` still opens `8080` ("General web
services"). Before this phase, `8080` was where qBittorrent's nginx listener lived, and
`modules/gateway/Caddyfile` (unchanged by this phase) still reverse-proxies `torrent.vofi`
to `ser8.local:8080` / `192.168.68.65:8080`. A repo-wide search for port `8080` in
`hosts/ser8` and `modules/` after this phase's changes shows nothing on ser8 listens on it
anymore. The firewall rule is now dead, and the gateway route it used to serve now resolves
to nothing (connection refused / 502 at the Caddy layer instead of a redirect or removed
route).
**Fix:** Remove `8080` from `allowedTCPPorts` now that nothing on ser8 uses it, and file a
follow-up to drop the corresponding `torrent.vofi` block from `modules/gateway/Caddyfile`
(out of this diff, but now orphaned by this change).
```nix
allowedTCPPorts = [
  # Additional ports not in modules
  9134 # ZFS exporter
  445 # SMB
  139 # NetBIOS
];
```

### WR-02: Smoketest still asserts permissions on a directory this phase stopped provisioning

**File:** `scripts/smoketests/media/all.sh:76` (coupled with `hosts/ser8/impermanence.nix`)
**Issue:** This phase removed the qBittorrent-labeled `systemd.tmpfiles.rules` entries that
created `/mnt/media/downloads/complete` and `/mnt/media/downloads/incomplete`
(`hosts/ser8/impermanence.nix`). No other rule creates `/mnt/media/downloads/complete`; the
only remaining mechanism that touches it is `hosts/ser8/media/permissions.nix`'s
`media-permissions` service, which recursively `chgrp`/`chmod`s files that already exist
under `/mnt/media/downloads` but never creates missing directories. Despite this,
`scripts/smoketests/media/all.sh` still runs:
```sh
find /mnt/media/downloads/complete /mnt/media/downloads/usenet/complete \
    ( -type d ( ! -group media -o ! -perm 2775 ) -o -type f ( ! -group media -o ! -perm 0664 ) ) \
    -print -quit
```
On the live `ser8` host this currently passes only because the directory is leftover state
from before qBittorrent was torn down (per the phase's own D-04 note, on-disk paths are
deliberately left untouched and migration is deferred to Phase 13). If that path is ever
removed — which D-04 explicitly permits — `find` will error on the missing path, the `ssh`
command will exit non-zero, and the smoketest will fail with "could not check completed
download permissions" instead of a real permissions failure, breaking the whole
`smoketests-ser8` fan-out for an unrelated reason.
**Fix:** Either drop `/mnt/media/downloads/complete` from this check now that nothing
manages it declaratively, or keep provisioning it via a plain (non-qBittorrent-labeled)
tmpfiles rule until the Phase 13 migration lands and the smoketest can be updated alongside
it.

## Info

### IN-01: Stale rationale comment for the `unstable` specialArg

**File:** `flake.nix:173`
**Issue:** The comment `# Retained with no in-tree consumers: Phase 10 needs this
plumbing.` above the `unstable` specialArg is out of date — `hosts/ser8/household/mealie.nix`
already consumes `unstable.mealie`, so the "no in-tree consumers" claim is no longer true.
Not touched by this phase, but it was read in full per the review scope and is misleading to
future readers deciding whether the plumbing can be removed.
**Fix:** Update or remove the comment now that Phase 10 shipped a real consumer.

---

_Reviewed: 2026-08-23T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
