# Codebase Concerns

**Analysis Date:** 2026-08-17

## Tech Debt

**SOPS admin key bootstrap disabled:**
- Issue: The user-provisioning and status scripts have their admin-age-key logic commented out because the maintainer currently prefers using a GPG key manually instead of the scripted SSH-to-age flow.
- Files: `scripts/sops/add-user.sh:8-19`, `scripts/sops/status.sh:6-14`
- Impact: `make sops-status` no longer reports the admin key, and onboarding a new user via the script does not add the admin's age key to `.sops.yaml`. Anyone relying on the documented `make` targets for secret rotation gets an incomplete picture.
- Fix approach: Either restore the automated path (parameterize which key type is used) or delete the dead code and document the manual GPG workflow as the supported one.

**Tmux status bar color is host-agnostic:**
- Issue: The shared tmux module has a hardcoded status-bar background with a `TODO` noting it should vary per host.
- Files: `modules/common/tmux.nix:3`
- Impact: Cosmetic only; multiple hosts opened in adjacent terminals look identical, increasing risk of running a command on the wrong host by mistake.
- Fix approach: Pass a per-host color parameter into the module from `hosts/<host>/configuration.nix`.

**`rollback-HOST` Make target is a non-functional placeholder:**
- Files: `Makefile:75` (help text), `Makefile:274` (`rollback-%:` target)
- Impact: An operator who assumes `make rollback-ser8` performs an automated rollback after a bad deploy has no real safety net; `CLAUDE.md` explicitly warns not to present it as functional.
- Fix approach: Implement it against `nixos-rebuild --rollback` / generation switching over SSH, or remove the target entirely and rely on `nixos-rebuild switch --rollback` run manually per the deploy docs.

**`experimental/docker-compose/` tree duplicates and diverges from the live flake:**
- Files: `experimental/docker-compose/` (full parallel `hosts/`, `scripts/`, `secrets/keys/` structure)
- Impact: Contains its own copies of provisioning scripts, host configuration, and public key material that can silently drift from the real `hosts/` and `secrets/` trees, creating confusion about which is authoritative. Public keys checked in here (`secrets/keys/users/bobmac-rsa.pub`, host keys) are not obviously kept in sync with `secrets/keys/` at the repo root.
- Fix approach: Either promote this to a real host once complete, or delete it and track the docker-compose exploration in `.planning/` instead of a parallel live-looking tree.

**pi5 has no role-specific module group:**
- Files: `hosts/pi5/`
- Impact: `pi5` only has base server config, boot config, and disk layout (per `CLAUDE.md`); it is effectively unused infrastructure carried in the flake with no service payload, adding maintenance surface without benefit.
- Fix approach: Assign it a role and module group, or remove it from `deploy.yaml`/flake outputs until a role is defined.

## Known Bugs

**Frigate live-stream 403 (pre-existing, documented but unresolved):**
- Symptoms: Frigate's live camera stream returns HTTP 403 under some access paths.
- Files: `modules/automation/frigate.nix`; diagnosis recorded in git history (`fb0b982 docs(09-05): record pre-existing frigate live-stream 403 diagnosis`)
- Trigger: Accessing the Frigate live view through the current reverse-proxy/auth path.
- Workaround: None implemented yet at time of writing; tracked only as a diagnosis, not a fix, per the phase-09 verification report (`5c4912c docs(09): add phase verification report (gaps found)`).

**Phase 09 verification found gaps not yet closed:**
- Symptoms: The most recent phase-09 verification pass (`5c4912c`) reported gaps, followed by two gap-closure plans (`0d5cff8`, `5e0fcb3`) that had not yet been executed as of this analysis.
- Files: `.planning/phases/` (phase 09 artifacts)
- Trigger: N/A — planning-time issue, not a runtime bug.
- Workaround: Re-run `/gsd-progress` or the phase-09 gap-closure plans before treating the 26.05 channel migration as fully verified.

## Security Considerations

**qBittorrent exposed through nginx from inside the NordVPN network namespace:**
- Risk: The service that most directly handles untrusted/internet-facing torrent traffic runs inside a VPN network namespace and is bridged back to the LAN via nginx (`hosts/ser8/media.nix`, `modules/nordvpn/service.nix`). Misconfiguration of this bridge (wrong bind address, missing auth) could expose qBittorrent's WebUI outside the VPN boundary it's meant to be confined to.
- Files: `modules/nordvpn/service.nix` (324 lines), `hosts/ser8/media.nix`
- Current mitigation: Namespace isolation plus nginx reverse proxy; SOPS-managed credentials for the WebUI (`make sops-gen-hash-qbittorrent`).
- Recommendations: Periodically verify with `make smoketests-ser8` that the WebUI is only reachable via the intended LAN path, and confirm nginx does not also bind on the VPN-facing interface.

