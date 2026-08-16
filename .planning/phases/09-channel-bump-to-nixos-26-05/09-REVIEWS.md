---
phase: 9
reviewers: [codex]
reviewed_at: 2026-08-17T05:02:11Z
plans_reviewed: [09-01-PLAN.md, 09-02-PLAN.md, 09-03-PLAN.md, 09-04-PLAN.md, 09-05-PLAN.md]
---

# Cross-AI Plan Review — Phase 9

> Reviewer: Codex CLI 0.147.0 (model gpt-5.6-sol, reasoning effort high), invoked with `--sandbox danger-full-access` for full repo access.
> This supersedes an earlier gpt-5.6-terra run. All citations are source-grounded against the working tree.

## Codex Review

# Phase 9 Plan Review

## Overall assessment

The migration direction is sound and well researched, but the plans are not execution-ready. Several acceptance checks are incompatible with the actual flake output shape, Plan 02 verifies the Pi build before completing required option migrations, Plan 03 would make a disruptive VPN test part of routine deployment, and Plan 05 performs its definitive runtime checks after making configurations permanent. Overall risk is **HIGH** until these ordering and verification defects are corrected.

## Plan 09-01

### Summary

This is a sensible x86-first migration slice with appropriate fixes for filesystem options, Home Assistant deprecation, Grafana encryption compatibility, and the Actual module. Its principal defect is that the enabled-services baseline is treated as a JSON object even though the flake returns an array.

### Strengths

- The bind-mount fix targets real missing values. `/etc/nixos` and `/var/log` currently have a device and bind option but no `fsType` at [hosts/ser8/impermanence.nix](/Users/bobby/github/catgrep/nixos-config/hosts/ser8/impermanence.nix:172).

- Preserving the Home Assistant resource workaround pending runtime verification is prudent. It is currently both copied into persistent state and included in the service restart triggers at [modules/automation/home-assistant.nix](/Users/bobby/github/catgrep/nixos-config/modules/automation/home-assistant.nix:447).

- The proposed Grafana secret follows the existing runtime-file pattern already used for the admin and SMTP passwords at [modules/gateway/grafana.nix](/Users/bobby/github/catgrep/nixos-config/modules/gateway/grafana.nix:43).

- Wiring the Actual assertion into `make check` is appropriate because that target is the repository-wide evaluation gate at [Makefile](/Users/bobby/github/catgrep/nixos-config/Makefile:141).

### Concerns

- **HIGH:** `enabledServices.<host>` is a JSON array, not an object. The output is produced by `builtins.filter` at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:375). Therefore:

  - `jq -e 'type == "object"'` can never pass.
  - `jq -S` does not sort the array elements.
  - Later `.sabnzbd`, `.frigate`, and `keys` queries are invalid or meaningless.

- **MEDIUM:** The objective says ser8 and firebat are dry-activated, but the plan only runs `nix build --dry-run`. The repository has a distinct remote activation-preview mechanism at [Makefile](/Users/bobby/github/catgrep/nixos-config/Makefile:236). Either run it or describe the result as derivation evaluation only.

- **MEDIUM:** The baseline capture does not explicitly preserve the `make check` exit status. That command evaluates all four hosts at [Makefile](/Users/bobby/github/catgrep/nixos-config/Makefile:146), so a pre-existing failure must be recorded without aborting or being mistaken for success.

- **LOW:** The state-version diff only searches selected configuration paths. Evaluated assertions for all four hosts would be more reliable.

### Suggestions

- Capture enabled services with `jq -S 'sort'` and assert `type == "array"`.

- Add a script that computes `old - new` using `jq -n '$old - $new'` and fails on unexplained removals.

- Record baseline command, timestamp, tool versions, and exit status separately from raw output.

- Either add `make dry-activate-ser8` and `make dry-activate-firebat`, or narrow the plan language to evaluation.

### Risk Assessment

**HIGH.** The implementation changes are reasonable, but a mandatory acceptance check is currently impossible because of the JSON type mismatch.

## Plan 09-02

### Summary

The target Pi architecture is correct: one system constructor, upstream board modules, explicit host entry points, extlinux, and a cached mainline kernel. The task ordering and trust-removal verification need correction.

### Strengths

- The plan correctly identifies the current split between the fork-backed `mkPiSystem` and shared `mkSystem` at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:175) and [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:204).

