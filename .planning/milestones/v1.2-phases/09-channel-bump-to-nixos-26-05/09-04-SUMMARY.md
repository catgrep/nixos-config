---
phase: 09-channel-bump-to-nixos-26-05
plan: 04
subsystem: flake-inputs
tags: [channel-bump, flake-update, home-manager, overlays, frigate, sabnzbd, tailscale]
status: complete
requires:
  - 09-01 (nixpkgs on 26.05, make check repaired to propagate host failures)
  - 09-02 (Pi hosts on upstream nixpkgs)
  - 09-03 (committed pre-bump service/package baselines + diff-enabled-services.sh)
provides:
  - home-manager aligned to release-26.05 at top level and in the subflake
  - every remaining flake input re-locked onto the 26.05 channel
  - "make check green for the first time this phase (all four hosts)"
  - zero unstable-channel package references, with the input and plumbing retained
  - frigate overlay removed on real-build evidence
affects:
  - flake.nix
  - flake.lock
  - home-manager/flake.nix
  - home-manager/flake.lock
  - modules/servers/tailscale.nix
  - modules/media/sabnzbd.nix
  - modules/media/radarr.nix
  - modules/media/sonarr.nix
  - modules/automation/frigate.nix
  - modules/common/packages.nix
  - users/bdhill.nix
  - .planning/STATE.md
tech-stack:
  added: []
  patterns:
    - "Read un-overlaid stable versions through a host that does not import the overlaying module (firebat) rather than through --impure, which the sandbox blocks"
    - "Route x86_64 builds to ser8 by copying the .drv and realising it over user SSH, bypassing the nix daemon's missing root known_hosts"
key-files:
  created: []
  modified:
    - flake.nix
    - flake.lock
    - home-manager/flake.nix
    - home-manager/flake.lock
    - modules/servers/tailscale.nix
    - modules/media/sabnzbd.nix
    - modules/media/radarr.nix
    - modules/media/sonarr.nix
    - modules/automation/frigate.nix
    - modules/common/packages.nix
    - home-manager/default.nix
    - users/bdhill.nix
    - .planning/STATE.md
  deleted:
    - overlays/frigate-tflite-optional.nix
decisions:
  - "Delete the Frigate TFLite overlay: nixpkgs 26.05 applies its own ai-edge-litert.patch, so the overlay is both broken (its guard aborts the build) and redundant"
  - "Keep the PYTHONPATH tensorflow filter in frigate.nix even after removing the overlay, because tensorflow remains in Frigate's closure"
  - "Force UMask 0002 on radarr and sonarr; 26.05's servarr module now sets 0022 and would drop the shared media group's write bit"
  - "Migrate programs.git to the settings.* form rather than accepting the new rename warning"
metrics:
  duration: ~50 min
  completed: 2026-08-17
actuals:
  tokens: 6641
  tasks: 4
  commits: 4
---

# Phase 09 Plan 04: Refresh Remaining Inputs and Retire 25.11 Workarounds Summary

Aligned Home Manager to `release-26.05`, re-locked every remaining input, and deleted three 25.11-era package-source workarounds — one of which had silently inverted into a downgrade and one of which a real build proved was already broken.

## Performance

- Duration: ~50 min (01:34–01:49 for commits; the bulk of wall time was the Frigate build and the 224-path closure realisation on ser8)
- Tasks: 4/4
- Commits: 4

## Accomplishments

`make check` exits 0 for the first time in this phase. All four hosts dry-run build, and both x86 hosts pass the array-aware service diff against their committed 25.11 baselines.

### Task 1 — Home Manager release alignment (`aa8af76`)

Top-level `home-manager` moved `release-25.05` → `release-26.05`. The `home-manager/` subflake pinned no release at all, so both of its inputs moved together (`nixpkgs` → `nixos-26.05`, `home-manager` → `release-26.05`) rather than creating a fresh mismatch of the kind being closed; colmena still follows the subflake's nixpkgs.

