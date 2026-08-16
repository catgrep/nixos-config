---
phase: 09-channel-bump-to-nixos-26-05
plan: 05
subsystem: infra
tags: [channel-bump, activation, zfs-snapshot, impermanence, home-assistant, lovelace, systemd-boot, frigate, go2rtc]
status: complete
requires:
  - 09-02 (Pi hosts off the fork, so the flake evaluates for every host)
  - 09-03 (committed pre-bump ser8 smoketest baseline, ZFS feature-flag guard)
  - 09-04 (all inputs re-locked onto 26.05, make check green)
  - 09-06 (gateway suite repair, consumed by plan 07 rather than by this plan)
provides:
  - ser8 running NixOS 26.05 activated and selected as its boot default (generation 268)
  - a named, quiesced ZFS snapshot of ser8's persistent dataset with both restore procedures written down
  - the declarative lovelace-resources workaround removed from the Nix source and from Home Assistant's persistent storage
  - four recorded ser8 smoketest runs (pre-bump, temporary, post-edit temporary, post-switch) for section-by-section comparison
  - a recorded bootloader entry list proving generation 267 (25.11) is still selectable
  - a diagnosed, evidence-backed classification of the Frigate live-stream 403 as pre-existing and not bump-caused
affects:
  - 09-07 (firebat activation follows the same ladder; ser8's reboot proofs are still outstanding)
  - modules/automation/home-assistant.nix
  - modules/automation/frigate.nix (go2rtc api.origin decision deferred to its own plan)
tech-stack:
  added: []
  patterns:
    - "Quiesce the service, snapshot the ZFS dataset, restart, then record both restore procedures before any activation command runs"
    - "Run the whole rollout ladder (dry-activate, test, smoketests, human check) twice when a configuration edit lands mid-plan, so no change reaches the switch unverified"
    - "Prove a post-switch smoketest run is live rather than replayed by diffing it against the prior run and pointing at the field that must differ"
key-files:
  created:
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/dry-activate-ser8-2605-task1.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/dry-activate-ser8-2605-task3.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2605-task1.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2605-task3.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2605-task5.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/bootctl-list-ser8-postswitch.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/lovelace_resources.pre-removal.json
  modified:
    - modules/automation/home-assistant.nix
    - .planning/phases/09-channel-bump-to-nixos-26-05/deferred-items.md
decisions:
  - "Remove the declarative lovelace-resources workaround outright: 26.05 selects resource_mode yaml automatically when custom lovelace modules are present, and the generated configuration.yaml lists advanced-camera-card.js itself"
  - "Delete the persisted /var/lib/hass/.storage/lovelace_resources file explicitly after removing its Nix rule, because /var/lib/hass survives the impermanence rollback and the file would otherwise outlive the rule"
  - "Classify the Frigate live-stream 403 as pre-existing on journal evidence predating the first 26.05 activation, and defer the go2rtc api.origin remedy rather than slip a CSRF-protection tradeoff into an activation plan"
  - "Treat the identical post-switch smoketest result as the pass condition, evidenced by a fresh run whose live Frigate MQTT payload size differs from the prior run"
  - "Do not reboot ser8 in this phase; the impermanence rollback proof and the ZFS userland/kmod skew recovery are recorded as outstanding rather than claimed"
coverage:
  - id: D1
    description: "ser8 has NixOS 26.05 activated and selected as its boot default, with the previous generation still selectable in the bootloader"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "ssh ser8 nixos-version -> 26.05.20260817.0dd31db; readlink -f /nix/var/nix/profiles/system -> nixos-system-ser8-26.05...; sudo bootctl list -> generation 268 (default), generation 267 present"
        status: pass
    human_judgment: false
  - id: D2
    description: "ser8's persistent state captured in a named, quiesced ZFS snapshot with both restore procedures recorded"
    verification:
      - kind: integration
        ref: "ssh ser8 zfs list -t snapshot rpool/safe/persist -> rpool/safe/persist@pre-26.05-2026-08-17T085547Z"
        status: pass
    human_judgment: false
  - id: D3
    description: "The full ser8 smoketest suite passes area by area against the switched system, matching the temporary-activation runs and beating the pre-bump baseline"
    verification:
      - kind: integration
        ref: "make smoketests-ser8 (baseline/smoketests-ser8-2605-task5.txt): media 8/8, nordvpn 3/4, zfs 7/7, vaapi 5/5, frigate 5/5, home-assistant 3/3"
        status: pass
    human_judgment: false
  - id: D4
    description: "The lovelace-resources workaround is gone from the Nix source and from Home Assistant's persistent storage, with the camera card rendering exactly once"
    verification:
      - kind: integration
        ref: "grep -c lovelace_resources modules/automation/home-assistant.nix -> 0; ssh ser8 test -e /var/lib/hass/.storage/lovelace_resources -> absent"
        status: pass
      - kind: manual_procedural
        ref: "Task 4 human dashboard check: cache-free reload, card renders once, one resource-list entry, no duplicate custom-element error"
        status: pass
    human_judgment: true
    rationale: "Whether a custom Lovelace card renders, and how many times, is only observable in a browser; no smoketest in this repository covers the rendered dashboard."
  - id: D5
    description: "The impermanence rollback and ZFS kmod skew recovery on the new generation"
    verification:
      - kind: integration
        ref: "PENDING REBOOT: /IMPERMANENCE-MARKER-09-05 must not survive the first 26.05 boot; zfs-kmod must reach 2.4.3 so zfs-scrub.service stops failing"
        status: unknown
    human_judgment: false
requirements-completed: [FOUND-01]
metrics:
  duration: ~1h of executor time across 9h40m wall clock (two human gates)
  completed: 2026-08-17
actuals:
  tokens: 15672
  tasks: 5
  commits: 4
---

# Phase 09 Plan 05: Activate 26.05 on ser8 Summary

ser8 has NixOS 26.05 activated and selected as its boot default, reached through the full reversible ladder twice, with the stale Lovelace resources workaround removed after a human dashboard check proved 26.05 loads the card on its own.

## Performance

- Duration: ~1h of executor time (01:52-02:15 for Task 1, 11:00-11:34 for Tasks 3 through 5), across 9h40m of wall clock dominated by the two human gates
- Started: 2026-08-17T08:52Z
- Completed: 2026-08-17T18:34Z
- Tasks: 5/5
- Files modified: 1 source file (`modules/automation/home-assistant.nix`), 11 planning artifacts

## Accomplishments

- ser8 runs NixOS 26.05 (`26.05.20260817.0dd31db`, Yarara) as generation 268, the default bootloader entry, with generation 267 (25.11 Xantusia) still listed and selectable.
- Every definitive check happened while the activation was still reversible. The switch was the last command in the plan, not the first.
- The Lovelace resources workaround is gone from both places it lived: the Nix module and Home Assistant's persistent storage.
- The Task 4 dashboard observation turned a suspected regression into a diagnosed pre-existing defect with journal evidence three days older than the first 26.05 activation.

## Task Commits

1. **Task 1: Snapshot ser8, activate 26.05 reversibly, run the full suite** - `1e76c90` (docs)
2. **Task 2: Human dashboard checkpoint** - no commit (human gate)
3. **Task 3: Resolve the lovelace resources workaround, re-activate reversibly** - `65b65ad` (refactor, module source)
4. **Task 4: Human dashboard checkpoint on the final configuration** - `fb0b982` (docs, the diagnosis the checkpoint produced)
5. **Task 5: Make the ser8 configuration the boot default** - `38722d7` (docs, post-switch evidence)

## Task 1: Backup and first reversible activation

### The snapshot

| Field | Value |
|---|---|
| Snapshot | `rpool/safe/persist@pre-26.05-2026-08-17T085547Z` |
| Created | Mon 2026-08-17 01:55 PDT (2026-08-17T08:55:47Z) |
| Quiesced | `home-assistant.service` stopped for the snapshot and restarted after, ~1s downtime |
| Dataset | `rpool/safe/persist`, mountpoint `legacy` at `/persist`, `snapdir=hidden` |

`/var/lib/hass` and `/var/lib/frigate` are both persisted through `/persist`, so this one dataset snapshot covers both.

**Restore procedure A, per-file (non-destructive).**
Read the old files back out of the snapshot directory without disturbing anything else.
The snapshot directory is hidden but reachable by explicit path.

```bash
sudo ls /persist/.zfs/snapshot/pre-26.05-2026-08-17T085547Z/
sudo systemctl stop home-assistant
sudo cp -a /persist/.zfs/snapshot/pre-26.05-2026-08-17T085547Z/var/lib/hass/.storage/<file> \
           /persist/var/lib/hass/.storage/<file>
sudo systemctl start home-assistant
```

**Restore procedure B, whole-dataset rollback (destructive).**
This reverts the entire persistent dataset to its 08:55:47Z state.

```bash
sudo systemctl stop home-assistant frigate
sudo zfs rollback rpool/safe/persist@pre-26.05-2026-08-17T085547Z
sudo systemctl start home-assistant frigate
```

**Caveat, recorded because it is the part that bites.**
`zfs rollback` discards every snapshot of that dataset taken after the one named.
It also discards every write to `/persist` since 08:55:47Z, which includes Frigate's persisted state, all Home Assistant history written since, and the `/persist/backups/09-05/` directory created in Task 3.
Prefer procedure A unless the whole dataset is known bad.

The impermanence rollback snapshot `rpool/local/root@blank` was confirmed present by the existing plan 03 ZFS check rather than by duplicated logic (`scripts/smoketests/ser8/test-zfs-health.sh`, Impermanence Rollback Tests section).

### Task 1 dry-activate preview

Full text: `baseline/dry-activate-ser8-2605-task1.txt`.
This was the whole-channel activation, so the unit list is long. Summarised:

| Category | Count | Notable members |
|---|---|---|
| would stop | 57 | every media service, `frigate`, `go2rtc`, `home-assistant`, `mosquitto`, `netns@wgnord`, `wgnord`, all 8 Prometheus exporters, all 5 `zfs-*` units, Samba, `nscd`, `avahi-daemon` |
| would NOT stop (changed) | 13 | `systemd-logind`, `systemd-journal-flush`, `user@1000`, five `systemd-fsck@*` |
| would restart | 10 | `nginx`, `sshd`, `nix-daemon`, `systemd-journald`, `systemd-networkd`, `systemd-resolved`, `systemd-udevd`, `tailscaled`, `etc-nixos.mount`, `var-log.mount` |
| would reload | 3 | `dbus`, `firewall`, `reload-systemd-vconsole-setup` |
| would start | 55 | the stop list minus `systemd-oomd.service` and `systemd-udev-settle.service` |
| other | 2 | "would restart systemd"; "would modify rendered secret: nzbget.conf" |

`systemd-resolved` restarting is the 26.05 `services.resolved` structured-settings migration landing; it restarted cleanly and DNS stayed up.

### Task 1 smoketest run

`make test-ser8` activated 26.05 temporarily, then `make smoketests-ser8` ran against it (`baseline/smoketests-ser8-2605-task1.txt`, exit 1).
Post-run state: `nixos-version` reported `26.05.20260817.0dd31db`, `zpool status -x` reported both pools healthy, and the boot default was still `system-267-link` (25.11).
The switch target was not run.

## Task 2: First dashboard observation (human gate)

Outcome: **the card rendered, and the workaround was found to be redundant under 26.05's automatic resource-mode selection**.
The plan routes both the "renders twice" and the "renders once, resource listed once" observations to the same action, remove, and that is the branch Task 3 took.

The supporting server-side evidence, recorded in commit `65b65ad`, is unambiguous about the redundancy.
26.05 selects `resource_mode: yaml` automatically when custom Lovelace modules are present, and the generated `configuration.yaml` lists `advanced-camera-card.js?7.27.4` itself.
The declarative storage file was registering the same card a second time and had gone stale doing it: `baseline/lovelace_resources.pre-removal.json` pins `advanced-camera-card.js?7.6.5`, twenty-one minor versions behind what 26.05 was already loading.

## Task 3: Removing the workaround

Branch taken: **remove**, on the duplicate observation from Task 2.

Source edits in `modules/automation/home-assistant.nix` (commit `65b65ad`, 25 lines changed):

- removed the `lovelaceResources` let-binding
- removed the `systemd.tmpfiles` `C+` rule that copied it into `/var/lib/hass/.storage/`
- removed the now-unused `advancedCameraCard` binding
- removed the restart trigger that referenced the same derivation

Host-side deletion, which is the step the review flagged and the one a source edit alone does not perform.
`/var/lib/hass` is persisted through `/persist`, so the file outlives the Nix rule that created it, and skipping this would have left the Task 4 check reading exactly the stale file the change was meant to remove.

| Item | Value |
|---|---|
| Backup on ser8 | `/persist/backups/09-05/lovelace_resources.pre-26.05-2026-08-17T180923Z` (197 bytes, `hass:hass`, mode 0600) |
| Backup in repo | `baseline/lovelace_resources.pre-removal.json` |
| Post-deletion check | `ssh ser8 'test -e /var/lib/hass/.storage/lovelace_resources'` exits non-zero (re-confirmed after the Task 5 switch) |
| Source check | `grep -c 'lovelace_resources' modules/automation/home-assistant.nix` outputs `0` |

`home-assistant.service` was restarted after the deletion so it re-read its resource state.

### Task 3 dry-activate preview

Full text: `baseline/dry-activate-ser8-2605-task3.txt`.
Scoped to the edit, as expected for a single-module change on an already-activated generation:

- would start: `home-assistant.service`, `systemd-tmpfiles-resetup.service`
- would stop: `home-assistant.service`, `systemd-tmpfiles-resetup.service`
- two warnings about the `media` UID/GID change not being applied (pre-existing, see Deferred below)

`make test-ser8` re-activated, `make smoketests-ser8` re-ran (`baseline/smoketests-ser8-2605-task3.txt`, exit 2).
The switch target was still not run; the boot default was still `system-267-link`.

## Task 4: Second dashboard observation (human gate) and the diagnosis it produced

Approved outcome, after a cache-free reload on the direct URL: **the card renders exactly once, one resource-list entry, no duplicate custom-element registration error**.

The first attempt at this check reported a `TypeError` and a doubled card, which turned out to be a stale browser service-worker cache still serving the pre-deletion resource list.
A cache-bypassing reload cleared it. That is why the plan's step 1 says cache-bypassing refresh, and it earned its place.

The same observation surfaced every camera's **live stream failing** with a 403 and a 500.
This was diagnosed rather than accepted, and the finding is recorded in full in `deferred-items.md`:

- **Mechanism.** go2rtc rejects the cross-origin WebSocket upgrade that Home Assistant's Frigate proxy forwards. Reproduced on ser8 localhost against the running production go2rtc: upgrade with no `Origin` header returns `101`, the same upgrade with `Origin: https://hass.shad-bangus.ts.net` returns `403`. No Caddy, Tailscale, or firebat involvement.
- **Pre-existing, with evidence.** Identical 403s for the same three cameras on the same endpoint appear in ser8's journal at `2026-08-14T01:08:21-07:00`, three days before the first 26.05 activation at `2026-08-17T02:03:16-07:00`. The journal is continuous back to 2026-07-23, so the pre-bump 25.11 system produced the same failure.
- **Remedy verified but deliberately not applied.** Setting go2rtc's `api.origin` to `"*"` fixes it, proven on two throwaway go2rtc instances from the same store binary and config. Not applied here on three counts: not bump-caused, the fix lives in `modules/automation/frigate.nix` while this plan's only file is `home-assistant.nix`, and `origin: "*"` trades away a CSRF protection the repository owner should give up explicitly rather than have an activation plan slip in.
- **Why no test caught it.** Frigate moved 0.16.3 to 0.17.2 in this bump, unremarked by the plan, alongside the Home Assistant Frigate component 5.11.0 to 5.15.3 and go2rtc 1.9.12 to 1.9.14. The Frigate smoketest checks HTTP reachability and MQTT publication only. Nothing in the suite exercises the live-stream path, which is precisely the blind spot that let a months-old defect stay invisible.

## Task 5: The switch

`make switch-ser8` was run and its confirmation prompt answered `y`.

**`NO_CONFIRM` was not set for any command in this plan.**
The `confirm()` function in `scripts/lib/prompt.sh` executed and read its answer from stdin; the override branch was never taken.
The answer relayed the user's explicit Task 4 approval to proceed.

### What the switch did, stated precisely

ser8 has the 26.05 configuration **activated and selected as its boot default**.
**ser8 has not been rebooted.**
`readlink -f /run/booted-system` still resolves to the 25.11 system, and nothing in this phase produces evidence about bootloader or early-boot behaviour on the new generation.

| Fact | Before switch | After switch |
|---|---|---|
| `nixos-version` | `26.05.20260817.0dd31db` | `26.05.20260817.0dd31db` |
| `/run/current-system` | `...-ser8-26.05...` (temporary) | `...-ser8-26.05...` |
| `/run/booted-system` | `...-ser8-25.11...` | `...-ser8-25.11...` (unchanged, no reboot) |
| `/nix/var/nix/profiles/system` | `system-267-link` (25.11) | `system-268-link` (26.05) |
| Generation count | 9 | 10 |
| `systemctl is-system-running` | `degraded` (zfs-scrub) | `running`, zero failed units |
| `zpool status -x` | all pools healthy | all pools healthy |

The activation also **updated systemd-boot on the ESP from 258.7 to 260.2**, rewriting `/boot/EFI/systemd/systemd-bootx64.efi` and `/boot/EFI/BOOT/BOOTX64.EFI`.
The EFI boot manager binary is therefore already 26.05's while the booted kernel is still 25.11's.
This is normal for a switch and both generations' Boot Loader Specification entries remain valid, but it is recorded because it is a bootloader-level change made without a reboot to confirm it.

The `degraded` to `running` change is not the ZFS skew being fixed.
`zfs-scrub.service` was in the activation's stop/start list, so its failed state was reset (`ActiveState=inactive`, `Result=success`).
The underlying userland/kmod skew is unchanged and the unit will fail again on its next trigger (timer next due 2026-08-24) until ser8 reboots.

### Bootloader entries

Full text: `baseline/bootctl-list-ser8-postswitch.txt` (23 entries).
The two that matter:

```
title: NixOS (Generation 268 NixOS Yarara 26.05.20260817.0dd31db (Linux 6.18.44), built on 2026-08-17) (default)
   id: nixos-generation-268.conf
title: NixOS (Generation 267 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-08-13)
   id: nixos-generation-267.conf
```

Generations 259 through 268 are all present as Type #1 BLS entries on the EFI System Partition.
This is the fact that matters for recovery: profile symlinks prove generations exist, but the bootloader entry list proves generation 267 can actually be chosen at the boot menu.

### Post-switch smoketest run and section-by-section comparison

`make smoketests-ser8` was run against the switched system (`baseline/smoketests-ser8-2605-task5.txt`, exit 2).

| Area | Pre-bump 25.11 baseline | Task 1 (26.05 temporary) | Task 3 (26.05 + HA edit) | Task 5 (26.05 switched) |
|---|---|---|---|---|
| media (Jellyfin, Sonarr, Radarr, Bazarr, qBittorrent, Prowlarr, SABnzbd, NZBGet) | 8/8 pass | 8/8 pass | 8/8 pass | **8/8 pass** |
| nordvpn: veth interfaces | pass | pass | pass | **pass** |
| nordvpn: forwarding | FAIL (stale pi4 resolver) | FAIL (same) | FAIL (same) | **FAIL (same, deferred)** |
| nordvpn: qbittorrent | FAIL (tunnel down) | pass | pass | **pass** |
| nordvpn: qbittorrent confinement | FAIL 0/3 | pass 3/3 | pass 3/3 | **pass 3/3** |
| ZFS health + impermanence + feature flags | 7/7 pass | 7/7 pass | 7/7 pass | **7/7 pass** |
| VAAPI | 5/5 pass | 5/5 pass | 5/5 pass | **5/5 pass** |
| Frigate | 5/5 pass | 5/5 pass | 5/5 pass | **5/5 pass** |
| Home Assistant | 3/3 pass | 3/3 pass | 3/3 pass | **3/3 pass** |
| nordvpn suite total | 1/4 | 3/4 | 3/4 | **3/4** |
| ser8 suite total | 5/6 | 5/6 | 5/6 | **5/6** |

Every area green pre-bump is green post-switch, no section is missing, and the NordVPN area improved from 1/4 to 3/4 because the tunnel came back up between the baseline capture and this plan.
The single red is `nordvpn/test-forwarding.sh`, which hard-codes the retired pi4 resolver `192.168.68.56`; it was already red pre-bump and is deferred to the `.vofi` re-establishment work in Phase 10.

**On the equality being real rather than stale.**
The Task 5 output is identical to Task 3 in every assertion, which is the pass condition here, not a suspicious one.
It is a genuinely fresh run: diffing the two transcripts yields exactly one differing line, the live Frigate MQTT stats payload size (`55101 bytes` at Task 3, `55112 bytes` at Task 5), which only a live subscription to `frigate/stats` produces.

## Files Created/Modified

- `modules/automation/home-assistant.nix` - removed the `lovelaceResources` let-binding, its tmpfiles copy rule, the unused `advancedCameraCard` binding, and the restart trigger
- `.planning/phases/.../baseline/dry-activate-ser8-2605-task1.txt` - whole-channel activation preview
- `.planning/phases/.../baseline/dry-activate-ser8-2605-task3.txt` - post-edit activation preview
- `.planning/phases/.../baseline/smoketests-ser8-2605-task{1,3,5}.txt` and `.status` - the three 26.05 runs
- `.planning/phases/.../baseline/bootctl-list-ser8-postswitch.txt` - bootloader entry list after the switch
- `.planning/phases/.../baseline/lovelace_resources.pre-removal.json` - the deleted file, kept in the repo alongside the on-host backup
- `.planning/phases/.../deferred-items.md` - three new 09-05 entries (media UID/GID drift, Frigate 403 diagnosis, ZFS kmod skew)

## Decisions Made

- **Remove the Lovelace workaround rather than re-justify it.** 26.05 selects `resource_mode: yaml` automatically when custom Lovelace modules are present and lists `advanced-camera-card.js?7.27.4` in the generated `configuration.yaml`. The declarative storage file was a workaround for the old storage mode, had gone stale at 7.6.5, and was producing the duplicate the Task 2 check found.
- **Delete the persisted file explicitly, with a backup.** Removing the Nix rule does not remove state under `/var/lib/hass`.
- **Defer the go2rtc `api.origin` fix.** Not bump-caused, wrong file for this plan, and it trades away a CSRF protection that the repository owner should surrender explicitly.
- **Do not reboot ser8.** Out of scope for this plan and left as a separate, user-gated decision.

## Deviations from Plan

### Auto-fixed and handled inline

**1. [Rule 3 - Blocking] Stale browser service-worker cache produced a false failure at the Task 4 gate**
- **Found during:** Task 4
- **Issue:** The first Task 4 observation reported a `TypeError` and a doubled card, which read as the Task 3 removal having broken something.
- **Fix:** A cache-bypassing reload on the direct URL cleared it; the card then rendered exactly once with one resource-list entry.
- **Verification:** Human re-observation, approved.
- **Committed in:** no source change required.

**2. [Rule 4 - Architectural, deferred not applied] Frigate live-stream 403**
- **Found during:** Task 4
- **Issue:** Every camera's live stream failed. Initially indistinguishable from a bump regression.
- **Resolution:** Diagnosed to go2rtc's cross-origin WebSocket check and proven pre-existing on journal evidence three days older than the first 26.05 activation. The remedy was verified on throwaway instances but deliberately not applied, because it is a security tradeoff in a different module belonging to its own plan.
- **Committed in:** `fb0b982` (documentation only; `modules/automation/frigate.nix` untouched).

---

**Total deviations:** 1 inline fix, 1 architectural finding deferred with a recorded diagnosis.
**Impact on plan:** None on scope. The plan's only source file remained `modules/automation/home-assistant.nix`.

## Issues Encountered

- **The plan's `<automated>` verify for Task 1 and Task 5 chains on `make smoketests-ser8` succeeding.** That command exits non-zero on ser8 both before and after the bump because of the deferred stale-pi4-resolver test, exactly as 09-03 recorded. The comparison was therefore done per-area against the committed baseline, which is the method 09-03's decision prescribes, rather than on top-level exit status.
- **`make switch-ser8` prompts interactively and the executor has no TTY.** Answered by writing `y` to the command's stdin, which runs the real `confirm()` path. The `NO_CONFIRM` override, which the plan prohibits, was never set.

## Outstanding: two proofs that require a reboot

**ser8 has not been rebooted, and neither of these can be claimed until it is.**
Both belong to 09-07 or to phase verification.

1. **Impermanence rollback on the new initrd.** The marker file `/IMPERMANENCE-MARKER-09-05` is planted on `rpool/local/root` and confirmed still present. 09-01 migrated ser8's erase-your-darlings rollback from `postDeviceCommands` to a `boot.initrd.systemd` stage-1 oneshot because 26.05 asserts on the old form under the new systemd-initrd default. Evaluation cannot prove that new initrd boots or that the rollback fires. **The proof is that the marker file does NOT survive the first 26.05 boot.** If it survives, the root rollback did not run and impermanence is silently broken.
2. **ZFS userland/kmod skew recovery.** ser8 currently runs `zfs-2.4.3-1` userland against `zfs-kmod-2.3.7-1` from the booted 25.11 kernel. `zfs scrub` is rejected with "the loaded zfs module does not support an option for this operation. A reboot may be required." Pools stay healthy and importable, and the failed unit state was reset by the switch, but the skew is unchanged. **The proof is that after the reboot `zfs version` reports matching userland and kmod and `zfs-scrub.service` completes.**

Recovery path if the reboot goes badly: select **generation 267** from the systemd-boot menu.
It is confirmed present in `bootctl list` and is the pre-bump 25.11 system.
The repository's `make rollback-HOST` target prints `TODO` and is not a recovery path.

## Also deferred (recorded in deferred-items.md)

- **`media` UID/GID drift on ser8** (992 to 1100, 1002 to 1100). A year old, predates the bump, and activation refusing the renumber is the protective behaviour. Fixing it requires a deliberate re-chown across the media pool.
- **Frigate 0.16.3 to 0.17.2** moved in this bump unremarked by the plan, alongside the HA Frigate component 5.11.0 to 5.15.3 and go2rtc 1.9.12 to 1.9.14. Deserves its own verification of recording, detection, and retention behaviour.
- **go2rtc `api.origin`** and a smoketest covering the live-stream path.

## User Setup Required

None for this plan.
The one outstanding user decision is whether and when to reboot ser8, which is deliberately outside this plan's scope.

## Next Phase Readiness

- **09-07 (firebat) is unblocked.** D-05's ordering is satisfied: ser8 activated first, its suite is green area by area, and its previous generation is confirmed selectable.
- **Carry into 09-07:** budget hours for firebat's `subgen` torch source build (no binary cache at the pinned rev), and the x86 remote-build workaround (`nix copy --derivation` plus `ssh nix-store --realise`) since the nix daemon cannot ssh to the targets.
- **Carry into phase verification:** the two reboot proofs above are the phase's last unmet must-have on ser8.

## Self-Check: PASSED

All 9 referenced artifact paths exist on disk and all 4 task commits (`1e76c90`, `65b65ad`, `fb0b982`, `38722d7`) are present in `git log`.
Live-host claims re-verified against ser8 after the switch: `nixos-version`, `readlink -f /nix/var/nix/profiles/system`, `readlink -f /run/booted-system`, generation count, `sudo bootctl list`, `zpool status -x`, `systemctl is-system-running`, `zfs list -t snapshot`, `zfs version`, the absence of `/var/lib/hass/.storage/lovelace_resources`, and the presence of `/IMPERMANENCE-MARKER-09-05`.

---
*Phase: 09-channel-bump-to-nixos-26-05*
*Completed: 2026-08-17*