- New Pi `default.nix` files are required because `mkSystem` imports the host directory, whereas the current Pi helper imports `configuration.nix` directly at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:193).

- Keeping the two kexec outputs is correct. They are independent of the fork-backed SD images at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:292) and consumed by [Makefile](/Users/bobby/github/catgrep/nixos-config/Makefile:308).

- The mainline-kernel assertion directly protects against the undesired vendor-kernel default.

### Concerns

- **HIGH:** Task 1 requires both Pi toplevels to evaluate before Task 2 migrates two fork-only option usages. The current base module reads `boot.loader.raspberryPi` at [modules/raspberrypi/base.nix](/Users/bobby/github/catgrep/nixos-config/modules/raspberrypi/base.nix:49), and pi5 still uses the fork schema at [hosts/pi5/configtxt.nix](/Users/bobby/github/catgrep/nixos-config/hosts/pi5/configtxt.nix:11). Task 1 therefore cannot satisfy its own verification after the fork is removed.

- **HIGH:** Removing the cache from the repository file does not remove it from the developer daemon. The actual installation step is `make update-nix-conf`, which copies the file into `/etc/nix` and restarts the daemon at [Makefile](/Users/bobby/github/catgrep/nixos-config/Makefile:130). That target is not required by the plan’s verification.

- **MEDIUM:** Checking only that the named `nixos-raspberrypi` lock node is gone does not prove all `nvmd` sources left the lock. The current lock already contains several generically named `nixpkgs_*` nodes. Verify source owners or URLs, not only node names.

- **MEDIUM:** The Pi evidence still falls short of the roadmap’s literal “all hosts dry-activate” wording. The repository dry-activate path requires SSH and a target host at [scripts/nixos-rebuild.sh](/Users/bobby/github/catgrep/nixos-config/scripts/nixos-rebuild.sh:74). The plan should explicitly reconcile that criterion with pi4 being disconnected.

- **LOW:** Fork-era Pi recovery guidance remains in [scripts/nixos-rebuild.sh](/Users/bobby/github/catgrep/nixos-config/scripts/nixos-rebuild.sh:44), although its invocation is currently commented out. It should be deleted or rewritten during the replacement.

### Suggestions

- Combine Tasks 1 and 2, or defer all Pi build verification until the base module and config.txt migrations are complete.

- Run `make update-nix-conf`, then verify `/etc/nix/nix.custom.conf` no longer contains the removed cache.

- Search `flake.lock` for `nvmd` URLs after re-locking.

- Record the FOUND-01 evidence limitation explicitly: all four locally evaluate, only reachable hosts receive remote dry-activation previews.

### Risk Assessment

**HIGH.** The architecture is good, but Task 1’s required verification is impossible in its current order, and the daemon trust removal is not actually applied.

## Plan 09-03

### Summary

This plan addresses real regression gaps, but it would make a disruptive VPN manipulation part of every ser8 deployment and does not fully implement the promised DNS, VAAPI, or MQTT guarantees.

### Strengths

- A fan-out is necessary because ser8 currently invokes only the media suite at [deploy.yaml](/Users/bobby/github/catgrep/nixos-config/deploy.yaml:11), while NordVPN tests are separate at [scripts/smoketests/nordvpn/all.sh](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/nordvpn/all.sh:4).

- Frigate and Home Assistant genuinely lack dedicated smoketests despite being enabled at [hosts/ser8/configuration.nix](/Users/bobby/github/catgrep/nixos-config/hosts/ser8/configuration.nix:207).

- The selected HTTP ports match the deployed configuration: Frigate on 80 and Home Assistant on 8123 at [modules/gateway/Caddyfile](/Users/bobby/github/catgrep/nixos-config/modules/gateway/Caddyfile:47).

- A qBittorrent egress comparison is aligned with the actual network-namespace design.

### Concerns

- **HIGH:** Fan-out through the current NordVPN `all.sh` executes `test-anonymity.sh`, which deliberately takes down `wgnord` and waits before restoring it at [scripts/smoketests/nordvpn/test-anonymity.sh](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/nordvpn/test-anonymity.sh:89). It has no cleanup trap, so an intermediate failure can leave the interface down.