`nix build --no-link './home-manager#homeConfigurations."bobby".activationPackage'` exits 0. No package blocked on the subflake move — nothing required the unstable channel.

The top-level `flake.lock` diff for this commit touched only the `home-manager` node (4 fields: `lastModified`, `narHash`, `rev`, `ref`); no unrelated input revision moved.

### Task 2 — blanket re-lock (`2f5f6dc`)

`nix flake update` moved `declarative-jellyfin` 3843ca5 → **c758527**, the revision carried from 09-01 as required for Jellyfin 10.11.11. This unblocked ser8 and turned `make check` green. `disko`, `sops-nix`, `nixos-images` and `nixpkgs-unstable` advanced with it; `nixos-hardware` stayed pinned.

Fork-return gates: `jq -e '.nodes | has("nixos-raspberrypi") | not'` exits 0 and `grep -c 'nvmd' flake.lock` outputs `0`.

### Task 3 — unstable-to-stable moves and the inverted overlay (`3cb8a9a`)

### Task 4 — Frigate overlay decision (`eb32d55`)

See the dedicated sections below.

## Version Movement

Before values are from `.planning/phases/09-.../baseline/ser8-packages-2511.json`. After values come from direct attribute evaluation, not `packageInfo`.

| Package | Before (25.11) | After (26.05) | Bar the deleted comment named | Command |
|---|---|---|---|---|
| sabnzbd | 5.0.3 (overlay pin; channel shipped 4.5.5) | **5.0.4** | overlay existed to beat 4.5.5 | `nix eval --raw '.#nixosConfigurations.ser8.config.services.sabnzbd.package.version'` |
| par2cmdline-turbo | unstable-sourced (channel had 1.3) | **1.4.0** | "SABnzbd 5.x release builds use par2cmdline-turbo 1.4" | `nix eval --raw '.#nixosConfigurations.ser8.pkgs.par2cmdline-turbo.version'` |
| tailscale | 1.98.0 (unstable-sourced) | **1.98.10** | ">= 1.92.5" | `nix eval --raw '.#nixosConfigurations.ser8.config.services.tailscale.package.version'` |

SABnzbd moved **forward** (5.0.3 → 5.0.4), confirming the overlay had inverted: it pinned 5.0.3 to get ahead of 25.11, but 26.05 ships 5.0.4, so keeping it would have held ser8 on the older release indefinitely.

Un-overlaid stable values were read through **firebat's** package set (`.#nixosConfigurations.firebat.pkgs.<p>.version`), which never imports `modules/media` and therefore carries no SABnzbd overlay. Reading `ser8.pkgs.sabnzbd` would have returned the overlay's own 5.0.3 and produced a vacuous comparison.

### The SABnzbd overlay was fully redundant, not merely inverted

Stable 26.05's `pkgs/by-name/sa/sabnzbd/package.nix` is byte-for-byte what the overlay hand-rolled: the same `sabctools` 9.4.0 override with the identical hash, the same `pythonEnv` package list, the same `installPhase`, and the same `path = lib.makeBinPath [...]` including `par2cmdline-turbo`. Deleting the overlay therefore carried the sabctools override and the par2 reference away with it — upstream sources both itself.

par2 presence was confirmed at the derivation level, since the x86_64 output cannot be inspected from the darwin dev machine:

```
$ nix derivation show $(nix eval --raw '.#nixosConfigurations.ser8.config.services.sabnzbd.package.drvPath') | grep -o 'par2cmdline-turbo-[0-9.]*'
par2cmdline-turbo-1.4.0
```

## Frigate Overlay Decision: REMOVED

**Outcome (b).** `overlays/frigate-tflite-optional.nix` no longer exists and `grep -c 'frigate-tflite-optional' flake.nix` outputs `0`.

**Frigate version the decision was made against: 0.17.2.**

### The real build falsified the plan's premise

09-RESEARCH.md Pitfall 5 recorded that all five patch targets and their guard lines were verified present at the version 26.05 ships. **A real build disproved this.** Building with the overlay still applied aborted:

