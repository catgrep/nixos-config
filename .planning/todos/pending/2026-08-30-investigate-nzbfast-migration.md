---
created: 2026-08-31T01:15:00.000Z
title: Investigate migrating from NZBGet/SABnzbd to nzbfast
area: media
severity: minor
files:
  - hosts/ser8/media/nzbget.nix
  - hosts/ser8/media/sabnzbd.nix
  - hosts/ser8/disko-config.nix
---

## Problem

The 2026-08-30 downloads cleanup showed the structural cost of two-phase usenet clients: download the archive set, then extract beside it, so every job transiently costs 2x its size and `rpool/safe/downloads` needs a 500G quota mostly as unpack headroom.
Nested obfuscated posts needed a custom `nzbget-extract-nested` extension, and NZBGet's compiled-in defaults (Unpack, UnpackCleanupDisk) disagree with its own settings UI.
nzbfast (https://github.com/nzbfast/nzbfast) claims fast one-pass verify-and-extract using roughly half the disk of other clients, which could shrink or remove the staging dataset entirely.

## Solution

Investigate before committing: project maturity and maintenance cadence; whether it exposes an arr-compatible API (Sonarr/Radarr/Prowlarr integration is the hard requirement); how it handles nested/obfuscated posts (would `nzbget-extract-nested` still be needed?); post-processing hook support for the permission normalizer; packaging (nixpkgs presence or custom derivation + module).
If adopted, plan the staging dataset consequences: quota reduction or removal of `rpool/safe/downloads`, and retirement of the NZBGet/SABnzbd pair it replaces (replace, don't run three clients).