- **HIGH:** The VAAPI proposal does not test a Jellyfin or Frigate transcode. It checks device presence, optional `vainfo`, and unit state, even though Frigate specifically configures VAAPI ffmpeg acceleration at [modules/automation/frigate.nix](/Users/bobby/github/catgrep/nixos-config/modules/automation/frigate.nix:78). Passing when `vainfo` is unavailable further weakens the gate.

- **HIGH:** The `.vofi` guard only changes the media helper. Firebat’s gateway test has an independent unconditional pi4 lookup at [scripts/smoketests/gateway/test-caddy.sh](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/gateway/test-caddy.sh:26).

- **HIGH:** Firebat gateway testing still includes `adguard.internal`, whose backend is the disconnected pi4 at [modules/gateway/Caddyfile](/Users/bobby/github/catgrep/nixos-config/modules/gateway/Caddyfile:63). The gateway test iterates every extracted route and fails on a bad route at [scripts/smoketests/gateway/test-caddy.sh](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/gateway/test-caddy.sh:124). This can make Plan 05’s firebat gate impossible.

- **MEDIUM:** “Frigate connected to MQTT” has no defined observable. The source only establishes intended broker settings at [modules/automation/frigate.nix](/Users/bobby/github/catgrep/nixos-config/modules/automation/frigate.nix:65). Unit and HTTP checks do not prove publishing.

- **MEDIUM:** In strict DNS mode, the media helper checks pi4 with `nslookup` but then curls through the system resolver instead of forcing the result at [scripts/smoketests/lib/services.sh](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/lib/services.sh:45). It does not prove that the tested resolver delivered the working route.

- **MEDIUM:** Deliberately making every new check fail has no safe fault-injection mechanism. Doing this by stopping live services conflicts with the reliability goal.

### Suggestions

- Split routine and disruptive NordVPN suites. Keep the new non-mutating confinement check in routine fan-out; invoke the kill-switch test manually with a cleanup trap.

- Run a small known ffmpeg VAAPI decode or encode under the same users and device permissions used by Jellyfin and Frigate.

- Apply the DNS guard to gateway tests too, and remove or explicitly skip the retired AdGuard Caddy route.

- Define MQTT freshness evidence, such as receiving a Frigate-owned topic with a bounded timeout and validating a recent timestamp.

- Test negative paths with mocked `ssh`, `curl`, and command output rather than stopping household services.

### Risk Assessment

**HIGH.** The plan improves coverage but introduces routine disruption and leaves multiple named guarantees only partially tested.

## Plan 09-04

### Summary

The package cleanup is well targeted, but its regression comparisons and Frigate overlay proof are not valid as written.

### Strengths

- Tailscale is currently sourced directly from unstable at [modules/servers/tailscale.nix](/Users/bobby/github/catgrep/nixos-config/modules/servers/tailscale.nix:17), so the move is localized.

- The SABnzbd override and unstable par2 dependency are entirely contained in [modules/media/sabnzbd.nix](/Users/bobby/github/catgrep/nixos-config/modules/media/sabnzbd.nix:15), making full replacement clean.

- Retaining `nixpkgs-unstable` is necessary beyond host packages because dev shells and sagent also use it at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:318).

### Concerns

- **HIGH:** The plan again treats `enabledServices.ser8` as an object. It is an array at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:391). `jq 'keys'` compares array indices, so two different service sets of equal length appear identical. `.sabnzbd` and `.frigate` queries cannot work.

- **HIGH:** A dry-run toplevel build does not execute the Frigate overlay’s `postPatch` guard at [overlays/frigate-tflite-optional.nix](/Users/bobby/github/catgrep/nixos-config/overlays/frigate-tflite-optional.nix:8). The automated verification therefore does not prove the patch applies or that the package builds.

- **MEDIUM:** `packageInfo` cannot reliably supply the requested par2 before/after comparison. It records enabled service packages and the first 50 system packages at [flake.nix](/Users/bobby/github/catgrep/nixos-config/flake.nix:461), while par2 is only embedded in SABnzbd’s wrapper path at [modules/media/sabnzbd.nix](/Users/bobby/github/catgrep/nixos-config/modules/media/sabnzbd.nix:68).

- **MEDIUM:** The Home Manager warning baseline is recorded in `.planning/STATE.md` at [.planning/STATE.md](/Users/bobby/github/catgrep/nixos-config/.planning/STATE.md:83), but the plan only proposes documenting its disappearance in a summary. The authoritative state remains stale.

