---
phase: 09-channel-bump-to-nixos-26-05
plan: 01
subsystem: flake-channel
tags: [nixpkgs, channel-bump, impermanence, systemd-initrd, grafana, validation]
status: complete
requires:
  - none
provides:
  - nixpkgs input locked to nixos-26.05
  - pre-bump 25.11 evaluation baseline for ser8 and firebat
  - scripts/validation/test-actual-module.sh (SC3 permanent gate)
  - scripts/validation/diff-enabled-services.sh (array-aware service regression diff)
  - make check host loop that propagates build failures
  - shfmt in the devShell
  - grafana secret_key pinned from SOPS (grafana.db ciphertext stays decryptable)
  - caddy xcaddy vendor hash corrected for 26.05
affects:
  - all four hosts (closure moves to 26.05)
  - plans 09-02, 09-04, 09-05
tech-stack:
  added:
    - shfmt (devShell)
  patterns:
    - boot.initrd.systemd.services for stage-1 ZFS rollback (replaces postDeviceCommands)
    - services.resolved.settings.Resolve structured form (replaces extraConfig)
key-files:
  created:
    - scripts/validation/test-actual-module.sh
    - scripts/validation/diff-enabled-services.sh
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/ (7 files)
  modified:
    - flake.nix
    - flake.lock
    - hosts/ser8/configuration.nix
    - hosts/ser8/impermanence.nix
    - modules/automation/home-assistant.nix
    - modules/common/networking.nix
    - modules/gateway/grafana.nix
    - modules/gateway/caddy.nix
    - secrets/firebat.yaml
    - Makefile
decisions:
  - Migrate ser8's erase-your-darlings rollback to a stage-1 systemd oneshot rather than pinning boot.initrd.systemd.enable = false
  - Take 26.05's new systemd-initrd default (true) on both x86 hosts
  - Pin grafana secret_key to the legacy upstream constant rather than minting a new key
  - Update the caddy withPlugins vendor hash in place rather than deferring it, since no other plan owns that file
  - Defer declarative-jellyfin's version assertion to plan 09-04's input refresh
  - Defer the Pi systemd-resolved collision to plan 09-02
  - Commit unsigned for this phase (GPG unavailable in the sandboxed session)
metrics:
  duration: ~45 min (tasks 1+3) + ~2h (task 2, mostly remote build time)
  completed: 2026-08-17
actuals:
  tokens: 3106
  tasks: 3
  commits: 4
---

# Phase 09 Plan 01: Channel Bump to NixOS 26.05 Summary

The flake is locked to `nixos-26.05`, ser8's four 26.05 breaking changes are fixed and proven by evaluation, `make check` can now actually fail, and Grafana's encryption key is pinned from SOPS so firebat's existing `grafana.db` ciphertext survives the bump.

**Status: all 3 tasks implemented and committed.** One verification remains unrun: neither host has produced a completed remote activation preview. ser8's is blocked on the declarative-jellyfin pin (09-04); firebat's got past every repo-side blocker and is now only waiting on a multi-hour uncached `torch` compile. Both are carried to 09-04. **Nothing in this plan is validated by activation — only by evaluation and derivation-graph resolution.** See "Verification Status".

## What Was Built

### Task 1 — Channel bump proven on ser8 (commit `a417618`)

The pre-bump baseline was captured on the untouched tree before any edit, then the nixpkgs input alone was re-locked.

**Baseline capture (pre-bump, 25.11).** Seven files under `baseline/`, all non-empty:

| File | Content |
|---|---|
| `ser8-services-2511.json` | sorted JSON array, 25 services |
| `ser8-packages-2511.json` | `packageInfo.ser8` |
| `firebat-services-2511.json` | sorted JSON array |
| `firebat-packages-2511.json` | `packageInfo.firebat` |
| `make-check-2511.txt` | 350,104 bytes of combined stdout+stderr |
| `make-check-2511.status` | `0` |
| `capture-metadata.json` | provenance |

Provenance recorded: `captured_at` = `2026-08-17T05:52:25Z`, `nixpkgs_rev_before` = `687f05a9184cad4eaf905c48b63649e3a86f5433`, `nix (Nix) 2.34.7+1`, `jq-1.8.1`, plus the exact command string for each capture.

