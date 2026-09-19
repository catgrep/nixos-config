---
created: 2026-09-19T03:03:13.798Z
title: Semver-pin third-party flake inputs (mvs-style)
area: tooling
severity: minor
files:
  - flake.nix:14-56
  - multiverse.lock
---

## Problem

multiverse.lock now version-pins nixpkgs applications (tailscale, mealie, homebox), but third-party flake inputs (caddy-nix, declarative-jellyfin, impermanence, disko, sops-nix, nixos-images) are still tracked as bare revisions in flake.lock.
A rev tells you nothing about what version you are on or how far behind you are; the only current options are manual rev-pin-plus-comment (too many manual steps) or release branches.
FlakeHub semver ranges were considered and rejected: paid service, centralizes the decentralized flake model.

## Solution

TBD - research first, build only if nothing exists.
Wanted: mvs-like capability for arbitrary flake inputs - map each input's git tags/releases to revisions so inputs can be pinned and audited by version ("disko 1.12.0, 2 releases behind") instead of bare revs.
Research whether existing tools already cover this (npins, niv-style pinning, flake-input update helpers) before building anything.
A small index/tool that resolves git tags to revs per input may be enough.
