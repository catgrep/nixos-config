# Phase 9: Channel Bump to NixOS 26.05 - Research

**Researched:** 2026-08-16
**Domain:** NixOS flake channel migration (25.11 EOL → 26.05), Raspberry Pi bootloader/input migration off a downstream fork onto upstream `nixos-hardware`
**Confidence:** HIGH for nixpkgs/nixos-hardware module facts (read directly from branch source at `raw.githubusercontent.com` at named refs). HIGH for repo state (files read in full this session). MEDIUM for runtime behaviour predictions on live hosts (Grafana DB decryption, Home Assistant resource loading) — these need on-host verification, not more reading.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Pi input strategy**
- **D-01:** Migrate both Pis to upstream: pi4 on `nixos-hardware` (raspberry-pi-4) + upstream nixpkgs 26.05, pi5 on `nixos-hardware` (raspberry-pi-5) + upstream nixpkgs 26.05. The nvmd `nixos-raspberrypi` fork input is removed entirely — input, cachix substituters/keys, and the `nixosInstaller`-based installer targets. — **Reversibility:** costly — undoing means re-adding the fork input and re-migrating `modules/raspberrypi/base.nix` back to `boot.loader.raspberryPi`; the fork's `main` no longer supports that path so re-pinning to the old rev would be required.
- **D-02:** Follow the bootstrap-image pattern from BennyDeeDev/nixos-pi5-template for eventual hardware migration: minimal upstream sd-image with SSH keys baked in, flash once, then deploy the full config remotely with `nixos-rebuild --target-host`. Full-featured custom installers are not rebuilt.
- **D-03:** Mainline kernel (`pkgs.linuxPackages`) on both Pis, overriding any downstream `linux-rpi` default from nixos-hardware. Rationale: Hydra-cached builds; neither host needs Pi-specific peripherals (pi4 = network utility box, pi5 = general purpose).
- **D-04:** Hardware migration method is reflash-from-image, not in-place bootloader migration — but no flashing happens in this phase (see D-06/D-08).

**Activation scope**
- **D-05:** Only the x86 hosts activate on 26.05 this phase: ser8 and firebat. Sequencing per host: `make test-HOST` (temporary activation) → smoketests → `make switch-HOST`. ser8 first, firebat second.
- **D-06:** pi4 gets build-compat treatment only: config migrated far enough to build cleanly on upstream nixpkgs + nixos-hardware, no image or flash work. Context: pi4's AdGuard DNS is physically disconnected and unused (this is why its smoketests currently fail); pi4 will probably be retired or repurposed. Record "disconnected, pending retirement/repurpose" alongside the FOUND-02 decision in PROJECT.md Key Decisions.
- **D-07:** pi5 this phase = config build only (evaluates and builds on upstream). Bootstrap image building and the physical reflash are deferred.
- **D-08:** The `make pi4-installer` / `make pi5-installer` targets are removed now (they depend on the removed input). Bootstrap-image targets are added later, alongside the deferred reflash work — note this with the deferred items.