**Was the pre-bump tree green?** Yes — `make-check-2511.status` contains `0`. Per the plan's own caveat this exit status is *not* trustworthy evidence about the host builds, because it was captured before Task 3 fixed the check target's host loop. At capture time the loop could not fail. The authority for the pre-bump state is `make-check-2511.txt`, not the status file.

**The re-lock.** `flake.nix` moved to `github:NixOS/nixpkgs/nixos-26.05`. `flake.lock` shows exactly one node changed — `nixpkgs_3`, `687f05a` → `02e0898`, ref `nixos-25.11` → `nixos-26.05`. Every other input, the `nixConfig` block, and both system helpers are untouched, as plans 02 and 04 own those.

**Four breaking-change fixes** (the plan anticipated two; two more were found during execution — see Deviations):

1. `hosts/ser8/impermanence.nix` — `fsType = "none";` added to `fileSystems."/etc/nixos"` and `fileSystems."/var/log"`, immediately after each `device` line. 26.05 dropped the `"auto"` default. `/persist` was deliberately left alone.
2. `modules/automation/home-assistant.nix` — the single legacy top-level `mode = "storage"` assignment inside `config.lovelace` deleted. The `dashboards` attrset, the `lovelaceResources` let-binding, and the tmpfiles rule are all untouched.
3. `hosts/ser8/configuration.nix` — the erase-your-darlings rollback migrated off `boot.initrd.postDeviceCommands` (see Decisions).
4. `modules/common/networking.nix` — `services.resolved` migrated to the structured `settings.Resolve` form.

**Verification actually run** (each claim names its command):

| Check | Command | Result |
|---|---|---|
| Channel ref | `nix flake metadata --json \| jq -r '.locks.nodes[.locks.nodes.root.inputs.nixpkgs].original.ref'` | `nixos-26.05` |
| `/etc/nixos` fsType | `nix eval --raw ...fileSystems."/etc/nixos".fsType` | `none` |
| `/var/log` fsType | `nix eval --raw ...fileSystems."/var/log".fsType` | `none` |
| `/persist` fsType (disko merge) | `nix eval --raw ...fileSystems."/persist".fsType` | `zfs` — non-empty, so the disko and impermanence definitions merge rather than collide |
| lovelace deprecation | `grep -v '^ *#' modules/automation/home-assistant.nix \| grep -c 'mode = "storage"'` | `0` |
| stateVersion (D-12) | `nix eval --raw ...system.stateVersion` for ser8, firebat | `24.11`, `24.11` |
| Baselines are arrays | `jq -e 'type == "array"'` on both services files | pass |
| Baseline is sorted | `jq -e '. == (. \| sort)'` on ser8 services | pass |
| Metadata completeness | `jq -e 'has("captured_at") and ... and has("commands")'` | pass |

### Task 3 — `make check` can fail, plus the Actual and service-diff assertions (commit `866710f`)