**Impermanence persistence list is manually curated and easy to under-specify:**
- Risk: `environment.persistence."/persist"` on ser8 hand-lists every directory/file that survives a reboot (SSH host keys, ACME state, NetworkManager connections, Jellyfin data, media mount points). Anything omitted silently resets on next boot, which for `/persist/etc/ssh/*` in particular would rotate host keys and break scripted SOPS decryption (age identities derive from SSH host keys per `CLAUDE.md`).
- Files: `hosts/ser8/impermanence.nix`
- Current mitigation: The critical SSH host keys and ACME/network state are already listed (`hosts/ser8/impermanence.nix:13-31`).
- Recommendations: Add a smoketest or boot-time assertion that confirms `/persist/etc/ssh/ssh_host_ed25519_key` exists and matches the expected fingerprint after activation, since a missing entry here fails silently rather than loudly.

**`.jj` (Jujutsu) working-copy metadata present alongside `.git`:**
- Risk: Low direct security risk, but a second VCS metadata directory (`.jj/`) increases the chance of divergent history or accidental commits made through one tool that the other doesn't see, especially relevant given the "never push directly to main" and PR-review workflow.
- Files: `.jj/`
- Current mitigation: None observed; not clear if `.jj` is actively used or a leftover from experimentation.
- Recommendations: Confirm whether `.jj` is intentional (colocated jj+git repo) or accidental, and gitignore/remove it if unused.

## Performance Bottlenecks

**`tools/sagent/default.nix` is a 1,020-line single file:**
- Problem: The largest file in the repo by a wide margin (next largest is 900 lines). A single monolithic derivation/script definition of this size is slow to review, slow for tooling (`sb`, editors) to parse in full, and increases the chance that unrelated changes collide.
- Files: `tools/sagent/default.nix`
- Cause: Organic growth of the `sagent` sandboxing tool as a single flake output without submodule decomposition.
- Improvement path: Split into logical units (sandbox profile generation, tmux session management, CLI argument parsing) under `tools/sagent/lib/` the way `scripts/lib/` is already organized elsewhere in the repo.

**`modules/gateway/grafana.nix` at 900 lines mixes provisioning config with dashboard logic:**
- Problem: Large single-file module makes it harder to isolate dashboard-provisioning changes from datasource/alerting changes when only one needs to change.
- Files: `modules/gateway/grafana.nix`
- Cause: All Grafana provisioning (datasources, dashboard JSON wiring, alerting) consolidated in one module.
- Improvement path: Split into `datasources.nix`, `dashboards.nix`, and `alerting.nix` under `modules/gateway/grafana/`, mirroring the pattern already used for `hosts/ser8/media/` (separate `orchestration.nix`, `sabnzbd.nix`, etc.).

## Fragile Areas

