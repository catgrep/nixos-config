---
created: 2026-08-18T01:23:36.696Z
title: Migrate .vofi hostnames to public vofi.dev domain
area: gateway
severity: minor
files:
  - modules/gateway/Caddyfile
  - modules/gateway/caddy.nix
  - modules/dns/adguard-home.nix
---

## Problem

Service hostnames currently use Caddy's local CA with made-up `.vofi` / `.vofi.app` domains (see the `local_certs` / `skip_install_trust` global block in `modules/gateway/Caddyfile`).
These names only resolve through AdGuard rewrites on pi4, and pi4 is currently disconnected, so the `.vofi` vhosts are effectively dead weight.
The primary access path today (local and remote) is Tailscale: per-service tsnet vhosts like `https://<name>.shad-bangus.ts.net` with `bind tailscale/<name>`.

Bobby owns the public domain `vofi.dev` and wants services moved to real hostnames under it with publicly trusted TLS certificates instead of the local CA.

## Solution

TBD. Rough shape:

- Replace `.vofi` / `.vofi.app` vhosts in `modules/gateway/Caddyfile` with `<name>.vofi.dev`, using ACME (likely DNS-01 challenge since services are LAN/Tailscale-only) instead of `local_certs`.
- Update any service `BASE_URL`-style settings that reference `.vofi` hostnames.
- Decide DNS story: public DNS pointing at private IPs, or split-horizon via AdGuard once pi4 is back.
- Related to but separate from v1.2 Phase 12 (trusted TLS for household devices) — coordinate so Phase 12 doesn't build more on the local CA than necessary.