**The gate fix.** `Makefile:146-151`'s host loop was a single shell command whose last element was a success message, so a failing `nix build --dry-run` inside the loop could not change the recipe's exit status. Added `set -e; \` immediately before the loop. Hosts iterated, messages, and the four preceding `@`-prefixed lines are unchanged.

**Proof the gate went red** — this is the part that matters, and it needs a caveat about which command produced the evidence:

```
OLD recipe semantics (no set -e), HOSTS=gsd-nonexistent-host  -> rc=0   <- the bug
NEW recipe semantics (set -e),    HOSTS=gsd-nonexistent-host  -> rc=1   <- the fix
```

That A/B ran the recipe's loop verbatim in `bash -c`, isolating the change. It was done that way deliberately: `make check HOSTS=gsd-nonexistent-host` **does** exit non-zero (observed `rc=2`), but it aborts at `nix flake check` on `Makefile:142` before ever reaching the host loop, so on its own it would prove nothing about the loop. Both runs are recorded here rather than the convenient one.

**`make check` normally: rc=2, still red.** It fails at `nix flake check` with `Failed assertions: - Unsupported jellyfin/jellyfin-web version!`. This is the deferred third-party blocker, not repo code — see Deferred Work.

**New scripts.** Both follow `test-nzbget-permissions.sh` for shebang, SPDX header, `set -euo pipefail`, and non-zero exit; both are executable; both pass `shellcheck` and `shfmt -d` clean.

`test-actual-module.sh` confirms Success Criterion 3 and exits 0:

```
ok: options.services.actual.user type = "nullOr"
ok: options.services.actual.group type = "nullOr"
ok: config.services.actual.settings.dataDir = "/var/lib/actual"
```

Those two option paths do not exist on 25.11 at all, so their resolution is the discriminator. **Phase 12 will not need an unstable overlay for Actual.** Eval failures are allowed to propagate — no fallback wraps these calls.

`diff-enabled-services.sh` takes `<host> <baseline.json>` positionally (a contract for plans 04 and 05), sorts both sides, and subtracts arrays. Results against the committed baselines:

- `ser8` → exit 0, `+ logind` added, nothing removed
- `firebat` → exit 0, `+ logind` added, nothing removed

`logind` appearing on both hosts is 26.05 exposing it as a distinct service; no service present in either baseline disappeared, so there is no regression to investigate.

**Direction proof for the diff script**, both observations as the plan requires:

- baseline copy with one service removed from the copy → **exit 0** (reported `+ avahi`, `+ logind` as additions)
- baseline copy with one extra service added to the copy → **exit 1**, `Services REMOVED since baseline (regression): - gsd-phantom-service`

**devShell.** `shfmt` added next to `shellcheck` in `flake.nix`, and confirmed resolvable — the `shfmt -d` run above executed from inside `nix develop`.

### Task 2 — Grafana's data-encryption key pinned from SOPS (commit `bd891df`)

26.05 removed the default for `services.grafana.settings.security.secret_key`, and Grafana moves 12.x → 13.x in the same bump. That key encrypts the datasource credentials and the Unified Alerting contact-point secrets that Phases 4 and 5 wrote into `/var/lib/grafana/grafana.db` on firebat. A freshly minted key would leave all of it permanently unreadable, and the only symptom would be alert emails quietly not arriving.

`modules/gateway/grafana.nix` gains a third SOPS secret in the identical shape as the two beside it, and consumes it through the same `$__file{...}` indirection `admin_password` uses, so the path — never the value — reaches the generated ini:

```nix
  sops.secrets.grafana_secret_key = {
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
```

```nix
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
```

**The value is the published legacy upstream constant, not a new key** — this is a compatibility pin against existing ciphertext, not a minted credential, and the code comment says so. Rotation is separate backlog work with its own re-provisioning cost.

**How the SOPS write happened, and what that means for the evidence.** The precondition this task carries — `secrets/firebat.yaml` decryptable with the developer's age identity — was *never met inside this session*. No age identity is reachable here (`~/.config/sops/age/keys.txt` and `~/.age/keys.txt` both absent, `SOPS_AGE_KEY_FILE` unset); a read-only `sops -d` exits 128 with `no identity`. The user wrote the key from their own terminal and reported verifying `sops -d secrets/firebat.yaml | grep -c '^grafana_secret_key:'` → `1`. The executor folded the resulting encrypted file into this commit without being able to read it.

> **This one acceptance criterion is user-attested, not executor-verified.** `sops -d secrets/firebat.yaml | grep -c '^grafana_secret_key:'` was not run here and its result is taken on the user's word. The `secrets/` directory is also unreadable to this session, so the committed ciphertext was never inspected — not its key set, not its recipients. Anyone re-validating this phase should re-run that command themselves. Every *other* criterion below was executed directly.

**Verification actually run** (each claim names its command):

| Check | Command | Result |
|---|---|---|
| Declaration present | `grep -n 'sops.secrets.grafana_secret_key' modules/gateway/grafana.nix` | line 59 |
| Consumption present | `grep -n 'secret_key = "$__file'` | line 78 |
| Shape matches neighbours | `grep -c 'owner = "grafana";'` | `3` |
| Secret path evaluates | `nix eval --raw ...sops.secrets.grafana_secret_key.path` | `/run/secrets/grafana_secret_key` |
| No plaintext in tracked tree | `grep -rl '<constant>' modules/ hosts/ scripts/ flake.nix` | no files |
| firebat derivation graph | `nix build --dry-run ...firebat...toplevel` | exit 0 |
| Formatting / lint | `nixfmt --check`, `statix check` on grafana.nix | both clean |
| `sops -d` key present | *not run — no identity* | **user-attested only** |

**`make dry-activate-firebat`: started, unblocked, not finished.** See "The firebat activation preview" below. This is the one acceptance criterion of Task 2 that is outstanding, and with it the requirement to record the grafana unit's disposition.

## The firebat activation preview — how far it actually got

The plan requires a real remote activation preview, not just a local dry-run, and explicitly forbids counting evaluation as validation. Here is the honest state.

**Run 1 failed on an unrelated repo-side blocker.** After ~7 minutes of copying derivations to firebat, the remote build died:

```
error: hash mismatch in fixed-output derivation 'caddy-src-with-xcaddy-2.11.4.drv':
         specified: sha256-fBrfiD0aFUwwKZCQAXupClIfVdrUFLIjdp3gAkRHCQk=
            got:    sha256-tP/ZQjZvfb+e3322dzd3I89Y9QwujcyqV1fbNWyw08g=
```

Fixed in `modules/gateway/caddy.nix` — see Deviations. Note this failure was invisible to `nix build --dry-run`, which resolves the derivation graph without building anything. That is precisely the gap the plan's "evaluation is not validation" prohibition warns about, and it showed up in practice inside one plan.

**Run 2 got past caddy and is bounded only by build time.** `unit-caddy.service.drv` built, confirming the new vendor hash is correct and that the pinned `caddy-tailscale` plugin still compiles against caddy 2.11.4 — the compatibility question the old `2.10.x` comment left open is now answered by a real build, not an assumption. The run then reached:

```
building 'python3.12-torch-2.11.0.drv'...
building 'python3.12-onnxruntime-1.24.4.drv'...
```

`torch` is pulled in by firebat's own `subgen` service (`nix why-depends`: `nixos-system-firebat → etc → system-units → unit-subgen.service → subgen-2026.07.3 → python3.12-torch-2.11.0`). It is compiling **from source** — cache.nixos.org has no build for this closure at the pinned 26.05 revision. Confirmed genuinely progressing, not hung: firebat showed load 32 on 16 cores with `cc1plus` and `lto1-ltrans` saturating it.

The client was killed at the session's background-task limit after ~85 minutes with torch still compiling. **The remote build survived** — firebat's nix daemon kept going (load 16, `cc1plus` still at 100% after the client died), and each completed derivation lands in firebat's store. A re-run resumes rather than restarting.

**What this means:** the preview is blocked on nothing but wall-clock compile time, and every repo-side blocker in its path has been cleared. It is *not* evidence of anything yet — no unit-change list was ever printed, so **the grafana unit's disposition is unrecorded**. This is also not an artifact of `dry-activate`: firebat must build that same torch to switch to 26.05 at all, so the cost is real work discovered early rather than overhead.

## Deviations from Plan

### [Rule 3 — Blocking] systemd stage-1 initrd broke the impermanence rollback

**Found during:** Task 1. **Resolved by:** user decision (Option A) at the prior checkpoint.

26.05 flips `boot.initrd.systemd.enable` to `true` by default, and the systemd stage-1 initrd *asserts* on `boot.initrd.postDeviceCommands` rather than silently dropping it — so ser8 would not evaluate at all. The alternative was pinning `boot.initrd.systemd.enable = false` to defer the work.

Migrated instead: `hosts/ser8/configuration.nix` now declares a stage-1 oneshot.

```nix
initrd.systemd.services.rollback = {
  wantedBy = [ "initrd.target" ];
  after = [ "zfs-import-rpool.service" ];
  before = [ "sysroot.mount" ];
  path = [ pkgs.zfs ];
  unitConfig.DefaultDependencies = "no";
  serviceConfig.Type = "oneshot";
  script = "zfs rollback -r rpool/local/root@blank";
};
```

Verified by evaluation: `boot.initrd.systemd.enable` = `true`, `after` = `["zfs-import-rpool.service"]`, `before` = `["sysroot.mount"]`, `postDeviceCommands` is now empty, and `zfs-import-rpool` genuinely exists in the initrd unit set (so the `After=` points at a real unit rather than a typo).

> **CRITICAL for plan 09-05.** Evaluation cannot prove the new initrd boots. Nothing here is evidence that the rollback still runs at the right moment, and a rollback that silently stops firing looks exactly like a healthy system until `/` starts accumulating state. **ser8's first reboot on 26.05 must confirm impermanence rollback still works** — e.g. write a marker file outside a persisted path, reboot, confirm it did not survive. Treat this as blocking for ser8's activation.

### [Rule 3 — Blocking] `services.resolved` options renamed

**Found during:** Task 1, not anticipated by the plan. **Files:** `modules/common/networking.nix`. **Commit:** `a417618`.

26.05 removed `services.resolved.extraConfig` and renamed `domains`, `dnssec`, `dnsovertls`, and `fallbackDns` into the structured `settings.Resolve` attrset. Every key was rewritten in the new form so no renamed-option warning is emitted (CLAUDE.md treats warnings as failures). The module space-joins `DNS`, `Domains`, and `FallbackDNS` when given as lists, so the rendered `resolved.conf` matches the previous hand-written `[Resolve]` section. Strict-mode's empty `FallbackDNS` behaviour is preserved. No dual-format shim was added.

### [Rule 3 — Blocking, scope expansion] caddy's xcaddy vendor hash was stale under 26.05

**Found during:** Task 2's activation preview. **Files:** `modules/gateway/caddy.nix`. **Commit:** `7a5b7df`.

`pkgs.caddy.withPlugins` assembles a Go vendor tree whose fixed-output hash depends on the caddy and go versions the channel supplies. 26.05 took caddy 2.10.x → 2.11.4, so the pinned hash no longer matched and firebat could not build at all.

**This is a deliberate scope expansion and should be read as one.** `modules/gateway/caddy.nix` is not in Task 2's `<files>` and not in the plan's `files_modified`; the failure was caused by Task 1's channel bump, not by anything in Task 2. The plan's scope-boundary rule would normally push this to deferred items. It was fixed here because **no other plan owns that file** — unlike ser8's declarative-jellyfin blocker, whose remedy is the input refresh that 09-04 already owns. Deferring it would have left the phase's central gate unowned and unproven.

Two things make the hash update safe rather than a blind "accept whatever came back":

- Every input to that hash is locked — the plugin is pinned to an exact commit (`caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac`) and caddy and go come from the locked nixpkgs. The hash is a *derived* value, not a trust anchor over a mutable upstream artifact.
- The old comment claimed the plugin was pinned "for Caddy 2.10.x compatibility", which a hash bump alone does not re-establish. That question was resolved by letting the build answer it: `unit-caddy.service.drv` built successfully against 2.11.4. The comment was updated to match, and the hash now carries a note explaining why it moves with the channel.

### [Plan defect] Acceptance criterion queried the wrong lock node

`nix flake metadata --json | jq -r '.locks.nodes.nixpkgs.original.ref'` reads a node that is not this flake's nixpkgs input — the root input resolves to `nixpkgs_3`. Corrected form, used throughout:

```bash
nix flake metadata --json | jq -r '.locks.nodes[.locks.nodes.root.inputs.nixpkgs].original.ref'
```

### [Plan defect] D-12 stateVersion criterion cannot cover four hosts yet

The criterion loops over all four hosts. pi4 and pi5 cannot evaluate until plan 09-02 re-platforms them. Verified ser8 and firebat only — both `24.11`. **pi4/pi5 stateVersion verification is deferred to 09-02** and must be carried there.

### [Plan defect] Two contradictory instructions about `keys`

Task 3's action mandates a header comment explaining why a `keys`-based comparison is wrong; its acceptance criterion says the file contains no occurrence of `keys`. Both cannot hold. Resolved in favour of the action text — the warning comment is what stops the next reader re-introducing the object assumption. The two occurrences are both inside that comment; executable occurrences are **0** (`grep -v '^\s*#' ... | grep -c 'keys'` → `0`).

### [User decision] Unsigned commits

GPG signing cannot work in this sandboxed session (`~/.gnupg` writes denied by the outer seatbelt). The user authorised `git commit --no-gpg-sign` for this phase. Hooks still ran on every commit; `--no-verify` was never used. **Both commits in this plan are unsigned.**

## Deferred Work

| Item | Deferred to | Why |
|---|---|---|
| `declarative-jellyfin` version assertion | **09-04** | Locked at `3843ca5` (2026-04-06), which supports Jellyfin ≤ 10.11.8; 26.05 ships 10.11.11. Upstream `c758527` (2026-06-10) adds 10.11.11 support. **09-04's input refresh must pull declarative-jellyfin at `c758527` or later.** This is a third-party module, so per the plan the remedy is the input refresh, not a workaround here. |
| ser8 `nix build --dry-run` toplevel + `make dry-activate-ser8` | **09-04** | Both blocked by the assertion above. No activation preview exists for ser8 yet, so no unit-change list can be recorded. |
| `make dry-activate-firebat` completion + grafana unit disposition | **09-04** | Repo-side path is clear; bounded only by an uncached multi-hour `torch` source build that exceeded this session. Re-run resumes from firebat's store. **Must be re-run and its unit list recorded before firebat is switched.** |
| Re-verify `sops -d secrets/firebat.yaml \| grep -c '^grafana_secret_key:'` → `1` | **09-04 or any session with an age identity** | User-attested only; this session could neither decrypt nor read `secrets/`. |
| pi4/pi5 evaluation, stateVersion check, systemd-resolved collision | **09-02** | Pis move to upstream nixpkgs there. No dual-format shim was added. |
| `make check` green | **09-02 at the earliest** | Red until both the jellyfin pin and the Pi collision clear. Accepted as transient by user decision. |

## Verification Status

| # | Plan verification item | Status |
|---|---|---|
| 1 | nixpkgs locked to `nixos-26.05` | PASS (corrected jq expression) |
| 2 | Both x86 dry-run builds + both remote activation previews | **PARTIAL** — firebat dry-run PASS; ser8 dry-run blocked on jellyfin (09-04). **Neither activation preview completed**, so no unit list and no grafana disposition exist for either host |
| 3 | `test-actual-module.sh` exits 0 | PASS |
| 4 | `make check HOSTS=<nonexistent>` non-zero, `make check` zero | PARTIAL — red run observed (`rc=2`) and loop propagation proven by A/B; green run blocked |
| 5 | `make fmt` clean, `statix` no new findings | PASS — `nixfmt --check` and `statix check` clean on all seven changed Nix files |
| 6 | `diff-enabled-services.sh` exits 0 for both x86 hosts | PASS — both exit 0, `+ logind` only, no removals |
| 7 | Grafana `secret_key` supplied from SOPS, no plaintext in tree | PASS by eval + grep; the `sops -d` leg is **user-attested, not executor-verified** |

Plan success criteria 1 (partially), 4, and 5 are met, and criterion 3 is now met in code. **Criterion 2 remains the plan's open gap:** the phase-level `must_have` truth *"ser8 and firebat each receive a real remote activation preview"* is **unmet for both hosts**. Per the plan's own prohibition, the channel bump is therefore **not** recorded as validated — the evidence here is evaluation and derivation-graph resolution, plus a partial firebat build that got as far as caddy. That distinction is not bookkeeping: run 1's caddy hash mismatch was invisible to `nix build --dry-run` and only surfaced under a real build.

## Known Stubs

None. No placeholder values, TODOs, or unwired code paths were introduced. The gaps in this plan are unrun verifications, all listed above.

## Commits

| Commit | Task | Scope |
|---|---|---|
| `a417618` | Task 1 | Channel bump, baseline capture, four 26.05 fixes |
| `866710f` | Task 3 | check-target fix, two validation scripts, shfmt |
| `bd891df` | Task 2 | Grafana `secret_key` from SOPS + the encrypted `secrets/firebat.yaml` |
| `7a5b7df` | Task 2 deviation | caddy xcaddy vendor hash for 26.05 |

All four are unsigned (`--no-gpg-sign`, user-authorised). Hooks ran on every one; `--no-verify` was never used.

## Self-Check: PASSED

All created and modified files exist on disk, `secrets/firebat.yaml` resolves in `HEAD`, and all four recorded commit hashes resolve in git history.

One limit worth stating plainly: the executor could not read `secrets/`, so the committed ciphertext was never inspected — its contents rest entirely on the user's out-of-band `sops -d` check.