**Disk identity assumptions in ZFS mirror migration plan:**
- Files: `.planning/SER8-ZFS-MIRROR-MIGRATION.md`, `hosts/ser8/disko-config.nix`
- Why fragile: The migration handoff document explicitly warns that `/dev/sde` and `/dev/sdf` device names are not guaranteed stable across reboots/reinstalls, and any destructive disk step must re-resolve device identity by WWN before running. This is a real and currently-open migration (not yet executed based on planning state), so `disko-config.nix` will need matching updates when it lands.
- Safe modification: Never hardcode `/dev/sdX` paths in `disko-config.nix`; use `/dev/disk/by-id/` WWN paths, and cross-check against the live system before any destructive step, exactly as the migration doc's approval contract requires.
- Test coverage: No automated test can validate physical disk identity; this is inherently a manual, gated process (see the doc's "Additional Disk Approval Gate").

**`modules/nordvpn/service.nix` couples systemd network namespace plumbing to qBittorrent lifecycle:**
- Files: `modules/nordvpn/service.nix` (324 lines)
- Why fragile: Network-namespace-based VPN confinement combined with a reverse-proxy bridge is inherently order-sensitive (namespace must exist before qBittorrent starts, nginx must route into the namespace correctly). A change to systemd unit ordering or nginx upstream config can silently break connectivity without a NixOS build failure.
- Safe modification: Always run `make smoketests-ser8` after touching this file or `hosts/ser8/media.nix`; do not rely on `make build-ser8` succeeding as proof the namespace routing still works.
- Test coverage: Smoketests exist under `scripts/smoketests/` but this analysis did not confirm one specifically exercises the VPN-namespace-to-nginx bridge end to end; verify one exists before making changes here.

**Frigate module (572 lines) and Home Assistant module (471 lines) are the largest automation surfaces:**
- Files: `modules/automation/frigate.nix`, `modules/automation/home-assistant.nix`
- Why fragile: Both integrate with camera hardware acceleration and external device state, areas already shown to have at least one open bug (Frigate live-stream 403). Their size also means a single edit is more likely to have unreviewed side effects elsewhere in the same file.
- Safe modification: Use `sb map` on these files before editing to see the full symbol surface, and re-run the relevant smoketest after any change.
- Test coverage: Git history shows active smoketest coverage work for Frigate/Home Assistant (`a3b28a8 smoketests(09-03): cover Frigate and Home Assistant`), which should be extended alongside any future change rather than assumed sufficient.

## Scaling Limits

**Single-node hosts with no redundancy for stateful services:**
- Current capacity: `ser8` (media/storage/automation) and `firebat` (gateway/monitoring) are each single physical/virtual hosts; there is no documented failover for either.
- Limit: Any hardware failure on `ser8` takes down Jellyfin, the *arr stack, Home Assistant, and Frigate simultaneously; any failure on `firebat` takes down Caddy (all reverse-proxied services), Prometheus, and Grafana simultaneously.
- Scaling path: Out of scope for a homelab of this size, but the in-progress ZFS mirror migration (`.planning/SER8-ZFS-MIRROR-MIGRATION.md`) at least addresses disk-level redundancy for media storage specifically.

## Dependencies at Risk

**`nixos-hardware` pinned to a specific commit rather than a branch:**
- Risk: `flake.nix:12` pins `nixos-hardware` to a fixed commit hash (`ff17823245ab9ff7bcae6acf950bd89cba82c38c`) rather than tracking a branch, which is correct for reproducibility but means Raspberry Pi board-support fixes/updates require a manual bump and are easy to forget.
- Impact: `pi4`/`pi5` board support can silently lag upstream `nixos-hardware` improvements (kernel config, firmware) until someone manually re-pins.
- Migration plan: Periodically check `nixos-hardware` upstream for the `raspberry-pi/4`/`raspberry-pi/5` modules and re-pin during routine `flake update` passes; document this as part of quarterly maintenance.

**Dual `nixpkgs` channels (`nixos-26.05` stable + `nixos-unstable`) increase overlay/package-conflict surface:**
- Risk: `flake.nix:7-8` tracks both a stable and unstable `nixpkgs` input, presumably for packages not yet in stable. Every package sourced from `nixpkgs-unstable` carries less testing and a higher chance of upstream breakage between updates.
- Impact: A `flake update` that bumps `nixpkgs-unstable` can break specific packages (subgen, faster-whisper, etc. under `packages/`) without any corresponding stable-channel signal.
- Migration plan: Audit which overlays/packages actually require the unstable input (`overlays/`) and periodically re-check whether they've since landed in stable, to shrink the unstable surface over time.

## Missing Critical Features

**No documented automated rollback path:**
- Problem: With `rollback-HOST` a placeholder (see Tech Debt), there is no single-command recovery from a bad `switch-HOST` deploy; an operator must know the manual `nixos-rebuild --rollback` incantation and target host address from `deploy.yaml` themselves.
- Blocks: Fast recovery during an on-call/incident scenario, especially for `firebat` where a bad Caddy config could cut off remote access entirely.

**No Raspberry Pi image-building or device-write tooling:**
- Problem: `CLAUDE.md` explicitly states bootstrap-image and device-write targets for the Pi hosts do not exist.
- Blocks: Reproducing `pi4`/`pi5` from bare metal without falling back to manual `nixos-anywhere` or SD-card flashing outside the repo's tooling.

## Test Coverage Gaps

**`experimental/docker-compose/` tree has no smoketest coverage:**
- What's not tested: Anything under `experimental/`, since it is explicitly not part of the active host flake per `CLAUDE.md`.
- Files: `experimental/docker-compose/`
- Risk: Low today (not deployed), but if promoted later without adding smoketests first, it would ship untested relative to every other host's `all.sh` convention under `scripts/smoketests/`.
- Priority: Low (only matters if/when promoted out of `experimental/`).

**No confirmed end-to-end smoketest for the qBittorrent VPN-namespace-to-nginx bridge:**
- What's not tested: This analysis did not locate a smoketest under `scripts/smoketests/` that specifically verifies qBittorrent's WebUI is reachable only through the intended LAN path and not directly via the VPN namespace's interface.
- Files: `modules/nordvpn/service.nix`, `scripts/smoketests/`
- Risk: A regression here is a security-relevant network exposure issue, not just a functional break, making it a higher-priority gap than typical missing coverage.
- Priority: High.

**Frigate live-stream 403 has a diagnosis but no regression test:**
- What's not tested: There is no smoketest asserting the Frigate live-stream path returns 200, so the known-403 issue could recur silently even after a future fix.
- Files: `modules/automation/frigate.nix`, `scripts/smoketests/`
- Risk: Silent regression of a user-facing feature (camera live view) already known to be broken once.
- Priority: Medium.

---

*Concerns audit: 2026-08-17*