```
> applying patch /nix/store/4v1xa1ipnvr8djizzgafaaylny7a6jhk-ai-edge-litert.patch
> Frigate TFLite import pattern changed in frigate/data_processing/real_time/bird.py
REALISE_EXIT=1
```

Since 26.05, nixpkgs applies its own `ai-edge-litert.patch`, which rewrites every `from tensorflow.lite.python.interpreter import ...` fallback to `from ai_edge_litert.interpreter import ...` across exactly the files the overlay targeted (plus `custom_classification.py` and `detector_utils.py`). The line the overlay grepped for no longer exists, so its fail-fast guard fired. This is precisely the failure a dry-run cannot surface, and it validates the review's sixth blocker.

### Build evidence (real, not dry-run — ran on ser8)

The nix daemon could not use ser8 as a remote builder (`Host key verification failed` — root's `known_hosts` is unwritable without sudo) and the local Native Linux Builder returned `Authentication token is invalid`. Worked around by shipping the derivation and realising it over user SSH:

```
nix copy --derivation --to ssh://bdhill@ser8.local /nix/store/a4jph19wcs22ryp18as6q7w355jnglc0-frigate-0.17.2.drv
ssh bdhill@ser8.local "nix-store --realise /nix/store/a4jph19wcs22ryp18as6q7w355jnglc0-frigate-0.17.2.drv"
```

Build output location: `/nix/store/9a88h1s4qyhsp848l46fzyqc0nlbgvs2-frigate-0.17.2` on ser8. Without the overlay it **substituted from cache.nixos.org** (3.55 MiB download) instead of building — the overlay had been forcing a full local rebuild of a large package for no benefit.

### Import test (executed, under the unit's own filtered PYTHONPATH)

`PYTHONPATH` was taken verbatim from `nix eval --raw '.#nixosConfigurations.ser8.config.systemd.services.frigate.environment.PYTHONPATH'` — **224 components, 0 matching `tensorflow-`, 1 matching `ai-edge-litert` (2.1.4)** — confirming the test ran under the filtered path the unit actually uses. All 224 store paths were realised on ser8 first.

```
ssh bdhill@ser8.local "PYTHONPATH=$(cat /tmp/pp.txt) USE_TF=0 \
  /nix/store/kxdkzc079hlg9ifg4lhjvyi2w7qwpshx-python3-3.13.14/bin/python -c '...import each module...'"
```

Result:

```
OK    frigate.data_processing.real_time.bird
OK    frigate.embeddings.onnx.face_embedding
OK    frigate.events.audio
OK    frigate.detectors.plugins.cpu_tfl
OK    frigate.detectors.plugins.edgetpu_tfl
tensorflow imported: False
ai_edge_litert: ai_edge_litert.interpreter
IMPORT_EXIT=0
```

All five previously-patched modules import with tensorflow absent and never loaded. The workaround the overlay supported is no longer needed **at the overlay level**, because upstream now routes those imports away from tensorflow.

The `PYTHONPATH` tensorflow filter in `modules/automation/frigate.nix` was **kept**: tensorflow is still present in Frigate's unfiltered `pythonPath` (1 component), so the protobuf-collision guard still does real work. Its stale comment referencing the deleted overlay was rewritten.

## Home Manager Warning Baseline

**Cause of the change:** the top-level `home-manager` input was two releases behind a 26.05 nixpkgs. Aligning it to `release-26.05` closed the gap, and the release-mismatch warning disappeared entirely.

**Evidence:** `nix build --dry-run '.#nixosConfigurations.ser8...' --option eval-cache false 2>&1 | grep -ci 'you are using'` outputs `0`.

**A new warning class did replace it, and it was fixed rather than accepted.** Home Manager 26.05 renamed `programs.git.userName` / `userEmail` / `extraConfig` to `programs.git.settings.*`. `users/bdhill.nix` was migrated in the same commit, so the count for that class is also zero.

`.planning/STATE.md` line 91 — the Phase 08 entry that permitted the mismatch as an accepted baseline — was **replaced** (not appended to, per replace-don't-deprecate) with:

> [Phase 09]: SUPERSEDES the Phase 08 accepted Home Manager mismatch baseline. As of 09-04 the home-manager input is on `release-26.05`, matching the nixpkgs channel at both the top level and in the `home-manager/` subflake, so the two-release gap that produced the release-mismatch warning no longer exists. That warning is GONE (`nix build --dry-run` on ser8 reports 0 matches for "you are using"), and it is no longer an accepted baseline: any release-mismatch warning appearing in evaluation output from now on is a finding to investigate, not a permitted condition. One new warning class replaced it — home-manager 26.05 renamed `programs.git.userName`/`userEmail`/`extraConfig` to `programs.git.settings.*` — and it was migrated away in the same commit rather than accepted, so the post-alignment warning count is zero for that class too. One unrelated warning remains outstanding and is NOT accepted: `nixfmt-rfc-style is now the same as pkgs.nixfmt`, introduced by the 09-01 nixpkgs bump.

The `nixfmt-rfc-style` warning named there was then fixed in Task 3 (`nixfmt-rfc-style` → `nixfmt` in `modules/common/packages.nix` and `home-manager/default.nix`).

## Service Diff (both x86 hosts)

Both exit 0 via `scripts/validation/diff-enabled-services.sh` (array-aware; no `keys`-based comparison). **No service present in either baseline is missing.**

One addition, on both hosts:

| Added | Explanation |
|---|---|
| `logind` | Not a configuration change. 26.05 introduced `options.services.logind.enable`, defaulting to `config.systemd.package.withLogind` (true). systemd-logind ran on both hosts before; it simply became expressible as an `enable` option, so the flake's `enabledServices` filter now counts it. The 25.11 baseline predates the option's existence. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — Missing critical functionality] Migrated `programs.git` to the renamed `settings.*` options**
- **Found during:** Task 1
- **Issue:** Home Manager 26.05 renamed `userName`/`userEmail`/`extraConfig`; the bump introduced a new evaluation warning, which the Phase 08 policy explicitly rejects and the repo's zero-warnings rule forbids.
- **Fix:** Rewrote the block in `users/bdhill.nix` to `programs.git.settings.{user.name,user.email,init.defaultBranch,pull.rebase}`. Verified `services...programs.git.settings.user.email` evaluates to the expected value.
- **Files modified:** `users/bdhill.nix`
- **Commit:** `aa8af76` (deliberately with the input that caused it, so a regression bisects to its cause)

**2. [Rule 3 — Blocking] Forced `UMask = "0002"` on radarr and sonarr**
- **Found during:** Task 2
- **Issue:** The blanket re-lock advanced nixpkgs, and 26.05's servarr module now sets `serviceConfig.UMask = "0022"` itself. This produced a hard evaluation conflict against the repo's `0002` and blocked all four hosts.
- **Fix:** Wrapped both in `lib.mkForce "0002"` with a comment explaining why. `0002` is required: the media pipeline hands files between services sharing the `media` group, and `0022` would strip the group-write bit. Upstream bazarr is unaffected.
- **Files modified:** `modules/media/radarr.nix`, `modules/media/sonarr.nix`
- **Commit:** `2f5f6dc`

**3. [Rule 2 — Transparency] Replaced `nixfmt-rfc-style` with `nixfmt`**
- **Found during:** Task 1, fixed in Task 3
- **Issue:** 26.05 aliases `nixfmt-rfc-style` to `nixfmt` and emits a deprecation warning. Introduced by 09-01's nixpkgs bump, not by this plan, but left the tree with an unaddressed warning that STATE.md would otherwise have recorded as outstanding.
- **Fix:** Renamed both references.
- **Files modified:** `modules/common/packages.nix`, `home-manager/default.nix`
- **Commit:** `3cb8a9a`

### Plan Defects Found

**4. Task 3's `! grep -rq 'unstable\.' modules/ hosts/` gate is unsatisfiable as written**
- The pattern `unstable\.` also matches `registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;` in `modules/common/nix.nix:35` — the registry plumbing D-11 explicitly requires retaining. The gate contradicts the plan's own must_have that the unstable input stay wired up.
- **Resolved by** testing the intent instead: `grep -rnP '(?<!nixpkgs-)\bunstable\.' modules/ hosts/` returns **no matches**, i.e. zero unstable-channel *package* references, while the registry entry survives. The literal command is recorded here as failing for a benign reason so a later auditor does not read it as a regression.

**5. Task 2's "no `.nix` source file changed" criterion could not hold**
- The re-lock itself broke evaluation (deviation 2). Landing the lock bump without its fix would have produced a commit that does not evaluate, which is strictly worse for the bisection the staged-commit decision (D-09) exists to enable. The UMask fix therefore landed inside `2f5f6dc` alongside `flake.lock` and `STATE.md`.

**6. `--impure` is blocked in this sandbox** (`getting status of "/Users/bobby/.config": Operation not permitted`), so un-overlaid stable versions could not be read via `builtins.getFlake`. Read through firebat's package set instead, as described above.

**7. 09-RESEARCH.md Pitfall 5 is factually wrong for Frigate** — see the Frigate section. It claimed the overlay's guard lines were still present at the 26.05 version; the real build proved they are not. Anyone re-reading that pitfall should treat it as superseded.

## Issues Encountered

- The nix daemon cannot dispatch to ser8 as a remote builder (`Host key verification failed`; root's `known_hosts` needs sudo, which is blocked this session), and the local Determinate "Native Linux Builder" fails with `Authentication token is invalid`. Both are environment problems, not repository problems, and the `nix copy --derivation` + `ssh nix-store --realise` route works around them. Worth fixing before 09-07, which needs real x86 builds.

## Known Stubs

None.

## Deferred Issues

Logged to `deferred-items.md`:

- **`services.sabnzbd.configFile` is deprecated in 26.05** (setter at `hosts/ser8/media/sabnzbd.nix:8`). The plan explicitly scoped this task to the package-version overlay and told the executor to leave service configuration untouched. Migrating to `settings` is not mechanical — `sabnzbd.ini` is rewritten by SABnzbd at runtime, so a declarative block risks clobbering live state and needs its own plan with real ser8 verification.
- **`stdenv.isDarwin is deprecated`** — emitted from a third-party flake input during darwin evaluation; no in-tree `.nix` file references it. Resolves when that input next bumps.

## Threat Flags

None. No new network endpoint, auth path, or trust-boundary schema change. `T-09-14` (SABnzbd held back by an inverted overlay) and `T-09-15` (Tailscale on an unnecessary source) are both closed by Task 3; `T-09-29` (overlay certified by a dry-run) is closed by Task 4's real build, which found the overlay actually broken.

## Next Phase Readiness

`make check` is green, which unblocks the activation previews carried from 09-01:

- **ser8** — `make dry-activate-ser8` was blocked behind the declarative-jellyfin pin. That pin is now lifted (`c758527`), so the preview can finally run. **It was not run here** — this plan's brief ended at input refresh and workaround removal, and 09-05 owns activation.
- **firebat** — still bounded by the uncached `python3.12-torch` source build for `subgen`. Unchanged by this plan.

Neither host has a recorded remote activation preview yet, so the phase must_have "ser8 and firebat each receive a real remote activation preview" remains **UNMET** and carries to 09-05/09-07.

Also still carried: the third-party cachix trusted key in `/etc/nix/nix.custom.conf` (needs `sudo make update-nix-conf`), and pi5's stale `deploy.yaml` address.

## Self-Check: PASSED

All claimed files exist, `overlays/frigate-tflite-optional.nix` is confirmed deleted, and all five commits (`aa8af76`, `2f5f6dc`, `3cb8a9a`, `eb32d55`, `92de772`) are present in git history.
