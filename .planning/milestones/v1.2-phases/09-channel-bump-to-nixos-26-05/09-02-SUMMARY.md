---
phase: 09-channel-bump-to-nixos-26-05
plan: 02
subsystem: infra
tags: [nix, flake, raspberry-pi, nixos-hardware, extlinux, supply-chain, cachix]

requires:
  - phase: 09-01
    provides: "nixpkgs pinned to nixos-26.05, the failure-propagating make check target, and the services.resolved settings.Resolve migration that made the Pi hosts fail to evaluate"
provides:
  - "Both Pi hosts constructed by the single mkSystem helper against upstream nixpkgs + nixos-hardware"
  - "hosts/pi4/default.nix and hosts/pi5/default.nix directory entry points"
  - "options.homelab.raspberryPi.variant, replacing the fork-only boot.loader.raspberryPi read"
  - "Mainline kernel forced over nixos-hardware's uncached vendor default on both Pis"
  - "pi5 config.txt on the upstream configtxt schema, with audio=on re-listed"
  - "scripts/validation/test-pi-bootloader.sh wired into make check"
  - "nvmd/nixos-raspberrypi, its bundled nixpkgs fork, and its trusted cachix key removed from the flake"
affects: [09-04, 09-05, 09-07, pi-reflash, bootstrap-image]

actuals:
  tokens: 8100
  tasks: 3
  commits: 2

tech-stack:
  added:
    - "nixos-hardware @ ff17823245ab9ff7bcae6acf950bd89cba82c38c (2026-08-16), deliberately pinned"
  patterns:
    - "Reusable module declares the option interface, host default.nix sets the policy (homelab.raspberryPi.variant)"
    - "Pure-eval validation scripts as permanent make check gates, no hardware required"

key-files:
  created:
    - hosts/pi4/default.nix
    - hosts/pi5/default.nix
    - scripts/validation/test-pi-bootloader.sh
  modified:
    - flake.nix
    - flake.lock
    - modules/raspberrypi/base.nix
    - hosts/pi5/configtxt.nix
    - modules/dns/adguard-home.nix
    - Makefile
    - etc/nix/nix.custom.conf
    - scripts/nixos-rebuild.sh
    - CLAUDE.md

key-decisions:
  - "Pinned nixos-hardware to ff17823245ab (2026-08-16) rather than following master, because raspberry-pi/common/ is under active development and a silent change there would alter Pi boot behaviour on an unrelated flake update"
  - "Retained the two kexec entries of installerConfigurations and the nixos-images input; only the two fork-built sd-image entries were dropped"
  - "pi5/default.nix imports configuration.nix and configtxt.nix only — configuration.nix already imports disko-config.nix, so listing it again would be a duplicate import"
  - "Dropped the two serial-console UART settings from pi5's config.txt entirely rather than porting them, per the documented Pi 5 ghost-input boot hazard"
  - "Did not bump declarative-jellyfin to unblock make check — that input is plan 09-04's scope and crossing the boundary would make both plans unbisectable"

patterns-established:
  - "Option interface in the reusable module, policy in the host: options.homelab.raspberryPi.variant is declared in modules/raspberrypi/base.nix with no default so an unset variant fails loudly at eval"
  - "Plain assignment to beat nixos-hardware's lib.mkDefault, with the reason (uncached vendor kernel) recorded inline"

requirements-completed: [FOUND-02]

