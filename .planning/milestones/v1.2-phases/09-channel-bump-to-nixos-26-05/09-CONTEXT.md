# Phase 9: Channel Bump to NixOS 26.05 - Context

**Gathered:** 2026-08-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Move the flake off the EOL `nixos-25.11` channel to `nixos-26.05` with all four hosts building cleanly, settle the Raspberry Pi input strategy (FOUND-02), confirm the 26.05 `services.actual` module evaluates on ser8 with real `user`/`group`/`dataDir` options, and activate ser8 (and firebat) with existing media, Frigate, and Home Assistant smoketests passing.
Household services themselves (Mealie, PostgreSQL, etc.) are Phase 10+ and out of scope here.

</domain>

<decisions>
## Implementation Decisions

### Pi input strategy
- **D-01:** Migrate both Pis to upstream: pi4 on `nixos-hardware` (raspberry-pi-4) + upstream nixpkgs 26.05, pi5 on `nixos-hardware` (raspberry-pi-5) + upstream nixpkgs 26.05. The nvmd `nixos-raspberrypi` fork input is removed entirely — input, cachix substituters/keys, and the `nixosInstaller`-based installer targets. — **Reversibility:** costly — undoing means re-adding the fork input and re-migrating `modules/raspberrypi/base.nix` back to `boot.loader.raspberryPi`; the fork's `main` no longer supports that path so re-pinning to the old rev would be required.
- **D-02:** Follow the bootstrap-image pattern from BennyDeeDev/nixos-pi5-template for eventual hardware migration: minimal upstream sd-image with SSH keys baked in, flash once, then deploy the full config remotely with `nixos-rebuild --target-host`. Full-featured custom installers are not rebuilt.
- **D-03:** Mainline kernel (`pkgs.linuxPackages`) on both Pis, overriding any downstream `linux-rpi` default from nixos-hardware. Rationale: Hydra-cached builds; neither host needs Pi-specific peripherals (pi4 = network utility box, pi5 = general purpose).
- **D-04:** Hardware migration method is reflash-from-image, not in-place bootloader migration — but no flashing happens in this phase (see D-06/D-08).

### Activation scope
- **D-05:** Only the x86 hosts activate on 26.05 this phase: ser8 and firebat. Sequencing per host: `make test-HOST` (temporary activation) → smoketests → `make switch-HOST`. ser8 first, firebat second.
- **D-06:** pi4 gets build-compat treatment only: config migrated far enough to build cleanly on upstream nixpkgs + nixos-hardware, no image or flash work. Context: pi4's AdGuard DNS is physically disconnected and unused (this is why its smoketests currently fail); pi4 will probably be retired or repurposed. Record "disconnected, pending retirement/repurpose" alongside the FOUND-02 decision in PROJECT.md Key Decisions.
- **D-07:** pi5 this phase = config build only (evaluates and builds on upstream). Bootstrap image building and the physical reflash are deferred.
- **D-08:** The `make pi4-installer` / `make pi5-installer` targets are removed now (they depend on the removed input). Bootstrap-image targets are added later, alongside the deferred reflash work — note this with the deferred items.