- **MEDIUM:** Task 1 asks for release-branch changes and the blanket input refresh to be separate commits, but places both in the same executor task. If task-level atomic commits are used, the requested bisection boundary will not exist.

### Suggestions

- Compare service arrays directly with sorted set differences.

- Run a real Frigate package build, then test the exact startup import path under the filtered `PYTHONPATH`.

- Evaluate package versions directly, for example `pkgs.par2cmdline-turbo.version`, rather than relying on `packageInfo`.

- Add `.planning/STATE.md` to the plan and replace the old accepted-warning decision.

- Split release alignment and blanket input refresh into separate tasks and commits.

### Risk Assessment

**HIGH.** Package changes are sensible, but the service regression comparison can miss removals and the overlay decision lacks executable evidence.

## Plan 09-05

### Summary

The rollout sequencing is close to correct, and the human checks target the right runtime-only risks. However, the checks occur too late, state backups are underspecified, and the Home Assistant cleanup cannot remove or permanently deploy the persisted resource file correctly.

### Strengths

- The repository genuinely distinguishes temporary activation from permanent switching at [scripts/nixos-rebuild.sh](/Users/bobby/github/catgrep/nixos-config/scripts/nixos-rebuild.sh:245).

- A real Grafana notification is the correct end-to-end check for contact-point decryption.

- Backing up Home Assistant and Grafana before major migrations is appropriate.

- The Pi evidence language correctly avoids equating evaluation with a boot.

### Concerns

- **HIGH:** The definitive Grafana notification and camera-dashboard checks happen after `make switch-*`. The repository’s `test` operation is specifically the reversible activation stage, while `switch` changes the boot default at [scripts/nixos-rebuild.sh](/Users/bobby/github/catgrep/nixos-config/scripts/nixos-rebuild.sh:251). These checks should gate the permanent switch.

- **HIGH:** “Take a copy” is not a safe database backup procedure. The plan gives no destination, consistency mechanism, ownership, checksum, or restore command. `/var/lib/hass` is persistent state at [hosts/ser8/impermanence.nix](/Users/bobby/github/catgrep/nixos-config/hosts/ser8/impermanence.nix:75), and Grafana permits UI-side database changes at [modules/gateway/grafana.nix](/Users/bobby/github/catgrep/nixos-config/modules/gateway/grafana.nix:106). Use a ZFS snapshot or quiesced copy, and SQLite’s backup mechanism for `grafana.db`.

- **HIGH:** Removing the Nix tmpfiles rule does not delete the existing persistent `/var/lib/hass/.storage/lovelace_resources`. The file is currently copied at [modules/automation/home-assistant.nix](/Users/bobby/github/catgrep/nixos-config/modules/automation/home-assistant.nix:437), while the parent state survives reboots. The post-removal visual test could therefore still be testing the stale file.

- **HIGH:** If the card does not render, the plan says to keep the workaround. A workaround that produces no rendered card is not proven load-bearing. That branch requires diagnosis, not acceptance.

- **HIGH:** Task 4 can change Home Assistant Nix after ser8 was permanently switched, but it does not explicitly repeat `dry-activate -> test -> visual check -> switch`. `make smoketests-ser8` alone does not deploy the edited source.

- **HIGH:** The firebat gateway suite may already be red because it tests the Caddy route pointing to disconnected pi4, as described under Plan 03.

- **MEDIUM:** The plan repeatedly says “booted generation,” but `switch` does not reboot. It activates the configuration and selects it as the next boot default. The distinction matters for bootloader and early-boot regressions.

- **MEDIUM:** Counting at least two `system-*` profile links proves historical generations exist, but not that the previous generation is bootable or selected in the boot menu.

### Suggestions

- Put the human dashboard check between `make test-ser8` and `make switch-ser8`.

- Put the Grafana notification check between `make test-firebat` and `make switch-firebat`.

- Define exact, consistent backups and restore commands. Store them on a persistent backup dataset and record checksums.

- When removing the Lovelace storage resource, explicitly back up and delete the persisted file, restart HA, verify the card, then permanently switch the final configuration. Restore both the file and Nix rule if the test fails.

- Replace “booted generation” with “activated and selected as boot default,” unless an explicit reboot test is added.