coverage:
  - id: D1
    description: "Both Pi hosts build from upstream nixpkgs and nixos-hardware with no fork input anywhere in the lock"
    requirement: FOUND-02
    verification:
      - kind: automated_ui
        ref: "jq -e '[.nodes[] | select(.locked.owner == \"nvmd\")] | length == 0' flake.lock && grep -c nvmd flake.lock"
        status: pass
      - kind: integration
        ref: "nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel' (and pi5)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Extlinux and the mainline-kernel override are permanently gated in make check"
    requirement: FOUND-02
    verification:
      - kind: integration
        ref: "./scripts/validation/test-pi-bootloader.sh"
        status: pass
    human_judgment: false
  - id: D3
    description: "pi5's config.txt renders the three intended dtparam lines under the upstream schema, with no serial console under the [pi5] filter"
    requirement: FOUND-02
    verification:
      - kind: integration
        ref: "nix eval --raw '.#nixosConfigurations.pi5.config.hardware.raspberry-pi.configtxt.file.text'"
        status: pass
    human_judgment: false
  - id: D4
    description: "The third-party trusted binary cache is revoked on the developer machine"
    verification:
      - kind: integration
        ref: "make update-nix-conf && grep -c cachix /etc/nix/nix.custom.conf"
        status: fail
    human_judgment: true
    rationale: "The repository declarations are clean, but applying them needs root and this session has no elevation. Only the user can run make update-nix-conf and confirm the installed daemon file."
  - id: D5
    description: "make check passes for all four hosts (FOUND-01)"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "make check"
        status: fail
    human_judgment: false
  - id: D6
    description: "Per-host FOUND-02 evidence reconciled against the roadmap's literal all-hosts-dry-activate wording"
    requirement: FOUND-02
    verification: []
    human_judgment: true
    rationale: "Whether the recorded evidence levels are an acceptable substitute for literal dry-activate on the two Pi hosts is a judgment call the user owns, not something a command can assert."

duration: 25min
completed: 2026-08-17
status: complete
---

# Phase 09 Plan 02: Raspberry Pi Migration to Upstream Summary

**Both Raspberry Pi hosts now build from upstream nixpkgs 26.05 and pinned nixos-hardware through the same `mkSystem` helper the x86 hosts use, with the `nvmd` fork, its bundled nixpkgs fork, and its trusted cachix key gone from the flake.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-17T07:27Z
- **Completed:** 2026-08-17T07:52Z
- **Tasks:** 3 of 3
- **Files modified:** 14 (3 created, 9 modified, 2 deleted)

## Accomplishments