### Input update scope
- **D-09:** Full input update in staged commits for bisection: commit 1 = `nixpkgs` → `nixos-26.05` + `nixos-hardware` bump + `nixos-raspberrypi` removal, then validate; commit 2 = `nix flake update` for the remaining inputs (disko, impermanence, sops-nix, home-manager, unstable, ...), then validate again.
- **D-10:** The Home Manager subflake (`home-manager/`) bumps to `release-26.05` in this same phase, with its configs built as validation.
- **D-11:** Keep the `nixpkgs-unstable` input (caddy-with-plugins follows it; Phase 10's Mealie 3.22 override may need it), but audit and minimize: every `unstable` reference in hosts/modules that 26.05 stable now satisfies moves to stable. `overlays/` is folded into the same audit — remove 25.11-era workarounds that 26.05 obsoletes.
- **D-12:** `system.stateVersion` values stay untouched on all hosts (standard practice).

### Evidence & verification
- **D-13:** FOUND-02 "tested build" evidence = evaluation/dry-activate level, not full toplevel builds. pi4 is disconnected, so its evidence is local evaluation (`nix build --dry-run` / toplevel eval); pi5 gets a real on-host dry-activate if reachable.
- **D-14:** Add permanent committed smoketests (`test-*.sh`) for the bump-sensitive spots on ser8: ZFS pool health, qBittorrent VPN-netns confinement, AMD hardware acceleration (Jellyfin/Frigate transcode).
- **D-15:** Delete the pi4 DNS smoketests outright (they test a retired, disconnected service — replace, don't deprecate). — **Reversibility:** reversible — git history retains them.
- **D-16:** Skip-flag the `.vofi` domain smoketests (keep the files wired into their `all.sh` entry points behind skip guards) so Phase 10 can re-enable them once `.vofi` DNS is re-established.

### Claude's Discretion
- Exact mechanics of the base.nix migration (which upstream bootloader options, firmware partition handling) — constrained by the template pattern in D-02 but details are research/planner territory.
- Whether `nixos-hardware` lands on a branch-follow or a new pinned rev, as long as it's current enough for the rpi5 module.
- How the skip guard for `.vofi` tests is expressed (env var, marker file, etc.).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research (v1.2)
- `.planning/research/STACK.md` — Channel-bump rationale, the 26.05 × nixos-raspberrypi risk analysis, the `services.actual` 25.11-vs-26.05 module diff, and the documented (now-superseded) 25.11 fallback.
- `.planning/research/SUMMARY.md` — Reconciled recommendation that the channel bump is its own gating phase; flags the Pi interaction as the phase's one LOW-confidence risk.

### Pi migration pattern
- `https://github.com/BennyDeeDev/nixos-pi5-template` — User-referenced template for the upstream Pi 5 approach: nixos-hardware rpi5 module, mainline kernel override (avoid uncached `linux-rpi`), U-Boot + extlinux, bootstrap sd-image with baked-in SSH keys, remote deploy. Caveat to verify: the template used nixos-unstable because Pi 5 boot files were too new for stable at the time — researcher must confirm `nixos-26.05` stable suffices. Also note: U-Boot on Pi 5 reads boot files from the SD slot only.

### Current implementation being replaced
- `flake.nix` — The pinned `nixos-raspberrypi` input block (with the comment explaining why it's pinned), the Pi system helper using `nixos-raspberrypi.lib.nixosSystem`, the installer outputs, and the cachix substituter entries — all to be removed/replaced.
- `modules/raspberrypi/base.nix` — Reads `boot.loader.raspberryPi` variants from the fork's nixpkgs; the file that must be migrated to upstream bootloader options.
- `deploy.yaml` — Source of truth for host addresses, tags, and smoketest wiring; pi4 entries and smoketest references need updating per D-06/D-15.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `make test-HOST` / `make switch-HOST` / `make dry-activate-HOST` / `make smoketests-HOST` — the exact rollout ladder D-05 prescribes already exists in the Makefile.
- Existing smoketest suites under `scripts/` (media, Frigate, Home Assistant areas with `all.sh` entry points) — the regression gate for ser8 activation; new `test-*.sh` files from D-14 join these areas.
- `nixos-hardware` is already a flake input (currently pinned to a rev) — bump it rather than adding a new input.
- `nixpkgs-unstable` already threaded into hosts as `unstable` — the audit target for D-11.

### Established Patterns
- Staged, one-logical-change commits with validation between (repo convention) — matches D-09.
- Impermanence + disko on ser8/firebat mean activation changes are eval-checked by `make check` dry-runs before touching live systems.
- `pi5` already uses disko; the fork removal must not regress its disk layout config.

### Integration Points
- `flake.nix` Pi system helper (`nixos-raspberrypi.lib.nixosSystem` with the fork's module imports) → replaced by plain `nixpkgs.lib.nixosSystem` + `nixos-hardware` modules.
- ser8's `services.actual` evaluation check (success criterion 3) is eval-only this phase — no Actual service is deployed.
- Kernel bump on ser8 touches ZFS, the NordVPN network namespace, and AMD VAAPI — the three D-14 smoketest subjects.

</code_context>

<specifics>
## Specific Ideas

- "Did you reference BennyDeeDev/nixos-pi5-template?" — the user explicitly wants the Pi migration modeled on this template (bootstrap image + remote deploy + mainline kernel), not on a rebuilt full installer.
- pi4's DNS role is already dead in practice — treat pi4 as a lame-duck host, not as production DNS.

</specifics>

<deferred>
## Deferred Ideas

- **pi5 bootstrap image + physical reflash** — build the sd-image target and flash pi5 when a maintenance window makes sense; until then pi5 keeps running its current generation. (D-07/D-08)
- **pi4 retirement or repurposing decision** — decide whether pi4 leaves the flake entirely or gets a new role; only then does it need image/flash work.
- **`.vofi` DNS ownership after pi4** — later phases (10+) assume `.vofi` names resolve via AdGuard on pi4, which is disconnected and retiring. Where `.vofi` DNS lives (AdGuard elsewhere, firebat, router) is an open question Phase 10 planning must answer before `mealie.vofi` can work. The skip-flagged `.vofi` smoketests (D-16) get re-enabled then.

</deferred>

---

*Phase: 9-Channel Bump to NixOS 26.05*
*Context gathered: 2026-08-16*