### Risk Assessment

**HIGH.** Permanent activation currently precedes the strongest runtime checks, and the Home Assistant cleanup can leave stale state or an undeployed final configuration.

## Required replanning before execution

At minimum, fix these blockers:

1. Correct every `enabledServices` assertion to operate on arrays.
2. Move Pi build verification after all fork-only options are migrated.
3. Apply and verify the daemon cache removal, not just the repository file.
4. Keep the disruptive VPN kill-switch test out of routine fan-out.
5. Resolve the disconnected pi4 Caddy route before requiring firebat smoketests.
6. Replace dry-run Frigate verification with a real package and import-path test.
7. Move Grafana and Home Assistant human checks before permanent switching.
8. Define consistent backups and explicitly remove persistent Lovelace state during cleanup.
---

## Consensus Summary

Single-reviewer run (Codex only), so this synthesizes Codex's own findings; where the earlier lower-effort run overlapped, agreement is noted.
Codex's verdict: migration direction is sound and well researched, but the plans are **not execution-ready** — overall risk HIGH until the 8 blockers in "Required replanning before execution" are fixed.

### Agreed Strengths

- Fork boundary, bind-mount `fsType` fixes, Grafana secret-key handling, SABnzbd/Tailscale unstable cleanup, and kexec retention are all correctly located and scoped (verified citations throughout).
- Staged ordering (x86 tracer first, Pi evaluation-only, ser8-before-firebat) matches the repo's deployment mechanics.
- Both model runs agreed on: the disruptive `test-anonymity.sh` in routine fan-out, the Frigate overlay dry-run proving nothing, the missing MQTT observable, and the post-switch HA cleanup lacking its own deployment ladder.

### Agreed Concerns (the 8 replanning blockers)

1. **`enabledServices.<host>` is a JSON array, not an object** (`flake.nix:375`) — the `jq 'type == "object"'` / `keys` / `.sabnzbd` assertions in Plans 09-01 and 09-04 can never pass or silently compare indices. Every enabledServices assertion must operate on arrays.
2. **Plan 09-02 Task 1 verification is impossible in its current order** — it requires Pi toplevels to evaluate before Task 2 migrates the fork-only `boot.loader.raspberryPi` reads (`modules/raspberrypi/base.nix:49`, `hosts/pi5/configtxt.nix:11`). Move Pi build verification after the option migrations.
3. **Daemon cache removal is not actually applied** — editing `etc/nix/nix.custom.conf` in-repo does nothing without `make update-nix-conf` (`Makefile:130`); the plan never runs or verifies it.
4. **Disruptive VPN kill-switch test in routine fan-out** — `test-anonymity.sh` downs `wgnord` with no cleanup trap (`scripts/smoketests/nordvpn/test-anonymity.sh:89`); split routine vs. disruptive suites.
5. **Firebat gate can be structurally red** — `test-caddy.sh` has an unconditional pi4 lookup (`:26`) and iterates the `adguard.internal` route whose backend is the disconnected pi4 (`Caddyfile:63`); Plan 09-05's firebat smoketest gate may be impossible without resolving the retired route.
6. **Frigate overlay "validation" proves nothing** — dry-run builds never execute the overlay's `postPatch` guard (`overlays/frigate-tflite-optional.nix:8`); a real package build + import-path test is required.
7. **Definitive runtime checks happen after permanent switch** — the Grafana notification and camera-dashboard human checks must gate `make switch-*`, sitting between `test` and `switch` (the repo's own reversible-activation design, `scripts/nixos-rebuild.sh:245-257`).
8. **HA Lovelace cleanup leaves stale persistent state** — removing the tmpfiles rule doesn't delete the existing `/var/lib/hass/.storage/lovelace_resources`; backups are underspecified ("take a copy" of live SQLite databases) — needs ZFS snapshot/quiesced copy, explicit deletion, restore commands.

### Divergent Views

The two Codex runs (terra vs. sol) disagreed on one point: terra flagged the stale Pi recovery guidance in `scripts/nixos-rebuild.sh` as HIGH; sol downgraded it to LOW after verifying its invocation is currently commented out (`:44`). Sol's array-type finding, task-ordering finding, daemon-cache finding, and pre-switch-gating finding were all missed by the lower-effort run — treat sol's review as authoritative.