**Input update scope**
- **D-09:** Full input update in staged commits for bisection: commit 1 = `nixpkgs` → `nixos-26.05` + `nixos-hardware` bump + `nixos-raspberrypi` removal, then validate; commit 2 = `nix flake update` for the remaining inputs (disko, impermanence, sops-nix, home-manager, unstable, ...), then validate again.
- **D-10:** The Home Manager subflake (`home-manager/`) bumps to `release-26.05` in this same phase, with its configs built as validation.
- **D-11:** Keep the `nixpkgs-unstable` input (caddy-with-plugins follows it; Phase 10's Mealie 3.22 override may need it), but audit and minimize: every `unstable` reference in hosts/modules that 26.05 stable now satisfies moves to stable. `overlays/` is folded into the same audit — remove 25.11-era workarounds that 26.05 obsoletes.
- **D-12:** `system.stateVersion` values stay untouched on all hosts (standard practice).

**Evidence & verification**
- **D-13:** FOUND-02 "tested build" evidence = evaluation/dry-activate level, not full toplevel builds. pi4 is disconnected, so its evidence is local evaluation (`nix build --dry-run` / toplevel eval); pi5 gets a real on-host dry-activate if reachable.
- **D-14:** Add permanent committed smoketests (`test-*.sh`) for the bump-sensitive spots on ser8: ZFS pool health, qBittorrent VPN-netns confinement, AMD hardware acceleration (Jellyfin/Frigate transcode).
- **D-15:** Delete the pi4 DNS smoketests outright (they test a retired, disconnected service — replace, don't deprecate). — **Reversibility:** reversible — git history retains them.
- **D-16:** Skip-flag the `.vofi` domain smoketests (keep the files wired into their `all.sh` entry points behind skip guards) so Phase 10 can re-enable them once `.vofi` DNS is re-established.

### Claude's Discretion

- Exact mechanics of the base.nix migration (which upstream bootloader options, firmware partition handling) — constrained by the template pattern in D-02 but details are research/planner territory.
- Whether `nixos-hardware` lands on a branch-follow or a new pinned rev, as long as it's current enough for the rpi5 module.
- How the skip guard for `.vofi` tests is expressed (env var, marker file, etc.).

### Deferred Ideas (OUT OF SCOPE)

- **pi5 bootstrap image + physical reflash** — build the sd-image target and flash pi5 when a maintenance window makes sense; until then pi5 keeps running its current generation. (D-07/D-08)
- **pi4 retirement or repurposing decision** — decide whether pi4 leaves the flake entirely or gets a new role; only then does it need image/flash work.
- **`.vofi` DNS ownership after pi4** — later phases (10+) assume `.vofi` names resolve via AdGuard on pi4, which is disconnected and retiring. Where `.vofi` DNS lives (AdGuard elsewhere, firebat, router) is an open question Phase 10 planning must answer before `mealie.vofi` can work. The skip-flagged `.vofi` smoketests (D-16) get re-enabled then.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | Flake runs on nixos-26.05; all four hosts build and dry-activate cleanly (25.11 is EOL) | `nixos-26.05` branch verified to exist and be actively maintained. Five concrete 26.05 breaking changes hitting this repo identified with exact file:line targets (Grafana `secret_key`, `fileSystems.fsType`, HA `lovelace.mode`, mosquitto ≥2.1, `boot.loader.raspberryPi` absence). See *Common Pitfalls* and *Migration Work Inventory*. |
| FOUND-02 | Decision recorded on replacing the nixos-raspberrypi pin with upstream Pi support (nixos-hardware for pi4, upstream nixpkgs for pi5), with a tested build for each Pi host | `nixos-hardware.nixosModules.raspberry-pi-4` and `raspberry-pi-5` verified present; both set `boot.loader.generic-extlinux-compatible` and default `boot.kernelPackages` via `lib.mkDefault` (so D-03's mainline override works). The upstream `hardware.raspberry-pi.{configtxt,firmware}` modules — added to nixos-hardware 2026-03-09 / 2026-07-10 and explicitly adapted from nvmd/nixos-raspberrypi — give full option-level parity with the fork. See *Pi Migration Mechanics*. |
</phase_requirements>

## Summary

The channel bump itself is mechanical: change one URL and re-lock.
The work in this phase is everything the bump breaks, and there are **five verified breaking changes** in the repo plus **one whole subsystem** (the Raspberry Pi input) to re-platform.

The single highest-risk item is not the Pis — it is **firebat's Grafana**.
NixOS 26.05 removed the default value of `services.grafana.settings.security.secret_key`, and Grafana jumps 12.3.6 → 13.0.6 in the same bump.
That key is what encrypts the datasource credentials and the Unified Alerting contact-point secrets that Phase 4 and Phase 5 provisioned into `/var/lib/grafana/grafana.db`.
Setting a *fresh* key silently makes those existing encrypted values undecryptable — the alerting email path stops working without an obvious error.
The migration is to explicitly pin the legacy constant `SW2YcwTIb9zpOOhoPsMm`, which upstream's own release note names for exactly this reason.

The Pi migration turned out **better than the milestone research assumed**.
`.planning/research/STACK.md` rated the `nixos-26.05` × `nixos-raspberrypi` interaction LOW confidence and flagged it as the phase's main unknown; that framing is now obsolete because D-01 removes the fork entirely, and upstream `nixos-hardware` has since absorbed the fork's own machinery.
`nixos-hardware` master now carries `raspberry-pi/common/config-txt.nix` and `raspberry-pi/common/firmware.nix`, both with header comments crediting `nvmd/nixos-raspberrypi` as the source.
That means the fork's `config.txt` generation, vendor-DTB staging, U-Boot chainloading, and firmware-partition refresh all have first-party upstream equivalents — the migration is a rename of option paths, not a loss of capability.

One caveat from the user-referenced Pi 5 template **is confirmed and still true on 26.05**: `nixos-26.05`'s `sd-image-aarch64.nix` has no `[pi5]` section, no `bcm2712-*` device trees, and still uses the split `u-boot-rpi3.bin`/`u-boot-rpi4.bin` layout rather than the unified `ubootRaspberryPiAarch64`.
Pi 5 sd-image support landed on master 2026-07-03, after the 26.05 branch-off.
This does **not** block Phase 9 (D-07/D-08 defer all image work), and there is a verified escape hatch for when the image work happens — see *Open Question 1*.

**Primary recommendation:** Sequence the phase as five commits — (1) input swap + Pi re-platform to a clean *evaluation*, (2) the four x86 breaking-change fixes, (3) `nix flake update` for the remaining inputs, (4) the `unstable`/overlay minimisation audit, (5) smoketest additions/deletions — validating with `make check` between each, and treating the Grafana `secret_key` pin as a blocking prerequisite before `make test-firebat` ever runs.

## Architectural Responsibility Map

This phase has no application tiers; the meaningful tiers are Nix evaluation layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Channel selection, input pinning, cachix substituters | Flake inputs (`flake.nix`, `flake.lock`) | Host nix daemon config (`etc/nix/nix.custom.conf`) | The substituter list is declared in *two* places; removing the fork must touch both or the local dev daemon keeps a dead cache. |
| Host system construction (`nixosSystem` helper, module lists) | Flake outputs (`mkSystem` / `mkPiSystem`) | — | `mkPiSystem` is the only consumer of `nixos-raspberrypi.lib.nixosSystem`; collapsing it into `mkSystem` is the whole Pi re-platform at the flake level. |
| Pi bootloader, config.txt, firmware partition | Upstream `nixos-hardware` modules | `modules/raspberrypi/base.nix`, `hosts/pi5/configtxt.nix` | Was owned by the fork's `nixosModules.raspberry-pi-N.base`; moves to `nixos-hardware.nixosModules.raspberry-pi-N` + `hardware.raspberry-pi.*`. |
| Pi kernel selection | Host/shared Pi module (`pkgs.linuxPackages`) | `nixos-hardware` (`mkDefault linux-rpi`) | D-03 requires overriding nixos-hardware's `lib.mkDefault` vendor-kernel choice; a plain assignment wins over `mkDefault`. |
| Breaking-change remediation (Grafana, fileSystems, HA) | Role modules (`modules/gateway`, `modules/automation`) + host configs | — | These are option-schema changes in 26.05, owned wherever the option is currently set. |
| Package-source minimisation (`unstable` → stable) | Role modules + `overlays/` | Flake inputs | D-11's audit; `nixpkgs-unstable` input stays for Phase 10 even if zero references remain in-tree. |
| Regression evidence | `scripts/smoketests/**` + `deploy.yaml` | `Makefile` (`test-`/`switch-`/`smoketests-`) | The rollout ladder D-05 prescribes already exists; only the test content changes. |

## Standard Stack

This phase adds no application packages. The "stack" is the flake input set.

### Core

| Input | Target | Purpose | Why Standard |
|-------|--------|---------|--------------|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-26.05` | Base channel, all four hosts | Only supported release; branch verified live with commits as recent as 2026-08-14 `[VERIFIED: api.github.com/repos/NixOS/nixpkgs/branches/nixos-26.05 → sha 02e08985a27c65ffd33d434eeb2e660a2e4dc84d, date 2026-08-14T12:45:00Z]` |
| `nixos-hardware` | bump from `daa628a725ab` (locked 2025-05-30) to current master | Pi 4 + Pi 5 board support | Already an input but **currently unused** — `rg` finds zero `nixos-hardware.nixosModules.*` references in-tree `[VERIFIED: repo-wide rg, only hit is flake.nix:9 the input declaration]`. The rpi5 module and the `hardware.raspberry-pi.firmware` module both postdate the current pin. |
| `home-manager` | `github:nix-community/home-manager/release-26.05` | NixOS-integrated HM (top-level flake input) | Branch verified live `[VERIFIED: api.github.com/repos/nix-community/home-manager/branches/release-26.05 → sha 09ae1b85a6db412d841d60f924b23f881f0d0a38, date 2026-08-17T00:01:01Z]` |
| `nixpkgs-unstable` | keep, refresh lock | caddy-nix overlay base, Phase 10 Mealie override | D-11 keeps it. Currently locked at `d233902339c0` (2026-05-15). |

### Supporting (refresh in D-09 commit 2)

| Input | Current lock | Notes |
|-------|--------------|-------|
| `disko` | `65fb947964bd` (2026-05-01) | `inputs.nixpkgs.follows = "nixpkgs"` — moves with the channel automatically |
| `impermanence` | `7b1d382faf60` (2026-01-27) | No `follows`; independent |
| `sops-nix` | `c591bf665727` (2026-05-05) | `follows` nixpkgs |
| `declarative-jellyfin` | `3843ca5bf0bd` (2026-04-02) | `follows` nixpkgs → its module gets evaluated against 26.05. Highest third-party eval risk after the Pi change. |
| `caddy-nix` | `516fabe2f036` (2025-10-01) | Overlay-only flake with **no inputs at all** `[VERIFIED: raw.githubusercontent.com/vincentbernat/caddy-nix/main/flake.nix — full contents are `{ outputs = { self }: { overlays = { default = import ./caddy.nix; }; }; }`]`. Lowest-risk input in the set. |
| `nixos-images` | `66fe34a02cc2` (2026-05-14) | Only consumer is the `aarch64-kexec`/`x86_64-kexec` entries inside `installerConfigurations`. If D-08 removes the whole attrset, decide explicitly whether the kexec installers move elsewhere or the input is dropped. |

### Removed

| Input | Reason |
|-------|--------|
| `nixos-raspberrypi` (`nvmd/nixos-raspberrypi` @ `a12cce571003`) | D-01. Also removes its transitive `nixpkgs_2` = `nvmd/nixpkgs` @ `59714dfc31ef` and `nixos-images_2` = `nvmd/nixos-images` from the lock. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `nixos-hardware` master follow | Pin a specific rev | Discretion per CONTEXT. A pin is more reproducible but `raspberry-pi/common/config-txt.nix` last changed 2026-08-07 and `firmware.nix` 2026-07-14 — this area is under active development, so a pin will need deliberate re-bumps. Recommend pinning a rev **at or after `ff17823245ab`** (master head 2026-08-16) and recording it, so a future `nix flake update` cannot silently change Pi boot behaviour. |
| Pinning the legacy Grafana `secret_key` | Generating a fresh key + re-entering all Grafana secrets | A fresh key is cleaner cryptographically, but requires manually re-provisioning every stored secret in `grafana.db`. Since the datasource has no password and the contact-point secrets are already re-derivable from SOPS, this is *feasible* but is unplanned scope. Recommend pinning the legacy value in Phase 9 and treating rotation as a separate backlog item. |
| Removing the `sabnzbd` overlay | Keeping it | 26.05 ships sabnzbd **5.0.4**, newer than the overlay's pinned **5.0.3** `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/by-name/sa/sabnzbd/package.nix:76 → `version = "5.0.4";` vs nixos-25.11 same path line 76 → `version = "4.5.5";`]`. Removing is strictly better; keeping means maintaining a *downgrade*. |

**Installation:** no package installs. The change is `flake.nix` edits plus `nix flake lock --update-input` / `nix flake update`.

**Version verification:** all versions in this document were read from `pkgs/**/package.nix` at the named branch refs on 2026-08-16 (see *Sources*). Re-verify at plan time if more than ~2 weeks elapse; `nixos-26.05` receives backports continuously.

## Package Legitimacy Audit

**Not applicable — no npm / PyPI / crates packages are introduced by this phase.**

`gsd-tools query package-legitimacy check` supports only the npm, PyPI and crates registries; the Nix ecosystem is out of its scope.
The equivalent supply-chain surface here is the flake input set, audited below by provenance instead.

| Input | Source | Provenance | Verdict | Disposition |
|-------|--------|-----------|---------|-------------|
| `nixpkgs` @ `nixos-26.05` | `github:NixOS/nixpkgs` | Official NixOS org, branch confirmed via GitHub API | OK | Approved |
| `nixos-hardware` | `github:NixOS/nixos-hardware` | Official NixOS org; module source read directly | OK | Approved |
| `home-manager` @ `release-26.05` | `github:nix-community/home-manager` | nix-community org, branch confirmed via GitHub API | OK | Approved |
| `disko`, `impermanence` | `github:nix-community/*` | nix-community org, already in use | OK | Retained |
| `sops-nix` | `github:Mic92/sops-nix` | Established, already in use | OK | Retained |
| `caddy-nix` | `github:vincentbernat/caddy-nix` | Single-author flake, already in use, zero inputs, overlay only | OK | Retained |
| `declarative-jellyfin` | `github:Sveske-Juice/declarative-jellyfin` | Single-author flake, already in use; its own flake tracks `nixpkgs?ref=master` but this repo overrides via `follows` | OK | Retained — but see Pitfall 8 |
| `nixos-raspberrypi` | `github:nvmd/nixos-raspberrypi` | Single-author fork carrying its own nixpkgs fork | — | **REMOVED** per D-01 |

**Packages removed:** the `nixos-raspberrypi` input and its two transitive forks (`nvmd/nixpkgs`, `nvmd/nixos-images`).
Removing a third-party nixpkgs fork from the closure is a net **reduction** in supply-chain surface for this phase.

**Packages flagged as suspicious:** none.

## Architecture Patterns

### System Architecture Diagram

```
                                 BEFORE (25.11)                              AFTER (26.05)

  flake inputs                                             flake inputs
  ┌────────────────────────┐                               ┌────────────────────────┐
  │ nixpkgs @ nixos-25.11  │──┐                            │ nixpkgs @ nixos-26.05  │──┐
  │ nixpkgs-unstable       │──┤                            │ nixpkgs-unstable       │──┤
  │ nixos-hardware (UNUSED)│  │                            │ nixos-hardware (bumped)│──┤
  │ home-manager rel-25.05 │──┤                            │ home-manager rel-26.05 │──┤
  │ nixos-raspberrypi ─────┼──┼──┐                         │        (fork gone)     │  │
  │   └─ nvmd/nixpkgs fork │  │  │                         └────────────────────────┘  │
  └────────────────────────┘  │  │                                                     │
                              │  │                                                     │
                    ┌─────────┘  └──────────┐                    ┌───────────────────┬─┘
                    ▼                       ▼                    ▼                   ▼
             mkSystem()              mkPiSystem()          mkSystem()          mkSystem(usePiModules)
        nixpkgs.lib.nixosSystem   fork.lib.nixosSystem   nixpkgs.lib.       nixpkgs.lib.nixosSystem
                    │                       │             nixosSystem              + nixos-hardware
                    │                       │                  │                 .nixosModules.rpi-N
                    │              imports fork's              │                        │
                    │           raspberry-pi-N.base            │                        │
                    ▼                       ▼                  ▼                        ▼
              ┌──────────┐            ┌──────────┐       ┌──────────┐             ┌──────────┐
              │  ser8    │            │   pi4    │       │  ser8    │             │   pi4    │
              │ firebat  │            │   pi5    │       │ firebat  │             │   pi5    │
              └────┬─────┘            └────┬─────┘       └────┬─────┘             └────┬─────┘
                   │                       │                  │                        │
    boot.loader.raspberryPi ───────────────┘   boot.loader.generic-extlinux-compatible ┘
    hardware.raspberry-pi.config               hardware.raspberry-pi.configtxt.settings
      .all.options / .base-dt-params             + .deviceTreeOverlays
                                               hardware.raspberry-pi.firmware.uboot


  ACTIVATION FLOW (D-05, x86 only this phase)

    make check ──▶ make dry-activate-HOST ──▶ make test-HOST ──▶ smoketests-HOST ──▶ make switch-HOST
    (eval gate)     (activation preview)      (temp activate,     (regression        (boot default)
                                               reboot reverts)     gate)
                                                                       │
    ser8 first ─────────────────────────────────────────────────────────┘  then firebat

  PI EVIDENCE FLOW (D-06/D-07/D-13, no activation)

    nix build .#nixosConfigurations.pi4.config.system.build.toplevel --dry-run  ──▶ FOUND-02 evidence
    nix build .#nixosConfigurations.pi5.config.system.build.toplevel --dry-run  ──▶ FOUND-02 evidence
    make dry-activate-pi5 (only if reachable) ─────────────────────────────────▶ optional stronger evidence
```

The diagram's load-bearing point: after the change **there is only one `nixosSystem` entry point**.
`mkPiSystem` disappears; the Pis become ordinary `mkSystem` calls with `system = "aarch64-linux"`, `useX86Modules = false`, `usePiModules = true`, plus the `nixos-hardware` board module in their `modules` list.
`mkSystem` already has `useX86Modules` and `usePiModules` flags `[VERIFIED: flake.nix:204-234 — `mkSystem = { hostname, system ? "x86_64-linux", modules ? [ ], useX86Modules ? true, usePiModules ? false, }:` and `++ (if usePiModules then piModules else [ ])`]`, so the parameters already exist and are simply unused today.

### Recommended File Layout Changes

```
flake.nix                          # remove nixos-raspberrypi input + nixConfig cachix + mkPiSystem
                                   #   + installerConfigurations; bump nixpkgs/nixos-hardware/home-manager
etc/nix/nix.custom.conf            # remove the nixos-raspberrypi.cachix.org substituter + key
modules/raspberrypi/
├── base.nix                       # migrate system.nixos.tags off boot.loader.raspberryPi
├── installer.nix                  # DELETE (only consumer was installerConfigurations)
└── usb-installer.nix              # DELETE (same)
hosts/pi5/configtxt.nix            # rewrite: hardware.raspberry-pi.config → .configtxt.settings
hosts/ser8/impermanence.nix        # add fsType to the two bind mounts
modules/gateway/grafana.nix        # add settings.security.secret_key
modules/automation/home-assistant.nix  # remove config.lovelace.mode
modules/media/sabnzbd.nix          # remove the whole overlay (26.05 ships 5.0.4 > pinned 5.0.3)
modules/servers/tailscale.nix      # unstable.tailscale → pkgs.tailscale
scripts/smoketests/
├── dns/                           # DELETE per D-15
├── media/all.sh                   # skip-guard the .vofi domains per D-16
├── lib/services.sh                # skip-guard the pi4-as-DNS-resolver path per D-16
└── media/test-zfs-health.sh       # NEW per D-14
    media/test-vaapi.sh            # NEW per D-14 (or under a new ser8/ area)
    nordvpn/test-qbittorrent-confinement.sh  # NEW per D-14
deploy.yaml                        # pi4 smoketests entry per D-15
Makefile                           # remove pi4-installer / pi5-installer / write-pi{4,5} targets
```

### Pattern 1: Pi system construction via upstream modules

**What:** Replace `nixos-raspberrypi.lib.nixosSystem` + the fork's `raspberry-pi-N.base` with plain `nixpkgs.lib.nixosSystem` + `nixos-hardware.nixosModules.raspberry-pi-N`.

**When to use:** Both Pi hosts, this phase.

**Current code being replaced:**

```nix
# flake.nix:176-201  [VERIFIED: flake.nix:176-201]
mkPiSystem =
  { hostname, piVersion ? "4", modules ? [ ], }:
  nixos-raspberrypi.lib.nixosSystem {
    specialArgs = { inherit inputs; inherit nixos-raspberrypi; unstable = import nixpkgs-unstable { system = "aarch64-linux"; config.allowUnfree = true; }; };
    modules = [
      nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".base
      nixos-raspberrypi.nixosModules."raspberry-pi-${piVersion}".display-vc4
      ./hosts/${hostname}/configuration.nix
    ] ++ baseModules ++ piModules ++ modules;
  };
```

Note the fork variant imports `./hosts/${hostname}/configuration.nix` directly, whereas `mkSystem` imports `./hosts/${hostname}` (the directory's `default.nix`).
`hosts/pi4/` and `hosts/pi5/` have **no `default.nix`** `[VERIFIED: `ls -R hosts/pi4 hosts/pi5` → pi4: configuration.nix, hardware-configuration.nix; pi5: configtxt.nix, configuration.nix, disko-config.nix, hardware-configuration.nix]`, so collapsing into `mkSystem` requires either adding `default.nix` files to both Pi host dirs or keeping the explicit `configuration.nix` path. Adding `default.nix` matches ser8/firebat (`hosts/ser8/default.nix` exists) and is the more consistent choice — it also gives pi5 a natural home for its `configtxt.nix` and `disko-config.nix` imports, which currently live in the flake's `modules` list.

**Target shape:**

```nix
pi4 = mkSystem {
  hostname = "pi4";
  system = "aarch64-linux";
  useX86Modules = false;
  usePiModules = true;
  modules = [
    nixos-hardware.nixosModules.raspberry-pi-4
    ./modules/dns
  ];
};

pi5 = mkSystem {
  hostname = "pi5";
  system = "aarch64-linux";
  useX86Modules = false;
  usePiModules = true;
  modules = [
    nixos-hardware.nixosModules.raspberry-pi-5
    disko.nixosModules.disko
  ];
};
```

`nixosModules.raspberry-pi-4` and `raspberry-pi-5` are both real attribute names `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/flake.nix:419-420 → `raspberry-pi-4 = import ./raspberry-pi/4;` and `raspberry-pi-5 = import ./raspberry-pi/5;`]`.

`mkSystem` currently applies the caddy-nix overlay unconditionally to every host `[VERIFIED: flake.nix:223-227 — the modules list opens with `{ nixpkgs.overlays = [ caddy-nix.overlays.default ]; }`]`. Applying it on aarch64 Pi hosts is new behaviour; it is an overlay that only redefines `caddy`, so it should be inert, but it is a real difference from `mkPiSystem` and worth a moment's thought if a Pi eval regresses.

### Pattern 2: Mainline-kernel override (D-03)

**What:** Both nixos-hardware board modules default `boot.kernelPackages` to the uncached vendor kernel.

```nix
# nixos-hardware raspberry-pi/5/default.nix
kernelPackages = lib.mkDefault (
  pkgs.linuxPackagesFor (pkgs.callPackage ../common/kernel.nix { rpiVersion = 5; })
);
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/5/default.nix — identical `lib.mkDefault` shape at raspberry-pi/4/default.nix]`

That kernel is `pname = "linux-rpi"` at `modDirVersion = "6.18.39"`, built from `raspberrypi/linux` tag `stable_20260724` `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/common/kernel.nix — `modDirVersion = "6.18.39"; tag = "stable_20260724"; ... pname = "linux-rpi";`]`.

**How to override:** a plain assignment beats `lib.mkDefault`.

```nix
# modules/raspberrypi/base.nix
boot.kernelPackages = pkgs.linuxPackages;
```

**Why this is safe on Pi 5:** the rpi5 module explicitly branches on which kernel you picked and selects the right initrd module names for mainline.

```nix
let linuxVariant = config.boot.kernelPackages.kernel.pname; in
...
++ lib.optional (linuxVariant == "linux") "rp1_pci"
++ lib.optional (linuxVariant == "linux-rpi") "rp1"
++ lib.optional (linuxVariant == "linux") "pinctrl-rp1"
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/5/default.nix]`

Mainline is a first-class supported path in that module, not an accident.
The module also asserts `lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.1.54"` for Pi 5 and `"6.1"` for Pi 4 — 26.05's `pkgs.linuxPackages` is far past both.

### Pattern 3: config.txt migration (pi5)

**What:** The fork's option schema and upstream's are different shapes for the same job.

| Fork (current, `hosts/pi5/configtxt.nix`) | Upstream `nixos-hardware` |
|---|---|
| `hardware.raspberry-pi.config.all.options.<k> = { enable = true; value = v; }` | `hardware.raspberry-pi.configtxt.settings.all.<k> = v;` |
| `hardware.raspberry-pi.config.all.base-dt-params.<k> = { enable = true; value = v; }` | `hardware.raspberry-pi.configtxt.settings.all.dtparam = [ "<k>=<v>" ];` |
| (dtoverlays inline) | `hardware.raspberry-pi.configtxt.deviceTreeOverlays.<filter> = [ { <name> = { params }; } ];` |

Upstream option paths verified verbatim: `options.hardware.raspberry-pi.configtxt = { settings = …; deviceTreeOverlays = …; file = …; }` `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/common/config-txt.nix]`.

**Concrete migration for `hosts/pi5/configtxt.nix`.** The current file sets exactly four things `[VERIFIED: hosts/pi5/configtxt.nix — `enable_uart`, `uart_2ndstage` under `all.options`; `pciex1`, `pciex1_gen` under `all.base-dt-params`]`:

```nix
# BEFORE (fork schema)
hardware.raspberry-pi.config.all = {
  options = {
    enable_uart   = { enable = true; value = true; };
    uart_2ndstage = { enable = true; value = true; };
  };
  base-dt-params = {
    pciex1     = { enable = true; value = "on"; };
    pciex1_gen = { enable = true; value = "3"; };
  };
};

# AFTER (nixos-hardware schema)
hardware.raspberry-pi.configtxt.settings.all = {
  enable_uart   = true;
  uart_2ndstage = true;
  # NOTE: this list REPLACES the module default `lib.mkDefault [ "audio=on" ]`.
  dtparam = [ "audio=on" "pciex1=on" "pciex1_gen=3" ];
};
```

Two things the planner must not miss here:

1. `config-txt-defaults.nix` ships `dtparam = lib.mkDefault [ "audio=on" ]` under `all` `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/common/config-txt-defaults.nix — `dtparam = lib.mkDefault [ "audio=on" ];`]`. A normal-priority definition outranks `mkDefault`, so `audio=on` must be re-listed or it silently disappears.
2. The same defaults file sets `pi5.enable_uart = lib.mkDefault false`, with the comment *"The Pi 5 has a dedicated debug UART. Leaving the mini UART on feeds ghost input into boot, so turn it back off."* `[VERIFIED: same file]`. `hosts/pi5/configtxt.nix` currently forces `enable_uart` **on**. Setting it under `all` and leaving the `pi5` default at `false` produces a config.txt where the `[pi5]` filter section turns it back off — which is upstream's deliberate behaviour and cross-confirmed by nixpkgs master's own sd-image comment referencing `bugzilla.opensuse.org/show_bug.cgi?id=1251192` `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/installer/sd-card/sd-image-aarch64.nix — `[pi5]` / `enable_uart=0`]`. **Recommendation: drop the `enable_uart`/`uart_2ndstage` settings entirely for pi5 and let the upstream defaults win.** They were serial-console debugging aids for the original fork install; keeping them fights a documented Pi 5 boot hazard.

**Verification command** (pure eval, no hardware needed):

```bash
nix eval --raw '.#nixosConfigurations.pi5.config.hardware.raspberry-pi.configtxt.file' \
  | xargs cat
```

This renders the exact config.txt and is the cheapest possible proof the migration is right.

### Pattern 4: firmware partition (deferred, but decide the option now)

`hardware.raspberry-pi.firmware.enable` installs an activation script that repopulates `/boot/firmware` on every `nixos-rebuild switch`, and `hardware.raspberry-pi.firmware.uboot.enable` chainloads U-Boot by setting `config.txt`'s `kernel=u-boot.bin` `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/common/firmware.nix — `hardware.raspberry-pi.configtxt.settings.all = { kernel = lib.mkDefault "u-boot.bin"; arm_64bit = lib.mkDefault pkgs.stdenv.hostPlatform.isAarch64; }` inside `lib.mkIf cfg.uboot.enable`]`.

Both default to **disabled** (`mkEnableOption`).

**Recommendation for Phase 9: leave both disabled.**
D-06/D-07 explicitly scope this phase to build-compat, and enabling the activation script would rewrite `/boot/firmware` on a live Pi the first time anyone runs `switch` — including pruning DTBs it did not copy, which the module's own docstring warns about: *"The activation script prunes stale `*.dtb` files and overlays it didn't copy, so don't keep manual changes on the FAT partition."*
Enabling it belongs with the deferred reflash work.
Record that as an explicit decision so the deferred item has a starting point.

### Anti-Patterns to Avoid

- **Bumping `nixpkgs` and running `nix flake update` in one commit.** D-09 forbids it and it is right: with five independent breaking changes plus a Pi re-platform, a single mega-commit makes `git bisect` useless. Validate between commits.
- **Setting a fresh Grafana `secret_key`.** See Pitfall 1. This is the one change in this phase that fails *silently and later* rather than at eval time.
- **Deleting `modules/raspberrypi/base.nix` along with the fork.** It carries systemd-networkd DHCP config and a udev rule that are still needed; only the `system.nixos.tags` block is fork-coupled.
- **Treating "the flake evaluates" as done for the Pis.** `nix flake check` builds the toplevel *derivation graph*; it does not prove a Pi will boot. D-13 already scopes evidence to eval level — the plan should say so out loud so nobody over-claims in PROJECT.md.
- **Migrating `hosts/pi4/hardware-configuration.nix`'s hard-coded UUIDs.** They describe the *currently running* pi4 disk. Leave them; changing them without a reflash breaks the host that is still (nominally) booted from them.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Generating Pi `config.txt` from Nix | A `writeText` + string interpolation module | `hardware.raspberry-pi.configtxt.settings` / `.deviceTreeOverlays` | Upstream's renderer handles conditional-filter stacking, `dtoverlay=` scope terminators, the 98-char line limit, and bool→`on`/`off` vs `1`/`0` distinctions. Its own source comments explain why a naive attrset-to-ini pass gets `dtparam` ordering wrong. |
| Staging Pi firmware onto the FAT partition | A custom `system.activationScripts` copy loop | `hardware.raspberry-pi.firmware` | Upstream's is idempotent (temp-file + rename), prunes stale DTBs, and correctly uses `pkgs.buildPackages` for cross-compiled image builds vs target `pkgs` for activation. Getting the cross case wrong is a well-known trap — upstream fixed it in a dedicated commit (`f185edb4e960`, "fix firmware install when cross-compiling"). |
| Pi 5 SD image with Pi 5 boot files on 26.05 | Hand-copying `bcm2712-*.dtb` into `sdImage.populateFirmwareCommands` | Import `nixos-hardware` common (which `mkForce`-overrides `sdImage.populateFirmwareCommands`) **or** build the image from the `nixpkgs-unstable` input | Deferred work, but pre-decide it. See Open Question 1. |
| Detecting Pi board version for `system.nixos.tags` | Reading `boot.loader.raspberryPi.variant` | An explicit module argument or a literal per-host string | The fork option does not exist upstream and will not come back. |
| Grafana secret rotation | A hand-written re-encrypt script | Pin the legacy key now; use `grafana-secretkey-rotation-tool` if rotation is ever wanted | Upstream's own release note names this tool and states there is no official rotation path. |
| Comparing evaluated host configs across the bump | Diffing `nix eval` output by eye | `nix eval --json '.#packageInfo.<host>'` and `nix eval --json '.#enabledServices.<host>'` | These flake outputs already exist `[VERIFIED: flake.nix:375-519]` and give a machine-diffable before/after. This is the cheapest high-signal regression check in the repo and it is already built. |

**Key insight:** the fork was carrying real engineering — config.txt rendering, firmware staging, DTB pruning. That engineering has since been upstreamed into `nixos-hardware` with attribution (`raspberry-pi/common/config-txt.nix` header: *"Based on work from nvmd/nixos-raspberrypi (MIT License)"*; `firmware.nix` header: *"DTB/overlay copy adapted from nvmd/nixos-raspberrypi (MIT)."*). The migration is therefore a *rename*, not a *reimplementation* — and any temptation to write replacement logic by hand means the upstream equivalent has not been found yet.

## Runtime State Inventory

This is a migration phase. All five categories answered explicitly.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | **(a)** `/var/lib/grafana/grafana.db` on firebat — datasource credentials and Unified Alerting contact-point secrets encrypted with Grafana's *default* `secret_key`, which 26.05 removes. **(b)** `/var/lib/hass/.storage/lovelace_resources` on ser8 — written declaratively via a tmpfiles `C+` rule `[VERIFIED: modules/automation/home-assistant.nix:447 → `"C+ /var/lib/hass/.storage/lovelace_resources 0600 hass hass - ${lovelaceResources}"`]`; its reason for existing changes under 26.05. **(c)** ZFS pools `rpool` and `backup` on ser8, incl. the `rpool/local/root@blank` snapshot the impermanence rollback depends on `[VERIFIED: hosts/ser8/configuration.nix:88-90 → `initrd.postDeviceCommands = lib.mkAfter '' zfs rollback -r rpool/local/root@blank ''`]`. **(d)** `/var/lib/AdGuardHome/AdGuardHome.yaml` on pi4 — mutated at each boot by a `preStart` yq injection; pi4 is disconnected so this is frozen. | (a) **code edit** — pin `secret_key` to the legacy constant; **no data migration** if the legacy value is used. (b) **code edit + on-host verification** — see Pitfall 3. (c) **no migration**; ZFS 2.3.8 in 26.05 reads existing pools. Add the D-14 health smoketest. (d) **none** — out of scope, host disconnected. |
| **Live service config** | Grafana dashboards/alerts created through the UI. The dashboard provider sets `allowUiUpdates = true` and `disableDeletion = false` `[VERIFIED: modules/gateway/grafana.nix — `disableDeletion = false; updateIntervalSeconds = 10; allowUiUpdates = true;`]`, so UI-side edits live in `grafana.db` and are **not** in `dashboards/*.json`. Jellyfin state managed by `declarative-jellyfin`. Frigate's runtime config. | Take a `grafana.db` copy before `make test-firebat`. This is the only non-git-backed live config in the blast radius, and the Grafana major-version jump (12.3.6 → 13.0.6) can perform one-way schema migrations on it. |
| **OS-registered state** | `systemd-boot` on ser8 (`boot.loader.systemd-boot.enable = true` `[VERIFIED: hosts/ser8/configuration.nix:79-82]`) — generations accumulate normally, rollback path intact. On pi4/pi5, `/boot/firmware` contents (`config.txt`, `u-boot*.bin`, vendor DTBs) were written by the **fork's** image builder and are **not** refreshed by `nixos-rebuild switch`. The running pi5 generation was likewise built by the fork. | **None this phase** — D-06/D-07 mean neither Pi is switched. But record it: the moment anyone runs `make switch-pi5` on the migrated config, the ext4 side updates (kernel/initrd/`extlinux.conf`) while the FAT side keeps fork-era U-Boot. That mixed state is exactly why D-04 chose reflash-from-image. **The plan should ensure `switch-pi4`/`switch-pi5` are not run.** |
| **Secrets & env vars** | SOPS age identities derive from SSH host keys (`/persist/etc/ssh/` on persistent hosts) — unaffected by a channel bump. Existing Grafana secrets `grafana_admin_password`, `grafana_smtp_password` consumed via `$__file{}` — unaffected. Tailscale `tailscale_authkey` from `secrets/shared.yaml` — unaffected. pi4's `adguard_user_password_hash` — unaffected. | **One potential new secret:** `grafana_secret_key` in `secrets/firebat.yaml`, if the SOPS route is chosen for Pitfall 1. No existing key is renamed or removed. |
| **Build artifacts / installed packages** | `etc/nix/nix.custom.conf` on the *developer machine* pins `nixos-raspberrypi.cachix.org` as a substituter and trusted key `[VERIFIED: etc/nix/nix.custom.conf — `extra-substituters = https://cache.nixos.org https://nixos-raspberrypi.cachix.org` and the matching `extra-trusted-substituters` / `extra-trusted-public-keys` lines]`. The same cachix entries appear in `flake.nix` `nixConfig` `[VERIFIED: flake.nix:60-67]` and in three `experimental/docker-compose/` files. Local `/nix/store` holds fork-built aarch64 closures. | **Code edit** to `etc/nix/nix.custom.conf` + `flake.nix` (`experimental/` is out of the active flake — leave it or note it). Applied via the existing `make update-nix-conf` target. Store GC is optional cleanup, not required. |

## Common Pitfalls

### Pitfall 1: Grafana `secret_key` — silent decryption failure

**What goes wrong:** After bumping firebat to 26.05, Grafana either refuses to start (no `secret_key`) or — worse, if a fresh key is generated — starts fine but can no longer decrypt the secrets already stored in `grafana.db`. Email alerting stops working with no obvious error at deploy time.

**Why it happens:** 26.05 removed the option's default value. Upstream's release note:

> `services.grafana.settings.security.secret_key` doesn't have a default value anymore. Please generate your own key or hard-code the old one ("SW2YcwTIb9zpOOhoPsMm") explicitly.
>
> `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/doc/manual/release-notes/rl-2605.section.md, Backward Incompatibilities section]`

The repo does **not** set it — `modules/gateway/grafana.nix` `settings.security` contains only `admin_user` and `admin_password` `[VERIFIED: modules/gateway/grafana.nix:65-69 → `security = { admin_user = "admin"; admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}"; };`]`.

The blast radius is real: Phase 4 wired Gmail SMTP into Grafana Unified Alerting contact points, and Phase 5 moved alert rules into Grafana-managed provisioning. Contact-point secrets are stored encrypted with `secret_key`.

**How to avoid:** set it explicitly to the legacy constant. Two viable shapes:

```nix
# Option A — SOPS, matching the existing admin_password / smtp_password pattern
security.secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
# secrets/firebat.yaml must contain the LEGACY value: SW2YcwTIb9zpOOhoPsMm
```

```nix
# Option B — literal, with a comment explaining it is the published upstream default
# Not a credential this repo minted; it is a public constant. But it IS an
# encryption key, so CLAUDE.md's "never commit plaintext credentials" argues for A.
security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
```

**Recommendation: Option A.** It keeps a grep for secrets in the repo clean and matches the two adjacent settings, at the cost of one new SOPS entry. Whichever is chosen, the *value* must be the legacy constant — this is a compatibility pin, not a security decision.

**Warning signs:** `journalctl -u grafana` showing `failed to decrypt` / `invalid key` on datasource or contact-point load; a test alert that never arrives at `catgrep@sudomail.com`. Add a post-switch check that fires a Grafana test notification.

### Pitfall 2: `fileSystems.<name>.fsType` lost its default — eval error on ser8

**What goes wrong:** `make check` fails on ser8 with *"The option `fileSystems."/etc/nixos".fsType' is used but not defined."*

**Why it happens:** In 25.11 the option had `default = "auto"`; in 26.05 it has no default.

```nix
# nixos-25.11/nixos/modules/tasks/filesystems.nix:124-127
fsType = mkOption {
  default = "auto";
  example = "ext3";
  type = nonEmptyStr;
```
```nix
# nixos-26.05/nixos/modules/tasks/filesystems.nix:124-126
fsType = mkOption {
  example = "ext3";
  type = nonEmptyStr;
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/{nixos-25.11,nixos-26.05}/nixos/modules/tasks/filesystems.nix]`

Confirmed by the release note: *"The `fileSystems.<name>.fsType` option no longer has a default value and must be specified by the user."*

**Where it bites in this repo:** two bind mounts in `hosts/ser8/impermanence.nix` declare `device` + `options = [ "bind" ]` and no `fsType`:

```nix
# hosts/ser8/impermanence.nix:172-183  [VERIFIED, verbatim]
fileSystems."/etc/nixos" = {
  device = "/persist/etc/nixos";
  options = [ "bind" ];
  neededForBoot = true;
};

fileSystems."/var/log" = {
  device = "/persist/var/log";
  options = [ "bind" ];
  neededForBoot = true;
};
```

**How to avoid:** add `fsType = "none";` to both (the conventional value for bind mounts).

`fileSystems."/persist"` at `hosts/ser8/impermanence.nix:25` sets only `neededForBoot = true` — disko supplies `device`/`fsType` for it by merge, so it should be fine, but the planner should confirm by eval rather than assume. Everything else in the repo already has an explicit `fsType`: `/mnt/media` (`fuse.mergerfs`), `/tmp` and `/nix-builds` (`tmpfs`) `[VERIFIED: hosts/ser8/configuration.nix:138-176]`, and both pi4 entries `[VERIFIED: hosts/pi4/hardware-configuration.nix:24-35 → `/` ext4, `/boot/firmware` vfat]`.

**Warning signs:** the error names the exact mount, so this one is loud and cheap. It fails at eval, before anything is built.

### Pitfall 3: Home Assistant `lovelace.mode` deprecation + the `.storage` hack

**What goes wrong:** A new deprecation warning appears on ser8 (which CLAUDE.md says to treat as a failure), and — subtler — the repo's hand-rolled `lovelace_resources` storage-file hack may become redundant or start double-registering the custom card.

**Why it happens:** the 26.05 module emits:

```nix
warnings = optionals (cfg.config ? lovelace.mode) [
  ''
    services.home-assistant.config.lovelace.mode is deprecated.
    Home Assistant 2026.8 renames the legacy top-level `lovelace.mode`
    setting in favour of per-dashboard configuration.

    Use `services.home-assistant.config.lovelace.dashboards` and
    `services.home-assistant.config.lovelace.resource_mode` instead.
  ''
];
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/home-automation/home-assistant.nix:837-848]`

The repo sets it:

```nix
# modules/automation/home-assistant.nix:285-287  [VERIFIED, verbatim]
config.lovelace = {
  mode = "storage"; # Keep default dashboard UI-editable
  dashboards = {
```

The deeper interaction: the repo built a workaround for storage-mode resource loading —

```nix
# modules/automation/home-assistant.nix:58-59  [VERIFIED, verbatim]
# When lovelace.mode = "storage", HA ignores lovelace.resources in configuration.yaml
# and reads from .storage/lovelace_resources instead. We create this file declaratively.
```

In 26.05 the module introduces `resource_mode`, defaulting to `"yaml"` whenever custom cards are present:

```nix
resource_mode = mkOption {
  type = types.nullOr (types.enum [ "yaml" "storage" ]);
  default = if cfg.customLovelaceModules != [ ] then "yaml" else null;
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/home-automation/home-assistant.nix:625-631]`

ser8 sets `customLovelaceModules = [ advanced-camera-card ]` `[VERIFIED: modules/automation/home-assistant.nix:280-282]`, so 26.05 will auto-set `resource_mode = "yaml"` and HA will read resources from `configuration.yaml` — which the module already injects via `customLovelaceModulesResources`. The `.storage/lovelace_resources` file then becomes redundant.

**How to avoid:**
1. Remove `mode = "storage";` — the `dashboards` attrset stays as-is.
2. Do **not** remove the `.storage` tmpfiles rule blindly. Deploy with `make test-ser8`, load the camera dashboard, and check whether the advanced-camera-card renders and whether HA's resource list shows a duplicate. Then decide.
3. Note that the tmpfiles rule uses `C+`, which copies **unconditionally on every boot** — so a stale duplicate cannot be cleaned by simply deleting the file once.

**Warning signs:** camera dashboard shows "Custom element doesn't exist: advanced-camera-card" (resource not loaded) or the card appears twice / logs a duplicate-registration error (loaded from both paths). This is a UAT item, not an automated one.

### Pitfall 4: HA jumps six months of releases in one step

`hassVersion` goes 2025.11.3 → 2026.5.4 `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/{nixos-25.11,nixos-26.05}/pkgs/servers/home-assistant/default.nix → `hassVersion = "2025.11.3";` / `hassVersion = "2026.5.4";`]`.

Only the lovelace change is called out in the NixOS release notes, but HA's own breaking changes across six monthly releases are not in scope for nixpkgs notes. The `modules/automation/home-assistant.nix` file is ~470 lines of declarative `config`, including Frigate integration wiring and notification automations that reference `review['after']['camera']` templates.

**Mitigation:** HA writes its own migration on first start and does not support downgrade of `.storage`. Snapshot `/var/lib/hass` before `make test-ser8`. This is the second-most-likely source of a "smoketests pass but the thing is subtly broken" outcome after Grafana.

### Pitfall 5: Frigate 0.16.3 → 0.17.2 and the overlay's fail-fast guards

`overlays/frigate-tflite-optional.nix` patches five files and **hard-aborts the build** if the import line it expects is absent:

```bash
grep -q '    from tensorflow\.lite\.python\.interpreter import Interpreter' "$f" \
  || { echo "Frigate TFLite import pattern changed in $f" >&2; exit 1; }
```
`[VERIFIED: overlays/frigate-tflite-optional.nix]`

26.05 ships Frigate **0.17.2** vs 25.11's **0.16.3** `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/{nixos-25.11,nixos-26.05}/pkgs/by-name/fr/frigate/package.nix]`.

**Good news — checked, and the guards still hold.** All five target files exist at tag `v0.17.2` and each still contains the expected import line `[VERIFIED: raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/... → bird.py:25, face_embedding.py:20, audio.py:46, cpu_tfl.py:15 each `    from tensorflow.lite.python.interpreter import Interpreter`; edgetpu_tfl.py:16 `    from tensorflow.lite.python.interpreter import Interpreter, load_delegate`]`. The surrounding structure is also unchanged — e.g. `bird.py`:

```python
try:
    from tflite_runtime.interpreter import Interpreter
except ModuleNotFoundError:
    from tensorflow.lite.python.interpreter import Interpreter
```

So the overlay survives the bump.

**But it still needs the D-11 treatment:** the overlay exists because ser8 strips tensorflow from Frigate's `PYTHONPATH` to dodge a protobuf/onnxruntime symbol clash. Whether 0.17.2 still needs that workaround is a separate question the audit should answer, because carrying an unnecessary `overrideAttrs` on a package this large is exactly the kind of drift D-11 targets. Frigate 0.17 is a substantial release; expect config-schema warnings on first start as a separate risk from the overlay.

### Pitfall 6: `boot.loader.raspberryPi` does not exist upstream — and never did on 25.11 either

`modules/raspberrypi/base.nix` reads two attributes of it:

```nix
# modules/raspberrypi/base.nix:49-58  [VERIFIED, verbatim]
  # System tags for identification
  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];
```

The upstream option directory `nixos/modules/system/boot/loader/raspberrypi` is absent from `nixos-24.11`, `nixos-25.05`, `nixos-25.11` **and** `nixos-26.05` `[VERIFIED: GitHub contents API returned "Not Found" for that path on all four refs]`. It only exists in the `nvmd/nixpkgs` fork. So removing the fork *must* rewrite this block; there is no upstream fallback and nothing to wait for.

**Replacement:** the two Pi-identifying facts have to come from somewhere else. Cleanest options, in order:

```nix
# Option A — module argument (matches how mkSystem already threads `unstable` via specialArgs)
{ piVersion, config, pkgs, lib, ... }:
system.nixos.tags = [
  "raspberry-pi-${piVersion}"
  "extlinux"
  config.boot.kernelPackages.kernel.version
];
```

```nix
# Option B — a small option owned by modules/raspberrypi/
options.homelab.raspberryPi.variant = lib.mkOption { type = lib.types.enum [ "4" "5" ]; };
# set from hosts/pi4/default.nix and hosts/pi5/default.nix
```

Option B is more consistent with the repo's two-layer module pattern (reusable module declares the interface; host module sets the policy) and is what CLAUDE.md's structure implies. `config.boot.kernelPackages.kernel.version` is upstream and keeps working unchanged.

Alternatively drop the `system.nixos.tags` block entirely — it is cosmetic (it labels boot-menu entries). Worth asking, since the Pis boot via extlinux where the tag surfaces differently than under the fork's bootloader.

### Pitfall 7: mosquitto ≥2.1 requirement — already satisfied, verify anyway

Release note: *"[services.mosquitto] now generates per-listener authentication and access control via the upstream `password-file` and `acl-file` plugins... [](#opt-services.mosquitto.package) must now be at least version 2.1."*

26.05 ships mosquitto **2.1.2** `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/by-name/mo/mosquitto/package.nix:37 → `version = "2.1.2";`]`, and the repo does not override `services.mosquitto.package` `[VERIFIED: rg for mosquitto across modules/ hosts/ — hits are `mosquitto.enable = true` at hosts/ser8/configuration.nix:216, a `services.mosquitto` block at modules/automation/home-assistant.nix:423, and unit-ordering references]`. **No action needed** — but the underlying auth plugin change means the generated mosquitto config file differs. Frigate↔HA MQTT is the coupling; ser8's smoketests should confirm Frigate still publishes detections after the switch.

### Pitfall 8: `declarative-jellyfin` evaluated against a channel it does not target

Its own flake declares `nixpkgs.url = "github:nixos/nixpkgs?ref=master"` `[VERIFIED: raw.githubusercontent.com/Sveske-Juice/declarative-jellyfin/main/flake.nix]`, but this repo overrides it with `inputs.nixpkgs.follows = "nixpkgs"` `[VERIFIED: flake.nix:39-42]`. Its module will therefore be evaluated against 26.05 while upstream develops against master. Its lock is from 2026-04-02, i.e. pre-26.05.

**Mitigation:** this is exactly what D-09's staged commits are for — if `make check` on ser8 fails inside a `declarative-jellyfin` module, commit 2's `nix flake update` (which bumps it) is the first thing to try. Jellyfin itself only moves 10.11.10 → 10.11.11 `[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/{nixos-25.11,nixos-26.05}/pkgs/by-name/je/jellyfin/package.nix]`, so the package side is a non-event; only the third-party module is a risk.

### Pitfall 9: the `.vofi` smoketests are not separate files

D-16 says *"keep the files wired into their `all.sh` entry points behind skip guards"* — but there are no `.vofi`-specific files. The `.vofi` domains are inline in an array:

```bash
# scripts/smoketests/media/all.sh  [VERIFIED, verbatim excerpt]
MEDIA_SERVICES=(
	"Jellyfin:jellyfin.vofi:8096:jellyfin"
	"Sonarr:sonarr.vofi:8989:sonarr"
	...
)
```

and the DNS dependency lives one level down in the shared helper:

```bash
# scripts/smoketests/lib/services.sh  [VERIFIED, verbatim excerpt]
    info "using host 'pi4' as the DNS server"
    dns_ipaddr=$(get_ip "pi4")

    # First check if we can resolve the domain using the AdGuard DNS server
    if ! nslookup "$domain" "$dns_ipaddr" >/dev/null 2>&1; then
        warn "DNS resolution failed for $domain using AdGuard DNS, trying with Host header"
```

So `test_service()` **already** degrades to a Host-header curl against the ser8 IP when pi4 does not answer. The tests are not currently *failing* on `.vofi` — they are emitting `warn` and falling back. The skip guard therefore belongs in `scripts/smoketests/lib/services.sh` (suppress the pi4 lookup + the warn, go straight to the Host-header path), not in `media/all.sh`.

`.vofi` also appears in `modules/gateway/Caddyfile` (14 occurrences) and `modules/dns/adguard-home.nix` (11) `[VERIFIED: `rg -c vofi` across the repo excluding `.planning` and lockfiles]`. Those are configuration, not tests, and are out of scope for D-16.

### Pitfall 10: `unstable` and overlay audit results (D-11)

Every current `unstable` reference and overlay, with the 26.05 verdict:

| Reference | Location | 25.11 | 26.05 | Verdict |
|---|---|---|---|---|
| `unstable.tailscale` | `modules/servers/tailscale.nix:20` | 1.90.9 | **1.98.10** | **Move to stable.** The in-file comment says *"stable 25.05 has 1.82.5, need >= 1.92.5"*; 26.05 clears the bar. `[VERIFIED: pkgs/by-name/ta/tailscale/package.nix on both refs]` |
| `unstable.par2cmdline-turbo` | `modules/media/sabnzbd.nix:71` | 1.3.0 | **1.4.0** | **Move to stable.** In-file comment: *"SABnzbd 5.x release builds use par2cmdline-turbo 1.4; stable 25.11 has 1.3."* Requirement now met. |
| sabnzbd 5.0.3 `overrideAttrs` | `modules/media/sabnzbd.nix:15,79-80` | 4.5.5 | **5.0.4** | **Delete the whole overlay.** In-file comment: *"sabnzbd 5.0.3: nixpkgs 25.11 has 4.5.5; bump via overlay until stable catches up."* 26.05 is *newer* than the pin — keeping it is a downgrade. Also removes the sabctools 8.2.6→9.4.0 divergence. |
| `inputs.nixpkgs-unstable` flake registry entry | `modules/common/nix.nix:35` | — | — | **Keep.** Registry convenience, unrelated to package sourcing. |
| `overlays/frigate-tflite-optional.nix` | applied to ser8 only `[VERIFIED: flake.nix:245-248]` | — | — | **Keep for now**, but re-justify: verify whether Frigate 0.17.2 + 26.05 still needs the tensorflow-off-PYTHONPATH workaround this overlay supports. |
| `caddy-nix.overlays.default` | applied to all `mkSystem` hosts | 2.11.4 | 2.11.4 | **Keep.** Caddy version is unchanged across the bump; the overlay exists for plugin support, not version. |

If both `unstable.*` references move to stable, **zero** `unstable` package references remain in-tree. D-11 explicitly says keep the input anyway for Phase 10. Note that `mkSystem`/`mkPiSystem` pass `unstable` through `specialArgs` `[VERIFIED: flake.nix:216-221]` — leave that plumbing in place, and delete the two stale `# Remove when stable tailscale >= 1.92.5` comments at `flake.nix:186` and `flake.nix:216`.

### Pitfall 11: the Home Manager version-mismatch baseline changes

STATE.md records a Phase 08 decision: *"Permit only the exact user-approved Home Manager mismatch baseline — continue without changing dependency pins or disabling release checks; reject changed or new warnings."*

That baseline exists because `flake.nix:45` pins `home-manager/release-25.05` against `nixpkgs/nixos-25.11` `[VERIFIED: flake.nix:44-47, verbatim `url = "github:nix-community/home-manager/release-25.05";`]` — a **two-release** gap. Bumping to `release-26.05` alongside `nixos-26.05` aligns them and should make the warning **disappear entirely**:

```nix
lib.optional (config.home.enableNixpkgsReleaseCheck && releaseMismatch) ''
  You are using
    ${...versionsSummary...}
```
`[VERIFIED: raw.githubusercontent.com/nix-community/home-manager/release-26.05/modules/home-environment.nix:601-604]`

**The plan must explicitly update the accepted-warning baseline** rather than treat the warning's disappearance as an unexplained diff. A warning that vanishes is still a change to a recorded baseline.

Also note D-10's wording is slightly off-target: `home-manager/flake.nix` (the *subflake*) does **not** pin `release-25.05` — it tracks `nixpkgs-unstable` and home-manager `main`, and builds an `aarch64-darwin` `homeConfigurations."bobby"` `[VERIFIED: home-manager/flake.nix — `nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";`, `home-manager.url = "github:nix-community/home-manager";`, `system = "aarch64-darwin";`]`. The `release-25.05` pin that causes the NixOS-side mismatch is the **top-level** `flake.nix:45` input. The planner should treat D-10 as covering *both*: bump `flake.nix:45` to `release-26.05` (this is the one that matters for FOUND-01), and separately decide whether the darwin subflake should also pin a release branch or keep following unstable. `make home-switch` builds the subflake and is the validation D-10 asks for.

## Code Examples

### Verify the 26.05 `services.actual` module (Success Criterion 3)

Pure evaluation — no service enabled, no deployment. The option defaults evaluate without `services.actual.enable = true`.

```bash
# The three options that do not exist on 25.11
nix eval --json '.#nixosConfigurations.ser8.options.services.actual.user.type.name'
nix eval --json '.#nixosConfigurations.ser8.options.services.actual.group.type.name'
nix eval --raw  '.#nixosConfigurations.ser8.config.services.actual.settings.dataDir'
# expect: "nullOr" / "nullOr" / /var/lib/actual

# Prove serverFiles/userFiles are real options derived from dataDir
nix eval --raw '.#nixosConfigurations.ser8.config.services.actual.settings.serverFiles'
nix eval --raw '.#nixosConfigurations.ser8.config.services.actual.settings.userFiles'
# expect: /var/lib/actual/server-files  /var/lib/actual/user-files
```

The 26.05 module definitions, verbatim:

```nix
# nixos-26.05/nixos/modules/services/web-apps/actual.nix
user = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
  ...
};
group = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
  ...
};
...
dataDir = lib.mkOption {
  type = lib.types.str;
  default = "/var/lib/actual";
  ...
};
...
ReadWritePaths = [
  cfg.settings.dataDir
  cfg.settings.serverFiles
  cfg.settings.userFiles
];
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/web-apps/actual.nix]`

For contrast, the 25.11 module has `dataDir` as a plain `let` binding and an unconditional `DynamicUser`:

```nix
# nixos-25.11/nixos/modules/services/web-apps/actual.nix
20:  dataDir = "/var/lib/actual";
...
59:          serverFiles = mkDefault "${dataDir}/server-files";
60:          userFiles = mkDefault "${dataDir}/user-files";
61:          dataDir = mkDefault dataDir;
...
83:        DynamicUser = true;
88:        WorkingDirectory = dataDir;
```
`[VERIFIED: raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/actual.nix]`

Note `dataDir` lives under `settings`, **not** at the top level — a plan that writes `services.actual.dataDir` will fail. Also note: `settings` is a freeform JSON submodule with `_secret` support, and the 25.11 module's `mkDefault` on `settings.dataDir` means the *option path* is identical but the *option definition* is not. Asserting on `options.services.actual.user` is the unambiguous discriminator.

### Verify FOUND-02 evidence (Pi builds, no hardware)

```bash
# Evaluation + derivation-graph proof for each Pi (D-13 evidence level)
nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'
nix build --dry-run '.#nixosConfigurations.pi5.config.system.build.toplevel'

# Prove the bootloader actually moved to upstream extlinux
nix eval '.#nixosConfigurations.pi4.config.boot.loader.generic-extlinux-compatible.enable'
nix eval '.#nixosConfigurations.pi5.config.boot.loader.generic-extlinux-compatible.enable'
# expect: true  true

# Prove the mainline-kernel override (D-03) won over nixos-hardware's mkDefault
nix eval --raw '.#nixosConfigurations.pi5.config.boot.kernelPackages.kernel.pname'
# expect: linux   (NOT linux-rpi -- linux-rpi means the override did not apply)

# Render the migrated config.txt and eyeball it
nix eval --raw '.#nixosConfigurations.pi5.config.hardware.raspberry-pi.configtxt.file' | xargs cat
```

The `kernel.pname` check is the single most valuable Pi assertion: if it returns `linux-rpi`, the build will attempt an hours-long uncached kernel compile, which is precisely what D-03 exists to prevent.

### Before/after config diff for the x86 hosts

```bash
# On the 25.11 lock, before any edits:
nix eval --json '.#packageInfo.ser8'      > /tmp/ser8-2511.json
nix eval --json '.#enabledServices.ser8'  > /tmp/ser8-2511-svc.json
nix eval --json '.#packageInfo.firebat'   > /tmp/firebat-2511.json
nix eval --json '.#enabledServices.firebat' > /tmp/firebat-2511-svc.json

# After the bump:
nix eval --json '.#enabledServices.ser8' | diff <(jq -S . /tmp/ser8-2511-svc.json) <(jq -S .) 
```

These outputs already exist in the flake `[VERIFIED: flake.nix:375-519 — `enabledServices`, `servicePackages`, `packageInfo` attrsets]` and are the cheapest way to catch a service that silently stopped being enabled because an option was renamed.

### Bind-mount fsType fix

```nix
# hosts/ser8/impermanence.nix
fileSystems."/etc/nixos" = {
  device = "/persist/etc/nixos";
  fsType = "none";          # 26.05: no longer defaults to "auto"
  options = [ "bind" ];
  neededForBoot = true;
};

fileSystems."/var/log" = {
  device = "/persist/var/log";
  fsType = "none";
  options = [ "bind" ];
  neededForBoot = true;
};
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Pi support via `nvmd/nixos-raspberrypi` + its nixpkgs fork | `nixos-hardware` `raspberry-pi-{4,5}` + `hardware.raspberry-pi.{configtxt,firmware}` | config.txt module 2026-03-09 (`a688dfcbb560`); firmware module 2026-07-10 (`f54c3bcb6557`); ordered dtoverlays 2026-08-07 (`7aefd9ab01ee`) | The fork's distinguishing features are now upstream, with attribution. The reason to run the fork has largely evaporated. `[VERIFIED: api.github.com/repos/NixOS/nixos-hardware/commits?path=...]` |
| `boot.loader.raspberryPi` (fork-only) | `boot.loader.generic-extlinux-compatible` + U-Boot chainload | Upstream removed the rpi loader before 24.11 | No upstream migration path exists; the rewrite is unavoidable. |
| Split `u-boot-rpi3.bin` / `u-boot-rpi4.bin` per-board in the aarch64 sd-image | Unified `pkgs.ubootRaspberryPiAarch64` (`rpi_arm64_defconfig`) with `kernel=u-boot.bin` for all boards | nixpkgs PR #537862, merged to **master** 2026-07-03 — **after** the 26.05 branch-off | 26.05's `sd-image-aarch64.nix` still uses the old split layout and has no Pi 5 files. See Open Question 1. `[VERIFIED: api.github.com/repos/NixOS/nixpkgs/pulls/537862 → merged_at 2026-07-03T08:26:21Z, base master; plus direct diff of the module on both refs]` |
| `services.promtail` for log shipping | `services.alloy` | 26.05 removes promtail | Already the repo's chosen direction (v1.1 decision), and neither is currently configured — `rg` finds zero hits for either `[VERIFIED: repo-wide rg for promtail\|alloy\|profiles/hardened\|enableNg\|jellyseerr\|AcceptEnv\|linux_hardened\|linux-rt → no matches]`. No action. |
| Bash `nixos-rebuild` | Python `nixos-rebuild` (was `nixos-rebuild-ng`) | 26.05 removes the Bash implementation and forbids `system.rebuild.enableNg` | Repo does not set `enableNg` (verified above). The repo's own `scripts/nixos-rebuild.sh` wrapper calls the binary and is unaffected by the reimplementation, but its flag handling is worth a smoke check on the first `make dry-activate-ser8`. |
| `profiles/hardened`, `linux_hardened`, `linux-rt` | removed in 26.05 | 26.05 | Repo uses none of them (verified above). No action. |

**Deprecated/outdated in this repo after the bump:**
- The `nixos-raspberrypi` pin comment block at `flake.nix:26-31` — its entire premise (keep `boot.loader.raspberryPi` alive) is resolved by the migration.
- `modules/raspberrypi/installer.nix` and `usb-installer.nix` — sole consumers are `installerConfigurations`, removed by D-08. Note `installer.nix` embeds an RSA public key for `bobby@bob-mac.local`; deleting the file removes it from the tree, and the replacement bootstrap image (deferred) should use an ed25519 key.
- `experimental/docker-compose/pi5-usb-installer.nix` also imports `nixos-raspberrypi` but is outside the active flake — leave it or note it as dead, per CLAUDE.md's "proactively flag dead code."

## Migration Work Inventory

A single table the planner can turn directly into tasks. Ordered by D-09's commit staging.

| # | Commit | File | Change | Verified basis |
|---|--------|------|--------|----------------|
| 1 | C1 | `flake.nix:7` | `nixos-25.11` → `nixos-26.05` | branch exists |
| 2 | C1 | `flake.nix:9` | bump `nixos-hardware` to ≥ `ff17823245ab` | rpi5 + firmware modules postdate current pin |
| 3 | C1 | `flake.nix:25-33` | delete `nixos-raspberrypi` input block | D-01 |
| 4 | C1 | `flake.nix:60-67` | delete `nixConfig` cachix substituter + key | D-01 |
| 5 | C1 | `flake.nix:77` | remove from `outputs` args | — |
| 6 | C1 | `flake.nix:171-201` | delete `mkPiSystem`; keep `piModules` | Pattern 1 |
| 7 | C1 | `flake.nix:260-276` | pi4/pi5 via `mkSystem` + `nixos-hardware.nixosModules.raspberry-pi-N` | Pattern 1 |
| 8 | C1 | `flake.nix:292-316` | delete `installerConfigurations`; decide fate of the two kexec entries + `nixos-images` input | D-08 |
| 9 | C1 | `hosts/pi4/default.nix`, `hosts/pi5/default.nix` | **new** — `mkSystem` imports the directory, not `configuration.nix` | `ls` shows neither exists |
| 10 | C1 | `modules/raspberrypi/base.nix:49-58` | rewrite `system.nixos.tags` off `boot.loader.raspberryPi` | Pitfall 6 |
| 11 | C1 | `modules/raspberrypi/base.nix` | add `boot.kernelPackages = pkgs.linuxPackages;` (D-03) | Pattern 2 |
| 12 | C1 | `hosts/pi5/configtxt.nix` | rewrite to `hardware.raspberry-pi.configtxt.settings` | Pattern 3 |
| 13 | C1 | `modules/raspberrypi/installer.nix`, `usb-installer.nix` | delete | D-08 |
| 14 | C1 | `Makefile` | remove `pi4-installer`/`pi5-installer`/`write-pi*` targets | D-08 |
| 15 | C1 | `etc/nix/nix.custom.conf:11-13` | remove `nixos-raspberrypi.cachix.org` entries | Runtime state inventory |
| 16 | C2 | `modules/gateway/grafana.nix` (`settings.security`) | add `secret_key` pinned to legacy value | Pitfall 1 — **blocking for firebat** |
| 17 | C2 | `hosts/ser8/impermanence.nix:172,178` | add `fsType = "none";` to both bind mounts | Pitfall 2 |
| 18 | C2 | `modules/automation/home-assistant.nix:286` | remove `mode = "storage";` | Pitfall 3 |
| 19 | C2 | `modules/automation/home-assistant.nix:58-69,447` | re-evaluate the `.storage/lovelace_resources` hack after deploy | Pitfall 3 |
| 20 | C3 | `flake.nix:44-47` | `home-manager` → `release-26.05` (+ update warning baseline) | Pitfall 11 |
| 21 | C3 | `flake.lock` | `nix flake update` for remaining inputs | D-09 |
| 22 | C4 | `modules/servers/tailscale.nix:19-20` | `unstable.tailscale` → `pkgs.tailscale`, drop comment | Pitfall 10 |
| 23 | C4 | `modules/media/sabnzbd.nix` | delete the sabnzbd overlay entirely | Pitfall 10 |
| 24 | C4 | `flake.nix:186,216` | delete the two stale tailscale comments | Pitfall 10 |
| 25 | C4 | `overlays/frigate-tflite-optional.nix` | re-justify or remove | Pitfall 5 |
| 26 | C5 | `scripts/smoketests/dns/` | delete (3 files) | D-15 |
| 27 | C5 | `deploy.yaml:25-30` | pi4 smoketests entry (pi5 uses the `"test"` placeholder as precedent) | D-15 |
| 28 | C5 | `scripts/smoketests/lib/services.sh` | skip guard for the pi4-DNS path | D-16 / Pitfall 9 |
| 29 | C5 | new `test-*.sh` × 3 | ZFS health, qBittorrent netns confinement, VAAPI transcode | D-14 |
| 30 | C5 | `CLAUDE.md:23` | update the sentence describing the Pi input strategy | doc accuracy |
| 31 | C5 | `.planning/PROJECT.md` | record FOUND-02 decision + pi4 "disconnected, pending retirement" | D-06 |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Pinning the legacy Grafana `secret_key` preserves decryptability of secrets already in `grafana.db`. Upstream's release note says this is "most likely OK" for a single-node instance; not tested on firebat. | Pitfall 1 | Alert email path breaks silently. Mitigate by firing a Grafana test notification post-switch. |
| A2 | Removing `lovelace.mode = "storage"` leaves the default HA dashboard UI-editable (HA's own default for the default dashboard is storage mode). | Pitfall 3 | Default dashboard becomes read-only or resets. UAT item. |
| A3 | The `.storage/lovelace_resources` tmpfiles hack becomes redundant under 26.05's auto `resource_mode = "yaml"` rather than actively harmful. | Pitfall 3 | Duplicate card registration. Verify visually after `make test-ser8`. |
| A4 | `pkgs.linuxPackages` on 26.05 boots both Pi boards headlessly (network, USB, NVMe root). Asserted by the BennyDeeDev template README and by the rpi5 module's explicit mainline support, not tested on this hardware. | Pattern 2 | Deferred reflash fails. No Phase 9 impact (no flashing). |
| A5 | `fileSystems."/persist"` on ser8 gets its `fsType` from disko by merge and needs no edit. | Pitfall 2 | Extra eval error, caught immediately by `make check`. Cheap. |
| A6 | The caddy-nix overlay is inert on aarch64 and does not break Pi evaluation when `mkSystem` applies it to the Pis. | Pattern 1 | Pi eval failure, caught by `make check`. |
| A7 | ZFS 2.3.8 on 26.05's default kernel imports the existing `rpool`/`backup` pools without a feature-flag upgrade prompt. | Runtime State Inventory | ZFS import warning or pool-version nag. The D-14 health smoketest is the detector. |
| A8 | Frigate 0.17.2 starts on ser8's existing Frigate config without a schema migration failure. Only the *overlay* compatibility was verified, not the config schema. | Pitfall 5 | Frigate fails to start post-switch. Covered by the existing Frigate smoketest gate in success criterion 4. |
| A9 | The `nixos-images` kexec entries can be relocated or dropped when `installerConfigurations` goes away without breaking `make aarch64-kexec` / `make provision`. | Standard Stack | A provisioning target breaks. Not exercised in normal operation; low blast radius, but the plan should state which way it went. |

## Open Questions

**Status: all four RESOLVED by the Phase 9 plan set (2026-08-16).** Each item below carries its disposition inline. Kept in place rather than deleted so the reasoning behind each disposition stays readable.

1. **(RESOLVED — deferred with the path recorded)** **Pi 5 sd-image on stable 26.05 — pre-decide the deferred path.**
   - *Disposition:* no image work happens in Phase 9 (D-07/D-08). Plan 09-05 Task 4 records recommendation (a) below as the intended path for the deferred reflash, so the deferred item is not re-researched from scratch.
   - *What we know:* `nixos-26.05`'s `sd-image-aarch64.nix` has no `[pi5]` filter, no `bcm2712-*` DTBs, and uses the split `u-boot-rpi3.bin`/`u-boot-rpi4.bin` layout. Master has all three. Pi 5 support merged to master 2026-07-03, after branch-off. The BennyDeeDev README's warning is therefore **confirmed still true on stable 26.05**. `[VERIFIED: direct diff of the module on both refs; PR #537862 metadata]`
   - *What's unclear:* which of three escape hatches to take when the deferred image work happens.
   - *Recommendation:* prefer **(a)** — import `nixos-hardware.nixosModules.raspberry-pi-5` into the bootstrap image config. `raspberry-pi/common/firmware.nix` contains `lib.optionalAttrs (options ? sdImage) { sdImage.populateFirmwareCommands = lib.mkForce "${lib.getExe imageInstallScript} ./firmware\n"; }` with the comment *"mkForce so we override (not merge with) sd-image-aarch64.nix, which also sets this and would clobber config.txt"* `[VERIFIED: raw.githubusercontent.com/NixOS/nixos-hardware/master/raspberry-pi/common/firmware.nix]`. That install script copies **all** vendor DTBs from `pkgs.raspberrypifw` plus `pkgs.ubootRaspberryPiAarch64` — supplying exactly the Pi 5 files stable's module lacks. And `ubootRaspberryPiAarch64` *does* exist in 26.05 `[VERIFIED: nixos-26.05/pkgs/misc/uboot/default.nix:752-756 → `ubootRaspberryPiAarch64 = buildUBoot { defconfig = "rpi_arm64_defconfig"; ... };`]`. Fallbacks: **(b)** build the bootstrap image from the retained `nixpkgs-unstable` input, matching the template literally; **(c)** wait for 26.11. Record (a) as the intended path so the deferred item is not re-researched from scratch.
   - *Not blocking Phase 9.*

2. **(RESOLVED — baseline capture is the phase's first action)** **Does `nix flake check` still pass with `installerConfigurations` gone — and does it pass at all?**
   - *Disposition:* plan 09-01 Task 1 captures the `make check` output on the untouched tree before any edit and commits it under the phase baseline directory, making criterion 1 falsifiable. Plan 09-02 Task 1 retains the output as a two-entry kexec attrset rather than removing it, so the non-standard-output question no longer arises.
   - *What we know:* `make check` runs `nix flake check`, `statix check`, a validation script, then per-host `--dry-run` builds `[VERIFIED: Makefile:141-150]`. `installerConfigurations` is a non-standard flake output.
   - *What's unclear:* whether `nix flake check` on 26.05's Nix version currently emits warnings about the non-standard output, and whether removing it changes `make check` behaviour.
   - *Recommendation:* run `make check` on the *unmodified* tree first and record the exact baseline output. Without that baseline, "make check passes" (criterion 1) is unfalsifiable. This should be the phase's first task.

3. **(RESOLVED — handed to Phase 10 with the guard in place)** **`.vofi` DNS ownership — flagged, not resolved here.**
   - *Disposition:* plan 09-03 Task 3 adds the `SKIP_VOFI_DNS` guard in the shared helper (the correct level, per Pitfall 9) and plan 09-05 Task 4 records the ownership question in PROJECT.md as an open item Phase 10 must answer before any household service is reachable by name.
   - Already a CONTEXT deferred item. Phase 9 only needs the skip guard (D-16). But note the coupling found in Pitfall 9: `test_service()` resolves *every* media domain through pi4. Once pi4 is retired, the fallback path becomes the only path — worth telling Phase 10.

4. **(RESOLVED — kept, via the option interface)** **Should `system.nixos.tags` survive at all on the Pis?**
   - *Disposition:* kept. Plan 09-02 Task 2 takes the recommendation below, declaring `homelab.raspberryPi.variant` in the reusable module with no default and setting it per host, which matches the repo's two-layer convention and fails loudly if a host forgets it.
   - *What we know:* it is cosmetic boot-menu labelling; the fork's bootloader surfaced it differently than extlinux does.
   - *Recommendation:* keep it with an explicit `piVersion` interface (Pitfall 6 Option B) — it costs ~5 lines and preserves the ability to tell generations apart on a headless box. But surfacing the choice to the user is cheap and this is exactly the kind of thing that gets carried forward unexamined.

## Environment Availability

Verified against the dev shell definition and `deploy.yaml`; the dev shell is the execution environment for this phase.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `nix` (flakes) | everything | ✓ | dev shell | — |
| `nixos-rebuild` | `make test-/switch-/dry-activate-` | ✓ | from `nixpkgs-unstable` devShell `[VERIFIED: flake.nix:331 lists `nixos-rebuild` in devShell buildInputs]` | — |
| `nixfmt` / `statix` | `make fmt`, `make check` | ✓ | devShell | — |
| `shellcheck` | new `test-*.sh` (D-14) | ✓ | devShell `[VERIFIED: flake.nix:342]` | — |
| `shfmt` | CLAUDE.md requires `shfmt -d` on changed shell scripts | ✗ | — | **Not in the devShell buildInputs list.** Add it, or run via `nix run nixpkgs#shfmt`. Flag for the planner — three new shell scripts are in scope. |
| `sops` / `age` / `ssh-to-age` | Grafana `secret_key` SOPS entry (Pitfall 1 Option A) | ✓ | devShell `[VERIFIED: flake.nix:335-337]` | Option B (literal) avoids SOPS entirely |
| `yq-go` | `make check`/`deploy.yaml` parsing | ✓ | devShell | — |
| SSH to ser8 (192.168.68.65) | D-05 activation + smoketests | assumed ✓ | — | none — blocks criterion 4 |
| SSH to firebat (192.168.68.63) | D-05 activation | assumed ✓ | — | none — blocks D-05 |
| SSH to pi4 (192.168.68.56) | — | **✗ physically disconnected** | — | D-06/D-13: local evaluation is the evidence. Not blocking. |
| SSH to pi5 (192.168.0.110) | optional dry-activate (D-13) | unknown — note the `192.168.0.x` subnet differs from every other host's `192.168.68.x` `[VERIFIED: deploy.yaml:33]` | — | D-13 says "if reachable"; fall back to local eval |
| aarch64 build capability | Pi toplevel `--dry-run` | ✓ for `--dry-run` (evaluation only) | — | A real aarch64 *build* would need `boot.binfmt.emulatedSystems` or a remote builder. D-13 scopes to dry-run, so not needed. |

**Missing dependencies with no fallback:** none.

**Missing dependencies with fallback:** `shfmt` (use `nix run nixpkgs#shfmt` or add to the devShell — recommend adding, since CLAUDE.md mandates it).

**Note on the pi5 subnet:** `192.168.0.110` vs everything else on `192.168.68.0/22`. Either pi5 is on a different network segment or the entry is stale. Worth a `ping` before planning any pi5 on-host step.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash smoketests + `nix` evaluation. No unit-test framework in the repo. |
| Config file | `deploy.yaml` (one `smoketests` entry per host) `[VERIFIED: deploy.yaml — ser8 → `./scripts/smoketests/media/all.sh`, firebat → `./scripts/smoketests/gateway/all.sh`, pi4 → `./scripts/smoketests/dns/all.sh`, pi5 → `"test"`]` |
| Quick run command | `nix flake check` (eval gate, seconds) |
| Full suite command | `make check` then `make smoketests-<host>` |
| Helper libs | `scripts/lib/all.sh` (sources logging/cleanup/yq/ssh/prompt), `scripts/smoketests/lib/services.sh` |

### Phase Requirements → Test Map

| Req / Criterion | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 / SC1 | Flake evaluates on 26.05 | eval | `make check` | ✅ |
| FOUND-01 / SC1 | Each host dry-activates | eval+activation preview | `make dry-activate-ser8` … ×4 | ✅ |
| FOUND-02 / SC2 | pi4 toplevel builds | eval | `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` | ✅ |
| FOUND-02 / SC2 | pi5 toplevel builds | eval | same for pi5 | ✅ |
| FOUND-02 / SC2 | Bootloader actually moved upstream | eval assertion | `nix eval '.#nixosConfigurations.pi4.config.boot.loader.generic-extlinux-compatible.enable'` | ❌ **Wave 0** — new `scripts/validation/test-pi-bootloader.sh` |
| FOUND-02 / SC2 | Mainline kernel override held (D-03) | eval assertion | `nix eval --raw '.#nixosConfigurations.pi5.config.boot.kernelPackages.kernel.pname'` → `linux` | ❌ **Wave 0** — same script |
| SC3 | `services.actual` 26.05 options present | eval assertion | `nix eval '.#nixosConfigurations.ser8.options.services.actual.user.type.name'` | ❌ **Wave 0** — new `scripts/validation/test-actual-module.sh` |
| SC4 | Media services reachable + permissions | smoke (ssh) | `make smoketests-ser8` | ✅ `scripts/smoketests/media/all.sh` |
| SC4 | Frigate healthy | smoke | — | ⚠️ **Gap** — `modules/automation/frigate.nix` exists but there is **no** `scripts/smoketests/` entry for Frigate. SC4 names Frigate explicitly. |
| SC4 | Home Assistant healthy | smoke | — | ⚠️ **Gap** — same; no HA smoketest exists. SC4 names HA explicitly. |
| D-14 | ZFS pool health | smoke | `zpool status -x` on ser8 | ❌ **Wave 0** |
| D-14 | qBittorrent confined to VPN netns | smoke | netns egress-IP check | ❌ **Wave 0** — `scripts/smoketests/nordvpn/test-netns.sh` and `test-anonymity.sh` are close prior art |
| D-14 | AMD VAAPI transcode works | smoke | `vainfo` / Jellyfin transcode probe | ❌ **Wave 0** |
| Pitfall 1 | Grafana can decrypt existing secrets | manual/UAT | Grafana test-notification | ❌ manual-only — decryption failure surfaces only on send |
| Pitfall 3 | Camera card renders once | manual/UAT | load the cameras dashboard | ❌ manual-only — visual |

### Sampling Rate

- **Per commit (D-09 staging):** `make check`
- **Per host activation:** `make dry-activate-HOST` → `make test-HOST` → `make smoketests-HOST` → `make switch-HOST`
- **Phase gate:** `make check` green on all four hosts + ser8 and firebat smoketests green + the two manual UAT items above confirmed

### Wave 0 Gaps

- [ ] `scripts/validation/test-pi-bootloader.sh` — asserts extlinux enabled and `kernel.pname == "linux"` on both Pis; covers FOUND-02 / SC2. Wire into `make check` alongside the existing `test-nzbget-permissions.sh` `[VERIFIED: Makefile:144]`.
- [ ] `scripts/validation/test-actual-module.sh` — asserts `options.services.actual.user` exists and `settings.dataDir` resolves; covers SC3. Also `make check`-wired, since it is a pure eval check needing no hardware.
- [ ] `scripts/smoketests/media/test-zfs-health.sh` — D-14.
- [ ] `scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh` — D-14; add to `nordvpn/all.sh`.
- [ ] `scripts/smoketests/media/test-vaapi.sh` — D-14.
- [ ] **Frigate and Home Assistant smoketests** — SC4 requires them and they do not exist. Either write them (they become part of D-14's spirit) or the plan must state which existing check stands in. **The planner must resolve this — as written, SC4 cannot be satisfied by any existing automated test.**
- [ ] `deploy.yaml` fan-out decision: ser8's single `smoketests` entry currently points only at `media/all.sh`, so nordvpn/frigate/HA tests are not reachable through `make smoketests-ser8`. `.planning/research/STACK.md` already flagged this ("`deploy.yaml` allows only **one** smoketest entry per host"). Introduce `scripts/smoketests/ser8/all.sh` that fans out, or extend `media/all.sh`.
- [ ] Baseline capture: record `make check` output on the unmodified 25.11 tree before any edit (Open Question 2).

## Security Domain

`security_enforcement` is not set in `.planning/config.json`, so it is enabled by default.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface changes. Grafana admin auth is unchanged (`$__file{}` from SOPS). |
| V3 Session Management | no | — |
| V4 Access Control | no | No new exposure. No firewall ports opened. Tailscale/LAN posture unchanged. |
| V5 Input Validation | no | No user input handled. |
| V6 Cryptography | **yes** | `services.grafana.settings.security.secret_key` is a data-encryption key. Pinning it to a published constant is a **deliberate, documented compatibility trade-off**, not a default. It must be recorded as such. |
| V7 Error Handling / Logging | marginal | Pitfall 1's failure mode is a decryption error that surfaces only at send time, not at deploy. Argues for the post-switch test-notification check. |
| V14 Configuration | **yes** | Supply chain: removing a third-party nixpkgs fork and its cachix substituter is a net reduction in trusted-input surface. Moving off an EOL channel restores security backports — this is the milestone's stated security rationale. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Running an EOL channel with no security backports | Elevation of Privilege / Tampering | The bump itself. 25.11 reached EOL 2026-06-30 per the milestone research. |
| Third-party binary cache as a trusted substituter | Tampering | Removing `nixos-raspberrypi.cachix.org` from both `flake.nix` `nixConfig` and `etc/nix/nix.custom.conf`. A `nixConfig.extra-trusted-public-keys` entry is a standing trust grant; deleting it is a real hardening win, not just cleanup. |
| Encryption key committed in plaintext | Information Disclosure | Pitfall 1 Option A (SOPS). The value is a public constant so the practical exposure is nil, but CLAUDE.md forbids plaintext credentials in the repo and the SOPS route costs one entry. |
| SSH public key baked into an installer image | — | `modules/raspberrypi/installer.nix` embeds an RSA key. It is being deleted; the deferred bootstrap image should use ed25519 (the template's own pattern) and disable password auth + root login, as `modules/pi5-common.nix` does. |
| Secret leakage into the Nix store via config rendering | Information Disclosure | Unchanged patterns: Grafana `$__file{}`, sops-nix `EnvironmentFile`. 26.05's `services.actual` `settings` freeform submodule supports `_secret` via `genJqSecretsReplacementSnippet` (materialised to `/run/actual/config.json`) — relevant to Phase 12, noted here since SC3 touches the module. |

**No new attack surface is introduced by this phase.** The net security effect is positive: supported channel + one fewer third-party nixpkgs fork + one fewer trusted cache.

## Project Constraints (from CLAUDE.md)

Directives extracted from `./CLAUDE.md` that constrain this phase's plan.

| Directive | Phase 9 implication |
|-----------|---------------------|
| `deploy.yaml` is the source of truth for addresses, users, tags, smoketest commands | pi4's `smoketests` entry must be updated in `deploy.yaml`, not just by deleting the scripts (D-15). |
| Prefer small modules imported through the relevant directory's `default.nix` | pi4/pi5 need `default.nix` files if `mkSystem` is used as-is (Pattern 1, item 9). |
| Format with `nixfmt-rfc-style`; do not hand-align against formatter output | Run `make fmt` before each commit. |
| Keep module filenames lowercase kebab-case | New smoketest files: `test-zfs-health.sh`, `test-vaapi.sh`, `test-qbittorrent-confinement.sh`. |
| Preserve `SPDX-License-Identifier: GPL-3.0-or-later` headers | Every new `.sh` and `.nix` file needs the header; the existing smoketests all carry it. |
| New Bash scripts start with `set -euo pipefail`; run `shellcheck` and `shfmt -d` | Three new scripts. Note `shfmt` is **not** in the devShell (see Environment Availability). |
| `make test-HOST` is safer than `switch`; interactive deploys prompt by default; `NO_CONFIRM=true` only for intentional non-interactive use | Matches D-05 exactly. Do not set `NO_CONFIRM`. |
| `rollback-HOST` is a placeholder and must not be presented as functional | The plan's rollback story for ser8/firebat is `make test-HOST` (reverts on reboot) plus the systemd-boot generation menu — **not** `make rollback-HOST`. Say so explicitly. |
| Add or update smoketests when changing deployed services, networking, DNS, gateway, monitoring, or media automation | This phase changes all six. D-14's three tests are the floor, not the ceiling — see the Frigate/HA gap in Wave 0. |
| Keep area entry points named `all.sh` when referenced by `deploy.yaml` | Any ser8 fan-out must be `scripts/smoketests/<area>/all.sh`. |
| Treat warnings from formatters, linters, evaluators, and tests as failures to resolve | The HA `lovelace.mode` deprecation warning must be fixed, not accepted. The HM mismatch warning disappearing must be recorded as a baseline change (Pitfall 11). |
| Never commit plaintext credentials | Argues for Pitfall 1 Option A (SOPS) over Option B (literal key). |
| Host-specific encrypted data in `secrets/<host>.yaml` | A `grafana_secret_key` entry belongs in `secrets/firebat.yaml`. |
| Short scoped imperative commit subjects, one logical change per commit | D-09's five commits map cleanly: `flake: bump nixpkgs to 26.05 and migrate Pis upstream`, `gateway: pin grafana secret_key`, etc. |
| Do not push directly to `main`; PRs identify affected hosts/modules, validation performed, and required deployment or secret steps | The PR must call out the new SOPS secret and the ser8-then-firebat activation order. |
| Use `sb` for structure-aware exploration before reading large files | Applied during this research. |
| Use `treehouse get --lease` for isolated worktrees | Relevant if plans run in parallel. |
| **Replace, don't deprecate** | Directly endorses D-15 (delete the pi4 DNS tests) and argues for deleting the sabnzbd overlay outright rather than leaving a commented-out version. |

## Sources

### Primary (first-party source read directly at named refs — HIGH)

- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/web-apps/actual.nix` — full module; `user`/`group`/`settings.dataDir`/`serverFiles`/`userFiles`/`ReadWritePaths`
- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/actual.nix` — the hard-coded `dataDir` and unconditional `DynamicUser` it replaces
- `raw.githubusercontent.com/NixOS/nixpkgs/{nixos-25.11,nixos-26.05}/nixos/modules/tasks/filesystems.nix` — `fsType` default removal; `boot.supportedFilesystems` type
- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/doc/manual/release-notes/rl-2605.section.md` — full Backward Incompatibilities section
- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/home-automation/home-assistant.nix` — `lovelace.mode` warning, `resource_mode` / `dashboards.nixos-lovelace` options
- `raw.githubusercontent.com/NixOS/nixpkgs/{nixos-26.05,master}/nixos/modules/installer/sd-card/sd-image-aarch64.nix` — the Pi 5 gap on stable
- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/system/boot/loader/generic-extlinux-compatible/default.nix` — option set
- `raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/misc/uboot/default.nix` — `ubootRaspberryPiAarch64` present
- `raw.githubusercontent.com/NixOS/nixos-hardware/master/{flake.nix, raspberry-pi/4/default.nix, raspberry-pi/5/default.nix, raspberry-pi/common/{default,config-txt,config-txt-defaults,firmware,kernel}.nix}` — the entire upstream Pi story
- `raw.githubusercontent.com/nix-community/home-manager/release-26.05/modules/home-environment.nix` — release-mismatch warning mechanism
- `raw.githubusercontent.com/blakeblackshear/frigate/v0.17.2/frigate/**` — five tflite import sites vs the overlay's guards
- `raw.githubusercontent.com/vincentbernat/caddy-nix/main/flake.nix`, `raw.githubusercontent.com/Sveske-Juice/declarative-jellyfin/main/flake.nix` — third-party input shape
- `api.github.com/repos/NixOS/{nixpkgs,nixos-hardware}` — branch existence, commit history per path, PR #537862 metadata
- Package versions read from `pkgs/by-name/**/package.nix` and `pkgs/servers/home-assistant/default.nix` at `nixos-25.11` and `nixos-26.05`: frigate, tailscale, par2cmdline-turbo, jellyfin, home-assistant, sabnzbd, adguardhome, caddy, grafana, mosquitto, zfs

### Repository files (read in full this session — HIGH)

Read via the `Read` tool: `flake.nix`, `modules/raspberrypi/base.nix`, `deploy.yaml`, `.planning/phases/09-.../09-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/research/STACK.md`.

Read in full via `cat`/`sed` (full-content reads of the source of truth, quoted verbatim above): `hosts/{pi4,pi5}/*.nix`, `hosts/ser8/configuration.nix` (relevant ranges), `hosts/ser8/impermanence.nix` (relevant ranges), `modules/raspberrypi/{installer,usb-installer}.nix`, `modules/automation/home-assistant.nix` (relevant ranges), `modules/gateway/grafana.nix` (relevant ranges), `modules/servers/tailscale.nix`, `modules/media/sabnzbd.nix` (relevant range), `overlays/frigate-tflite-optional.nix`, `home-manager/flake.nix`, `etc/nix/nix.custom.conf`, `Makefile` (relevant ranges), `scripts/smoketests/{media,dns,gateway}/all.sh`, `scripts/smoketests/lib/services.sh`, `scripts/smoketests/nordvpn/test-netns.sh`, `flake.lock` (via `jq`).

### Secondary (MEDIUM)

- `github.com/BennyDeeDev/nixos-pi5-template` — `README.md`, `flake.nix`, `modules/pi5-common.nix`, `images/pi5-bootstrap.nix`, `hosts/pi5-host-1.nix` (fetched via GitHub contents API). User-referenced pattern; its Pi 5 / stable-channel claim was independently re-verified against nixpkgs source and holds.
- `.planning/research/SUMMARY.md`, `.planning/research/STACK.md` — milestone research. STACK.md's LOW-confidence rating on the `26.05 × nixos-raspberrypi` interaction is **superseded** by D-01 (the fork is removed, so the interaction no longer exists).

### Tertiary (LOW)

- None. Every claim in this document traces to first-party source or a repo file read this session. The `[ASSUMED]` items are collected in the Assumptions Log and are all *predictions about runtime behaviour on live hosts*, which cannot be resolved by reading.

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|------|-------|--------|
| Flake input set + versions | HIGH | Branch existence confirmed via GitHub API; every version read from `package.nix` at the named ref |
| 26.05 breaking changes affecting this repo | HIGH | Release notes read in full, then each candidate cross-checked against the actual repo file and the actual module source on both refs |
| Pi migration mechanics (nixos-hardware option paths, kernel override, config.txt schema) | HIGH | All four relevant module files read in full from `nixos-hardware` master |
| Pi 5 sd-image gap on stable 26.05 | HIGH | Direct diff of `sd-image-aarch64.nix` between `nixos-26.05` and `master`, plus PR merge-date metadata |
| `services.actual` 26.05 vs 25.11 (SC3) | HIGH | Both module versions read in full |
| Repo migration targets (file:line) | HIGH | Repo files read in full and quoted verbatim |
| Runtime outcomes on live hosts (Grafana decryption, HA resources, Frigate 0.17 config, ZFS import) | MEDIUM | Predictions from source reading; resolvable only by deploying. Collected in the Assumptions Log with detection strategies. |
| Validation coverage | MEDIUM | Two genuine gaps found (no Frigate smoketest, no HA smoketest) that make SC4 unsatisfiable as written — flagged for the planner rather than silently assumed away |

**Research date:** 2026-08-16
**Valid until:** 2026-09-15 (~30 days). `nixos-26.05` receives backports continuously and `nixos-hardware`'s `raspberry-pi/common/` is under active development (three commits in the six weeks before this research) — re-verify the nixos-hardware option paths if planning slips past mid-September.
