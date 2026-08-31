---
created: 2026-08-31T01:15:00.000Z
title: Onboard rdt-client as a debrid download client
area: media
severity: minor
files:
  - hosts/ser8/media/default.nix
---

## Problem

The media stack is usenet-only.
rdt-client (https://github.com/rogerfar/rdt-client) fronts Real-Debrid (and similar debrid services) behind a qBittorrent-compatible API, letting Sonarr/Radarr treat debrid as a normal download client.

## Solution

Check nixpkgs for a package/module (it is a .NET app; a custom derivation plus a small module may be needed).
Wire it as a qBittorrent-type download client in Sonarr/Radarr, with download paths on the existing staging dataset and the permission conventions the other clients follow.
Credentials: the Real-Debrid account and API token are a human checkpoint - Bobby creates the account and provides the token for sops; agents must not create accounts.