- The flake has exactly one system-construction helper. `mkPiSystem` is gone and both Pi hosts are ordinary `mkSystem` calls with `system = "aarch64-linux"`, `useX86Modules = false`, `usePiModules = true`.
- The lock carries no node owned by `nvmd` and the raw lock file contains no occurrence of that string. Four nodes left: `nixos-raspberrypi`, its `nixpkgs_2` fork, its `nixos-images_2`, and `argononed`.
- Both Pi toplevels dry-run build clean — the state 09-01 left them in (failing on `services.resolved.settings.Resolve`, which the fork's nixpkgs did not have) is resolved.
- The mainline-kernel override holds on both boards, so no build will fall through to the uncached vendor `linux-rpi` kernel.
- The third-party cachix substituter and trusted public key are gone from `flake.nix` and `etc/nix/nix.custom.conf`. **They are still present in the installed `/etc/nix/nix.custom.conf`** — see Issues.

## Task Commits

1. **Task 1: Collapse both Pi hosts onto mkSystem and migrate every fork-only option** — `b0e9a85` (feat)
2. **Task 2: Remove the fork's installers, build targets, and trusted cache** — `ecb12c2` (chore)
3. **Task 3: Establish per-host evidence and reconcile the roadmap criterion** — no code changes; evidence recorded in this SUMMARY

## Files Created/Modified

**Created**
- `hosts/pi4/default.nix` — directory entry point so `mkSystem`'s `./hosts/pi4` import resolves; sets `homelab.raspberryPi.variant = "4"`
- `hosts/pi5/default.nix` — same for pi5, and pulls `configtxt.nix` out of the flake's per-host modules list into the host directory
- `scripts/validation/test-pi-bootloader.sh` — four pure-eval assertions (extlinux + `kernel.pname == "linux"` on each Pi), wired into `make check`

**Modified**
- `flake.nix` — fork input, `mkPiSystem`, the `nixConfig` cachix block, and the two sd-image installer entries removed; `nixos-hardware` bumped and added to the outputs arg list; both Pi call sites rewritten
- `flake.lock` — 7 nodes removed, `nixos-hardware` re-locked
- `modules/raspberrypi/base.nix` — restructured into `{ options; config; }`, fork-only bootloader read replaced, mainline kernel forced
- `hosts/pi5/configtxt.nix` — rewritten to `hardware.raspberry-pi.configtxt.settings.all`
- `modules/dns/adguard-home.nix` — `networking.resolvconf.enable = false` for a new 26.05 assertion (see Deviations)
- `Makefile` — sd-image/installer/device-write targets removed, Pi bootloader validation wired into `check`, help text corrected
- `etc/nix/nix.custom.conf` — cachix entries removed from all three `extra-*` lines
- `scripts/nixos-rebuild.sh` — fork-era recovery banner and its dead call deleted; shellcheck source directive added
- `CLAUDE.md` — three now-false statements corrected

**Deleted**
- `modules/raspberrypi/installer.nix`, `modules/raspberrypi/usb-installer.nix`

## The nixos-hardware pin

Pinned to **`ff17823245ab9ff7bcae6acf950bd89cba82c38c`, committed 2026-08-16T08:07:12Z** (`raspberry-pi: add ordered config.txt overlays`, PR #1947). This was master head at plan time and matches the revision RESEARCH.md recommended pinning at or after.

The previous pin `daa628a725ab` was from 2025-05-30 and had zero consumers in the tree; both the `raspberry-pi-5` board module and `hardware.raspberry-pi.firmware` postdate it.

Re-locking added one transitive node: `nixos-hardware/nixpkgs`, a `releases.nixos.org` unstable tarball. It is used only by nixos-hardware's own checks — the board modules take `pkgs` from this flake's `nixpkgs`.

## The kexec decision (recorded explicitly, per plan)

`installerConfigurations` now has exactly two entries, `aarch64-kexec` and `x86_64-kexec`, and the **`nixos-images` input is retained**. Those entries are what `make aarch64-kexec` and the nixos-anywhere provisioning flow consume, and they never depended on the removed fork. RESEARCH.md flagged the kexec fate as an open assumption; this resolves it.

The two fork-built sd-image entries were dropped along with the two installer modules that fed them.

## The rendered pi5 config.txt

Produced by `nix eval --raw '.#nixosConfigurations.pi5.config.hardware.raspberry-pi.configtxt.file.text'`:

```
[all]
arm_boost=1
camera_auto_detect=1
disable_fw_kms_setup=1
disable_overscan=1
display_auto_detect=1
dtparam=audio=on
dtparam=pciex1=on
dtparam=pciex1_gen=3
enable_uart=1
max_framebuffers=2

[all]
[cm4]
otg_mode=1

[all]
[pi5]
enable_uart=0

[all]
dtoverlay=vc4-kms-v3d
dtoverlay=

[all]
[cm5]
dtoverlay=dwc2
dtparam=dr_mode=host
dtoverlay=
```

Checked by eye against the pre-migration values:

| Pre-migration (fork schema) | Post-migration | Verdict |
|---|---|---|
| `base-dt-params.pciex1 = "on"` | `dtparam=pciex1=on` | carried over |
| `base-dt-params.pciex1_gen = "3"` | `dtparam=pciex1_gen=3` | carried over |
| (implicit upstream default `audio=on`) | `dtparam=audio=on` | **re-listed explicitly** — the normal-priority list replaces upstream's `lib.mkDefault [ "audio=on" ]` rather than merging, so omitting it would have silently dropped audio |
| `options.enable_uart = true` | absent from our file | dropped deliberately |
| `options.uart_2ndstage = true` | absent | dropped deliberately |

The `[all] enable_uart=1` line is upstream's own default; the `[pi5] enable_uart=0` line immediately below is upstream turning it back off under the board filter, which is the documented behaviour (the Pi 5 has a dedicated debug UART and the mini UART feeds ghost input into boot). **There is no serial-console enablement under the `[pi5]` filter**, which is what the plan asked to confirm.

The trailing empty `dtoverlay=` lines are upstream's overlay-terminator idiom, not a rendering defect.

## The trusted cache — NOT fully revoked

The third-party cachix entry was declared in three places. Two are clean; the third, which is the only one that actually grants anything, is unchanged.

| Location | Before | After | Proof |
|---|---|---|---|
| `flake.nix` `nixConfig` block | substituter + trusted key | removed | `grep -c cachix flake.nix` → `0` |
| `etc/nix/nix.custom.conf` (repository source) | on all 3 `extra-*` lines | removed, official cache retained | `grep -c cachix` → `0`; `grep -c cache.nixos.org` → `3` |
| `/etc/nix/nix.custom.conf` (installed, what the daemon reads) | substituter + trusted-substituter + trusted key | **UNCHANGED** | `grep -c cachix /etc/nix/nix.custom.conf` → `3` |

`make update-nix-conf` was run and failed:

```
$ make update-nix-conf
Backing up files...
cp: cannot stat '/etc/nix/machines': No such file or directory
'./etc/nix/machines' -> '/etc/nix/machines'
cp: cannot create regular file '/etc/nix/machines': Operation not permitted
make[1]: *** [Makefile:130: update-nix-conf] Error 1
```

It aborted on its first `cp`, before ever touching `nix.custom.conf`. Elevation was then attempted and is unavailable — `sudo` itself is blocked by this session's seatbelt sandbox:

```
$ sudo -n true
/nix/store/.../bin/bash: line 1: /usr/bin/sudo: Operation not permitted
```

Per the plan's transparency prohibition, **the cache is NOT reported as removed.** The installed daemon configuration still carries `nixos-raspberrypi.cachix.org` as a substituter, a trusted substituter, and a trusted public key, meaning that cache can still supply signed store paths to this machine. Threat T-09-06 remains open.

Post-apply contents of the installed file, verbatim as they still stand:

```
extra-substituters = https://cache.nixos.org https://nixos-raspberrypi.cachix.org
extra-trusted-substituters = https://cache.nixos.org https://nixos-raspberrypi.cachix.org
extra-trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
```

**Required user action:** run `sudo make update-nix-conf` (or copy `etc/nix/nix.custom.conf` to `/etc/nix/` and `launchctl kickstart -k system/systems.determinate.nix-daemon`), then confirm `grep -c cachix /etc/nix/nix.custom.conf` outputs `0`.

Note also a pre-existing defect in that target, logged as deferred rather than fixed here: it runs its `cp` commands without `sudo`, so it can only ever succeed when invoked as root, and its first line `cp -v /etc/nix/machines /etc/nix/machines.old` fails on a machine that has no `/etc/nix/machines`.

## Four-host evidence table and roadmap reconciliation

ROADMAP Phase 9 Success Criterion 1 says every host dry-activates without evaluation errors. The repository's `dry-activate` is a **remote** operation: `scripts/nixos-rebuild.sh` resolves an SSH host, creates a remote build directory over SSH, and passes `--build-host`/`--target-host`. It therefore cannot be performed against a board that does not answer. The criterion is **not met literally by either Pi**, and that gap is named here rather than redefined away.

| Host | Evidence level | Command that produced it | Meets criterion literally? |
|---|---|---|---|
| ser8 | Real remote activation preview | `make dry-activate-ser8` (plan 09-01) | Yes — but see the outstanding-blocker note below |
| firebat | Real remote activation preview | `make dry-activate-firebat` (plan 09-01) | Yes — same note |
| pi4 | **Local evaluation only** | `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` + `./scripts/validation/test-pi-bootloader.sh` | **No** — host is physically disconnected |
| pi5 | **Local evaluation only** (fallback branch of D-13) | `nix build --dry-run '.#nixosConfigurations.pi5.config.system.build.toplevel'` + `./scripts/validation/test-pi-bootloader.sh` | **No** — host did not answer any probe |

Carrying forward from 09-01 rather than restating it as settled: that plan's own SUMMARY records the ser8 and firebat activation previews as **outstanding**, blocked on jellyfin and on an uncached torch source build. This plan does not re-run or re-verify them; it reports what 09-01 recorded and defers the x86 half to 09-04/09-07.

### pi4 evidence (separate entry)

pi4's bar under D-13 is local evaluation, because the host is physically disconnected and pending retirement.

- `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` → exit 0. Plan: `169 derivations will be built`, `1027 paths will be fetched (2.2 GiB download, 6.0 GiB unpacked)`.
- `boot.loader.generic-extlinux-compatible.enable` → `true`
- `boot.kernelPackages.kernel.pname` → `"linux"`
- `system.nixos.tags` → `["raspberry-pi-4","extlinux","6.18.44"]`
- `system.stateVersion` → `24.11` (D-12 datapoint, unchanged by this plan)
- `git diff --stat hosts/pi4/hardware-configuration.nix` across the whole plan → empty; the hard-coded UUIDs are byte-identical.

**No boot was attempted, and none could be.** For completeness, SSH to pi4's deploy.yaml address was also tried and timed out: `ssh -o BatchMode=yes -o ConnectTimeout=5 bdhill@192.168.68.56 true` → `Operation timed out` (exit 255) at 2026-08-17T07:49:23Z. This confirms rather than discovers the disconnection.

### pi5 evidence (separate entry) — D-13 conditional resolved to the FALLBACK branch

pi5's address and user were read from `deploy.yaml`, not typed: `targetHost: 192.168.0.110`, `targetUser: nixos`, `buildOnTarget: true`.

**Subnet finding:** pi5 is the only host in `deploy.yaml` on `192.168.0.0/24`. ser8 (`.68.65`), firebat (`.68.63`), and pi4 (`.68.56`) are all on `192.168.68.0/22`. Given the probe results below, **that entry appears stale, not a live network fact.** The `targetUser: nixos` value is corroborating evidence — `nixos` is the installer's default account, which suggests the entry was written at first provisioning and never refreshed.

Probes, all at 2026-08-17T07:49Z:

| # | Command | Result |
|---|---|---|
| 1 | `ping -c 3 -t 5 192.168.0.110` | `ping: unsupported packet type: 5` (exit 1) — **not attributable**: the identical failure occurs against ser8, which is live, so ICMP is unusable from this sandbox rather than telling us anything about pi5 |
| 2 | `ssh -o BatchMode=yes -o ConnectTimeout=5 nixos@192.168.0.110 true` | `ssh: connect to host 192.168.0.110 port 22: Operation timed out` (exit 255) |
| 3 | `ssh -o BatchMode=yes -o ConnectTimeout=5 nixos@pi5.local true` | `Could not resolve hostname pi5.local` (exit 255) |
| 4 | `ssh -o BatchMode=yes -o ConnectTimeout=8 nixos@pi5.shad-bangus.ts.net true` | `Could not resolve hostname` (exit 255) — the Tailscale fallback the rebuild wrapper would itself take |

Because ICMP was unusable, an SSH **control** was run to make probe 2 attributable: `ssh -o BatchMode=yes -o ConnectTimeout=5 bdhill@192.168.68.65 true` (ser8) → exit 0. SSH works from this session; pi5 specifically does not answer.

**Branch taken: the fallback.** `make dry-activate-pi5` was **not** run, because it would have failed at the SSH step. pi5 falls back to the same local-evaluation evidence pi4 has:

- `nix build --dry-run '.#nixosConfigurations.pi5.config.system.build.toplevel'` → exit 0. Plan: `162 derivations will be built`, `911 paths will be fetched (2.1 GiB download, 5.8 GiB unpacked)`.
- `boot.loader.generic-extlinux-compatible.enable` → `true`
- `boot.kernelPackages.kernel.pname` → `"linux"`
- `system.nixos.tags` → `["raspberry-pi-5","extlinux","6.18.44"]`
- `system.stateVersion` → `24.11`
- Rendered config.txt read and confirmed (above).

The acceptance check `ssh <pi5> 'ls /nix/var/nix/profiles/'` was conditional on reachability and is therefore not applicable. No generation could have been created: no activation command was issued to either Pi.

## Decisions Made

See `key-decisions` in the frontmatter. The two worth restating:

1. **nixos-hardware is pinned, not tracking master.** `raspberry-pi/common/` changed as recently as the pinned commit itself. A `nix flake update` must not be able to silently change how these boards boot.
2. **`make check` was left red rather than fixed here.** The only remaining failure is `declarative-jellyfin` vs Jellyfin 10.11.11 on ser8, which plan 09-04 owns. Bumping that input from this plan would have made both plans unbisectable for no gain.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] NixOS 26.05 asserts on the resolvconf / `environment.etc."resolv.conf"` overlap**

- **Found during:** Task 1, at the first `pi4` dry-run toplevel build
- **Issue:** `Failed assertions: - networking.resolvconf.enable is true but environment.etc."resolv.conf" is also set.` `modules/dns/adguard-home.nix` deliberately writes a static `/etc/resolv.conf` pointing at the local AdGuard instance. 26.05 added an assertion on that overlap instead of letting one writer silently win. Without this fix pi4 cannot evaluate at all, so Task 1's verification was unreachable.
- **Fix:** `networking.resolvconf.enable = false;` added next to the `environment.etc."resolv.conf"` declaration, with a comment naming the assertion. This matches the module's actual intent — it owns the file outright.
- **Files modified:** `modules/dns/adguard-home.nix`
- **Verification:** `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` exits 0
- **Committed in:** `b0e9a85`

**2. [Rule 3 - Blocking] statix `empty_pattern` warning on the rewritten `hosts/pi5/configtxt.nix`**

- **Found during:** Task 2, running `statix check` as part of `make check`
- **Issue:** The plan directed trimming the file's argument list to `{ ... }:` per `hosts/ser8/default.nix`. statix flags that as `[10] Warning: Found empty pattern in function argument`. statix carves out module files whose body contains `imports` — which is why `hosts/ser8/default.nix` and the two new `default.nix` files are silent and this file was not. CLAUDE.md's zero-warnings rule makes this a must-fix rather than noise.
- **Fix:** `_:` instead of `{ ... }:`, which is the form statix's own message recommends.
- **Files modified:** `hosts/pi5/configtxt.nix`
- **Verification:** `statix check` repo-wide reports 0 warnings; the rendered config.txt is unchanged
- **Committed in:** `ecb12c2`

**3. [Rule 3 - Blocking] pre-existing SC1091 in `scripts/nixos-rebuild.sh`**

- **Found during:** Task 2, running the task's `shellcheck` verification
- **Issue:** The task's verify requires `shellcheck scripts/nixos-rebuild.sh` to exit 0. It exits 1 on `SC1091 (info): Not following: ./scripts/lib/all.sh`. Confirmed pre-existing: `git show HEAD:scripts/nixos-rebuild.sh` fails identically, as does the untouched `scripts/smoketests/gateway/test-subgen.sh`.
- **Fix:** Added the repo's existing `# shellcheck source=scripts/lib/all.sh` directive (the convention already used in `scripts/smoketests/media/all.sh` and `test-subgen.sh`), and ran the repo-conventional `shellcheck -x`, which exits 0. The plain `shellcheck` invocation still emits SC1091 for every sourcing script in the repo, so `-x` is the correct invocation rather than a workaround for this file.
- **Files modified:** `scripts/nixos-rebuild.sh`
- **Verification:** `shellcheck -x scripts/validation/test-pi-bootloader.sh scripts/nixos-rebuild.sh` exits 0; `shfmt -d` produces no diff
- **Committed in:** `ecb12c2`

### Scope moved earlier

**4. The `nixConfig` cachix block was removed in Task 1, not Task 2.** Task 1's acceptance criterion is `grep -c 'nixos-raspberrypi' flake.nix` → `0`, and the cachix URL and key both contain that string. Removing the block was therefore forced into Task 1. Task 2's `grep -c 'cachix' flake.nix` → `0` criterion is satisfied by the same edit. No work was skipped.

### Plan defects found

**5. `hosts/pi5/configtxt.nix` could not both carry the required comment and pass the required grep.** The action says to "add a comment recording both facts so a future reader does not re-add either"; the acceptance criterion says `grep -c 'enable_uart' hosts/pi5/configtxt.nix` → `0`. Naming the option in the comment fails the grep. Resolved by keeping the comment and rewording it to describe the settings and cite `raspberry-pi/common/config-txt-defaults.nix` without using the literal token. Both the instruction's intent and the criterion are satisfied.

**6. The `systemd.network.networks` acceptance criterion cannot pass on 26.05 for any host.** The criterion is `nix eval --json '.#nixosConfigurations.pi4.config.systemd.network.networks' | jq -e 'length > 0'`. Serializing the whole attrset reads every sub-option including `dhcpConfig`, whose 26.05 stub is `apply = _: throw "…can no longer be used since it's been removed"`. The same command fails identically on `firebat`, which proves it is a nixpkgs artifact and not a Pi regression. Verified the underlying intent instead:
  - `nix eval --json '…pi4.config.systemd.network.networks' --apply 'builtins.attrNames'` → `["40-end0","50-tailscale","99-ethernet-default-dhcp","99-wireless-client-dhcp"]` — both base-module networks survived the `options`/`config` restructure
  - `…networks."99-ethernet-default-dhcp".networkConfig` → `{"DHCP":"yes","IPv6PrivacyExtensions":"kernel"}`
  - `…config.boot.tmp.useTmpfs` → `true`

**7. The config.txt verification command cannot run on this machine.** The plan specifies `nix eval --raw '…configtxt.file' | xargs cat`. That store path is an `aarch64-linux` derivation and this is a macOS host whose Linux builder is unavailable (`Failed to set up Native Linux Builder … Authentication token is invalid`). Used `…configtxt.file.text` instead, which reads the exact same rendered string out of the `writeText` derivation by pure evaluation and needs no builder.

---

**Total deviations:** 3 auto-fixed (all Rule 3 — blocking), 1 scope reordering, 3 plan defects worked around.
**Impact on plan:** No scope creep. Deviation 1 is the only change to a file outside the plan's `files_modified` list, and without it neither Pi could evaluate.

## Issues Encountered

**1. `make check` does not pass — blocked on plan 09-04, not on this plan.**

```
$ make check
checking NixOS configuration 'nixosConfigurations.ser8'...
error: Failed assertions:
- Unsupported jellyfin/jellyfin-web version!
  Supported versions: 10.11.3 10.11.4 10.11.5 10.11.6 10.11.7 10.11.8
  Submit an issue to declarative-jellyfin to support version 10.11.11
```

This is exactly the blocker STATE.md already records against 09-01. Every other component of `check` was run individually and is green:

| Component | Result |
|---|---|
| `statix check` (repo-wide) | 0 warnings |
| `./scripts/validation/test-nzbget-permissions.sh` | pass |
| `./scripts/validation/test-actual-module.sh` | pass |
| `./scripts/validation/test-pi-bootloader.sh` | pass (4/4 assertions) |
| `nix build --dry-run` ser8 | **FAIL** (jellyfin) |
| `nix build --dry-run` firebat | pass |
| `nix build --dry-run` pi4 | pass |
| `nix build --dry-run` pi5 | pass |

Three of four hosts dry-run build. The FOUND-01 success criterion "make check passes for all four hosts" is **unmet** and stays that way until 09-04 refreshes `declarative-jellyfin`.

**2. Elevation unavailable, so the trusted cache grant still stands.** Detailed above.

**3. Dead references to the removed fork remain under `experimental/docker-compose/`.** Left in place deliberately — these files are outside the active flake and expanding into them was explicitly out of this plan's scope. They are now dead code:

- `experimental/docker-compose/pi5-usb-installer.nix` — imports `nixos-raspberrypi` and `../modules/raspberrypi/usb-installer.nix`, both of which no longer exist
- `experimental/docker-compose/Makefile:20` and `SUMMARY.md:104` — build a `pi5-usb-installer` package that no longer exists
- `experimental/docker-compose/docker-compose.yml:28-29` and `experimental/docker-compose/etc/nix/nix.conf:21` — still list the third-party cachix substituter and trusted key

The last item is worth flagging beyond tidiness: it is a fourth place the third-party cache is granted trust, scoped to that experimental container.

## Known Stubs

None.

## Deferred Issues

- `make update-nix-conf` runs its `cp` commands without `sudo` and unconditionally backs up `/etc/nix/machines`, which does not exist on this machine. It can only succeed when the whole target is invoked as root, and it aborts on its first line. Out of scope here; the plan directed running the target as-is.
- `experimental/docker-compose/` fork references (above).

## Next Phase Readiness

**Ready:**
- FOUND-02 is complete at the evidence level D-13 defines for each Pi. Plan 09-07 can write PROJECT.md from the two separate per-host entries above without collapsing them.
- The Pi half of `make check` is green and permanently gated. When 09-04 unblocks jellyfin, `make check` should go green in one step with no further Pi work.
- Threats T-09-05 (fork nixpkgs in the closure), T-09-07 (RSA key in the deleted installer), and T-09-23 (stale recovery guidance) are closed.

**Blockers carried forward:**
- **T-09-06 is open.** The third-party trusted key is still installed on the developer machine. Needs `sudo make update-nix-conf` from the user.
- `make check` red on ser8/jellyfin — 09-04.
- ser8 and firebat activation previews still outstanding from 09-01 — 09-04 / 09-07.
- pi5's `deploy.yaml` entry (`192.168.0.110`, user `nixos`) is very likely stale. It needs correcting before any future plan tries to reach that host, and the deferred reflash work should assume the address is unknown.

**For the deferred bootstrap image (D-02):** the deleted `modules/raspberrypi/installer.nix` embedded an **RSA** public key. The replacement minimal upstream bootstrap image should use **ed25519** instead, with password authentication disabled and root login disabled, matching the pattern the pi5 common module already follows.

**For the deferred reflash:** `hardware.raspberry-pi.firmware.enable` and `.uboot.enable` are both left at their upstream default of disabled. Enabling them installs an activation script that repopulates `/boot/firmware` on every switch and prunes DTBs it did not copy — that belongs with the reflash, not here.

## Self-Check: PASSED

Created files verified present:
- `hosts/pi4/default.nix` — FOUND
- `hosts/pi5/default.nix` — FOUND
- `scripts/validation/test-pi-bootloader.sh` — FOUND (mode 755)

Deleted files verified absent:
- `modules/raspberrypi/installer.nix` — ABSENT
- `modules/raspberrypi/usb-installer.nix` — ABSENT

Commits verified in `git log`:
- `b0e9a85` — FOUND
- `ecb12c2` — FOUND

---
*Phase: 09-channel-bump-to-nixos-26-05*
*Completed: 2026-08-17*
