---
phase: 09-channel-bump-to-nixos-26-05
plan: 07
subsystem: gateway
tags: [nixos-26.05, firebat, grafana, sqlite-backup, alerting, activation, raspberry-pi, project-decisions]

requires:
  - phase: 09-05
    provides: "ser8 switched to 26.05 as boot default, satisfying D-05's ser8-then-firebat ordering"
  - phase: 09-06
    provides: "a gateway smoketest entry point whose exit status reflects its member results, so the firebat gate can fail at all"
provides:
  - "firebat running NixOS 26.05 with the configuration activated and selected as boot default (generation 73)"
  - "A consistent, integrity-checked, restorable Grafana database backup on ser8's backup pool"
  - "Confirmed end-to-end Grafana alert-email delivery under the pinned legacy secret_key"
  - "PROJECT.md Key Decisions carrying the FOUND-02 Raspberry Pi strategy with per-host evidence and the deferred items"
affects: [10-household-foundation, pi-reflash, bootstrap-image]

actuals:
  tokens: 20500
  tasks: 3
  commits: 3

tech-stack:
  patterns:
    - "SQLite online .backup for live-writer databases, checksummed on both ends, with the restore command written down"
    - "Reversible activation gated by a human delivery check before the switch makes it permanent"

key-files:
  created:
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/dry-activate-firebat-2605-task1.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/test-firebat-2605-task1.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-firebat-2605-task1.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/switch-firebat-2605-task3.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-firebat-2605-task3.txt
  modified:
    - .planning/PROJECT.md
    - .planning/STATE.md
    - scripts/smoketests/gateway/test-caddy.sh

key-decisions:
  - "The Grafana secret_key pin from 09-01 is settled by evidence, not inference: a real test notification was sent from the reversibly-activated host and confirmed to arrive at catgrep@sudomail.com before make switch-firebat was run"
  - "Backup mechanism is SQLite's own .backup, never cp or rsync, because grafana.db has a live writer and the dashboard provider allows UI-side edits that exist nowhere in the version-controlled JSON"
  - "The Home Manager warning-baseline backstop did NOT fire: plan 09-04 had already replaced the stale STATE.md entry, so this plan changed nothing there"
  - "Neither x86 host was rebooted in this phase; both are activated and selected as boot default only, so no early-boot or bootloader path has been exercised"

requirements-completed: [FOUND-01, FOUND-02]

coverage:
  - id: D1
    description: "The Grafana database is backed up consistently against a live writer, integrity-checked, and restorable"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "sqlite3 <backup> 'PRAGMA integrity_check;' on the ser8 copy"
        status: pass
    human_judgment: false
  - id: D2
    description: "firebat activated 26.05 reversibly first and its gateway smoketests passed against that activation"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "make test-firebat then make smoketests-firebat"
        status: pass
    human_judgment: false
  - id: D3
    description: "The Grafana alert-email path delivers end to end under the pinned legacy secret_key"
    requirement: FOUND-01
    verification:
      - kind: manual
        ref: "Contact point 'email-alerts' Test action; arrival confirmed at catgrep@sudomail.com"
        status: pass
    human_judgment: true
    rationale: "Only a human can confirm a message actually landed in the recipient inbox. Grafana's own 'test sent' confirmation proves acceptance, not delivery."
  - id: D4
    description: "firebat has 26.05 activated and selected as boot default with the previous generation selectable"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "readlink -f /nix/var/nix/profiles/system; sudo bootctl list"
        status: pass
    human_judgment: false
  - id: D5
    description: "PROJECT.md records the Pi input strategy with per-host evidence naming the producing commands, pi4's disconnected status, and the deferred items"
    requirement: FOUND-02
    verification:
      - kind: integration
        ref: "grep -q nixos-hardware && grep -q FOUND-02 && grep -ci 'booted|tested on hardware|verified on device' -> 0"
        status: pass
    human_judgment: false
  - id: D6
    description: "make check exits 0 for all four hosts"
    requirement: FOUND-01
    verification:
      - kind: integration
        ref: "make check"
        status: pass
    human_judgment: false

duration: ~2h15m wall (includes the blocking human checkpoint)
completed: 2026-08-17
status: complete
---

# Phase 09 Plan 07: firebat Activation and Phase Close Summary

**firebat runs NixOS 26.05 as its boot default with the gateway suite green, and the Grafana encryption-key bet from 09-01 is settled by a real alert email that arrived before the switch was made permanent.**

## Performance

| Metric | Value |
|--------|-------|
| Tasks | 3 of 3 |
| Commits | 3 (one deviation, one Task 1 evidence, one phase close) |
| Wall time | ~2h15m, most of it the blocking human checkpoint |
| Hosts activated | 1 (firebat); zero Pi hosts touched |

## Accomplishments

- Captured a consistent, integrity-checked backup of firebat's live Grafana database and put it on the fleet's only durable dataset.
- Activated 26.05 on firebat reversibly, ran the gateway suite against it, and confirmed a clean Grafana log before asking anyone to approve anything.
- Proved end-to-end alert delivery under the pinned legacy `secret_key`, which is the one failure mode in this phase that no automated check can see.
- Switched firebat, making generation 73 the boot default with the 25.11 generation still selectable.
- Recorded the FOUND-02 Raspberry Pi decision in PROJECT.md with per-host evidence that names the producing commands and claims nothing stronger.
- Got `make check` to exit 0 for all four hosts, which is the first fully green run in this phase.

## Task Commits

| Task | Name | Commit |
|------|------|--------|
| — | Gateway caddy smoketest made runnable and honest (deviation, Rule 3) | `0a35dc1` |
| 1 | Grafana DB backup + reversible firebat 26.05 activation | `e2e740d` |
| 2 | Alert-email delivery proof (blocking human checkpoint) | no commit; approval only |
| 3 | Switch firebat, record the Pi decision, verify the warning baseline | this commit |

## The Grafana database backup

**Source:** `/var/lib/grafana/data/grafana.db` on firebat, owned `grafana:grafana`, mode `0640`, journal mode `delete`, live writer running throughout.

**Backup command actually used** (recovered verbatim from firebat's sudo audit journal, since Task 1's shell transcript was not committed):

```
sudo /nix/store/hfi7wfmjsap0l5jzjgphz4m76w3s9sm4-sqlite-3.50.4-bin/bin/sqlite3 \
  /var/lib/grafana/data/grafana.db \
  ".backup '/var/backups/09-07/grafana.db.pre-26.05-2026-08-17T184223Z'"
```

This is SQLite's own online backup API, not a file copy. `sqlite3` is not on firebat's system PATH, so the store path was invoked directly.

**Destination and integrity:**

| Property | Value |
|----------|-------|
| firebat path | `/var/backups/09-07/grafana.db.pre-26.05-2026-08-17T184223Z` |
| Durable copy | `ser8:/mnt/backups/firebat/grafana/grafana.db.pre-26.05-2026-08-17T184223Z` |
| Size | 9 699 328 bytes, identical on both hosts |
| sha256 | `8243ea3e7f18de312fbf460bcf23ed6bf7d8a51ccb2dde4a0bc821997e120557`, identical on both hosts |
| Ownership | `root:root`, mode `0600`, on both hosts |
| `PRAGMA integrity_check` | `ok`, run against the ser8 copy (the copy that would actually be restored from) |
| Content proof | 13 rows in `dashboard`, 1 row in `alert_configuration` |

ser8's `backup` ZFS pool is the only durable dataset in the fleet. firebat is a single ext4 disk: `hosts/firebat/disko-config.nix` declares no ZFS, and its `impermanence.nix` only pins SSH host key paths despite the filename, so there is no snapshot mechanism and no persist dataset on that host.

**Restore command**, stopping Grafana first:

```
sudo systemctl stop grafana
sudo cp ser8:/mnt/backups/firebat/grafana/grafana.db.pre-26.05-2026-08-17T184223Z \
        /var/lib/grafana/data/grafana.db      # scp from ser8 if restoring remotely
sudo rm -f /var/lib/grafana/data/grafana.db-wal /var/lib/grafana/data/grafana.db-shm
sudo chown grafana:grafana /var/lib/grafana/data/grafana.db
sudo chmod 0640 /var/lib/grafana/data/grafana.db
sudo systemctl start grafana
```

The `-wal`/`-shm` removal is defensive: the database is in `delete` journal mode today, but a Grafana upgrade that switches it to WAL would leave stale sidecar files that a restored main file must not be paired with.

## The activation ladder, in order

1. **Backup** (above), taken before anything was activated.
2. **`make dry-activate-firebat`** exited 0. Preview recorded in `baseline/dry-activate-firebat-2605-task1.txt`:
   - *stop*: `avahi-daemon.service`, `avahi-daemon.socket`, `caddy.service`, `grafana.service`, `kmod-static-nodes.service`, `logrotate-checkconf.service`, `nscd.service`, `prometheus-blackbox-exporter.service`, `prometheus-node-exporter.service`, `prometheus-process-exporter.service`, `prometheus-systemd-exporter.service`, `prometheus.service`, `subgen.service`, `systemd-modules-load.service`, `systemd-networkd-wait-online.service`, `systemd-oomd.service`, `systemd-oomd.socket`, `systemd-sysctl.service`, `systemd-timesyncd.service`, `systemd-tmpfiles-resetup.service`, `systemd-vconsole-setup.service`
   - *restart*: `systemd` itself, plus `nix-daemon.service`, `sshd.service`, `systemd-journald.service`, `systemd-networkd.service`, `systemd-resolved.service`, `systemd-udevd.service`, `tailscaled.service`
   - *reload*: `dbus.service`, `firewall.service`, `reload-systemd-vconsole-setup.service`
   - *start*: the stop list minus `avahi-daemon.service` and `systemd-oomd.service` (their sockets restart instead)
   - `grafana.service` appears in both the stop and start lists, which is the expected shape. Its absence would have been the surprise.
   - No unit was listed as removed.
3. **`make test-firebat`** activated 26.05 without touching the boot menu. `nixos-version` then reported `26.05.20260817.0dd31db (Yarara)` while `/nix/var/nix/profiles/system` still pointed at `...-nixos-system-firebat-25.11.20260518.687f05a`.
4. **`make smoketests-firebat`** exited 0 against that temporary activation: caddy 13/13 proxy routes, tailscale 24/24, gateway suite 3/3.
5. **Grafana log check**: `journalctl -u grafana --boot | grep -ci 'failed to decrypt'` returned `0`, and the same for `invalid key`.
6. **The human checkpoint** (Task 2, below).
7. **`make switch-firebat`**, run only after the checkpoint returned an approval.

`make switch-firebat` prompts by design and `NO_CONFIRM` was never set; the prompt was answered affirmatively on the user's explicit approval.

## Task 2: the alert delivery proof

The user opened the `email-alerts` contact point in Grafana and used its Test action. **The test notification arrived at `catgrep@sudomail.com`.** Dashboards were also confirmed to render Prometheus data, which clears the datasource credentials encrypted with the same key.

One detail worth recording because it nearly produced a false negative: before the button was pressed, firebat's journal showed zero send attempts, and that silence was briefly read as a delivery failure. It was not. Absence of a send attempt is absence of a test, not a failed test. The check was only meaningful once the Test action had actually been invoked.

Server-side corroboration since the 26.05 activation at 11:49 local:

| Check | Result |
|-------|--------|
| `Notify for alerts failed` / `failed to send email` occurrences | 0 |
| `failed to decrypt` / `invalid key` occurrences | 0 |
| Only `level=error` class present | `plugin route is not covered by RBAC and disabled default falling back to 403` (5 occurrences, unrelated to alerting) |

For contrast, the same journal shows repeated pre-bump `email-alerts/email[0]` notify failures through July and early August, all of them `i/o timeout` reaching `smtp.gmail.com`. Those are network reachability, not decryption, and they are not new. Zero such failures have appeared since the bump.

The pinned legacy `secret_key` from 09-01 is therefore confirmed correct against the existing ciphertext. No re-provisioning from SOPS was needed.

## After the switch

**`nixos-version`:** `26.05.20260817.0dd31db (Yarara)`

**Boot default now points at 26.05** (this is the state change the switch produced):

| Path | Before switch | After switch |
|------|---------------|--------------|
| `/nix/var/nix/profiles/system` | `...-nixos-system-firebat-25.11.20260518.687f05a` | `...kmfznlnwnq9r24fay4r3mfik2s1sdnj1-nixos-system-firebat-26.05.20260817.0dd31db` |
| `/run/current-system` | 26.05 (reversible) | 26.05 (permanent) |
| `/run/booted-system` | 25.11 | 25.11, unchanged |

**Bootloader entries** from `sudo bootctl list`, recorded as entry titles rather than as a profile-link count:

```
NixOS (Generation 73 NixOS Yarara 26.05.20260817.0dd31db (Linux 6.18.44), built on 2026-08-17) (default)
NixOS (Generation 72 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-08-12)
NixOS (Generation 71 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-07-26)
NixOS (Generation 70 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-07-26)
NixOS (Generation 69 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-07-25)
NixOS (Generation 68 NixOS Xantusia 25.11.20260518.687f05a (Linux 6.12.90), built on 2026-06-14)
nixos-generation-64.conf (selected) (reported/absent)
nixos-generation-63.conf (reported/absent)
Reboot Into Firmware Interface
```

Generation 72 is the recovery target: a real 25.11 entry with a present `.conf` on the ESP. Note the two `reported/absent` lines. Generation 64 is what firebat is *currently running*, and its boot entry has already been garbage-collected off the ESP, so the running generation is not itself re-selectable. This does not affect recovery (generation 72 is intact and is the same 25.11 release) but it is worth knowing before anyone reasons about "reboot back to what is running".

**`make switch-firebat` transcript** (`baseline/switch-firebat-2605-task3.txt`) recorded `copying 0 paths` and `updating systemd-boot from 258.7 to 260.2`. The zero-copy line is expected: `make test-firebat` had already realised the closure on the host. Activation reported only `setting up /etc`, the two sops key imports, and a user-unit reload, with no service restarts, because those had already happened under the reversible activation.

Same bootloader caveat as ser8 in 09-05: the EFI boot manager binary on firebat's ESP is now 26.05's systemd-boot 260.2 while the running kernel is still 25.11's. That is normal for a switch, and both generations' BLS entries remain valid, but it is a bootloader-level change made without a reboot to confirm it.

**`make smoketests-firebat` after the switch exited 0**: caddy 13/13 proxy routes, tailscale 24/24, gateway suite 3/3.

The post-switch transcript is byte-identical to the pre-switch one. **That equality is the pass condition, not a staleness signal**, and the run was proved fresh rather than assumed so:

- The command was executed live in this session and its exit status observed directly.
- The services it exercised belong to the 26.05 closure: `caddy.service`'s `ExecStart` is `/nix/store/r97g5kcgdngkq7c66h0mlmy4nvr4fnwi-caddy-start`, and `nix-store -q --requisites /run/current-system | grep -c r97g5kc...` returns `1`, so the routes tested were served by the switched configuration.
- Grafana 13.0.6 and Prometheus 3.12.0 are the running versions, all three units `active`.

**`make check` exits 0** for all four hosts, with `✓ All host configurations are valid`. This is the first fully green `make check` of the phase; it was red from 09-01 through 09-02 on `declarative-jellyfin` versus Jellyfin 10.11.11, which 09-04 resolved.

## PROJECT.md: the FOUND-02 decision, as written

Six rows were added to the Key Decisions table, followed by a prose evidence subsection. The rows, verbatim in substance:

1. **Pi input strategy** — both Pis build from upstream nixpkgs 26.05 + `nixos-hardware` pinned at `ff17823245ab9ff7bcae6acf950bd89cba82c38c` (2026-08-16), replacing the `nvmd/nixos-raspberrypi` fork. Rationale: the fork's engineering was upstreamed into `nixos-hardware` with attribution, making this a rename rather than a reimplementation; pinned rather than tracking master because `raspberry-pi/common/` is under active development.
2. **Mainline kernel** — `boot.kernelPackages = pkgs.linuxPackages` forced over `nixos-hardware`'s `mkDefault` vendor kernel, because the vendor `linux-rpi` kernel has no Hydra binary-cache build and neither host needs board-specific peripherals. Gated permanently by `scripts/validation/test-pi-bootloader.sh` in `make check`.
3. **pi4 is disconnected and pending retirement or repurposing**, which is why its DNS smoketests and its Caddy route were deleted in 09-06 rather than repaired.
4. **Evidence is evaluation-level only, recorded separately per host**, because D-13 sets a different bar for each board.
5. **Pi 5 bootstrap image and physical reflash deferred**, with the intended technical path recorded.
6. **`.vofi` DNS ownership is open and must be answered in Phase 10**, with `SKIP_VOFI_DNS` defaulting to `1` holding the smoketests in the meantime.

The evidence subsection states both bars explicitly and names every producing command:

- **pi4**: `nix build --dry-run '.#nixosConfigurations.pi4.config.system.build.toplevel'` (exit 0, 169 derivations, 1027 fetched paths), `./scripts/validation/test-pi-bootloader.sh`, and the SSH timeout at `bdhill@192.168.68.56` that confirms the disconnection.
- **pi5**: D-13's reachability conditional **resolved to the FALLBACK branch**. `make dry-activate-pi5` was never run. All four probes failed on 2026-08-17 (`192.168.0.110` SSH timeout, `pi5.local` and `pi5.shad-bangus.ts.net` both unresolvable), with a same-session ser8 SSH control exiting 0 to make those failures attributable to the host. Fallback evidence is `nix build --dry-run` on the pi5 toplevel (exit 0, 162 derivations, 911 fetched paths), the bootloader validation script, and the rendered `config.txt` eval.

`grep -ci 'booted\|tested on hardware\|verified on device' .planning/PROJECT.md` returns `0`. No Pi claim in that file implies a board was ever powered on.

## STATE.md: the Home Manager backstop did not fire

Plan 09-04 Task 2 owned replacing the stale Phase 08 entry, and it did so. STATE.md carries exactly one entry addressing the Home Manager warning baseline (the `[Phase 09]: SUPERSEDES the Phase 08 accepted Home Manager mismatch baseline...` decision), and it records the truth: the release-mismatch warning is gone now that `home-manager` is on `release-26.05` at both the top level and in the subflake, and any such warning appearing from here on is a finding rather than a permitted condition. No superseded entry survives alongside it.

**This task's backstop therefore changed nothing**, which is the outcome the plan wanted. Recorded here because "the backstop did not fire" is itself the finding about plan 09-04's execution.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Gateway caddy smoketest was unrunnable and judged routing incorrectly** (committed as `0a35dc1` during Task 1)

- **Found during:** Task 1, running `make smoketests-firebat` against the reversibly-activated host.
- **Issue:** three separate defects stacked. The test used process substitution, which `/dev/fd` denial in a sandboxed shell turns into a test failure rather than a visible environment error, hiding every route assertion behind it. The `SKIP_VOFI_DNS` path sent a `Host:` header against the bare IP, which gives Caddy no SNI and so no way to pick the vhost certificate. And it treated any non-200 as a routing failure, so `nzbget` 401, `sabnzbd` 303, and Home Assistant 400 (all the applications' own replies, identical when queried directly) counted as Caddy failures.
- **Fix:** temp files instead of process substitution; `curl --resolve` instead of a `Host` header, which consults no resolver (pi4 is still never contacted) but does send SNI; a route passes when the upstream answers with any non-5xx status, since only 5xx or no response means Caddy failed to route.
- **Files modified:** `scripts/smoketests/gateway/test-caddy.sh` (+50 / -36).
- **Commit:** `0a35dc1`.

### Process notes, not code changes

**Task 1's shell transcript was not committed**, only its three output files. The exact backup command therefore had to be recovered from firebat's sudo audit journal rather than read from a recorded transcript. It was recovered verbatim and is reproduced above, so the acceptance criterion is met, but future plans that require an exact command in the summary should tee the command itself, not only its output.

## Pending items carried out of this phase

None of these block plan 09-07's completion, and all of them need to be visible to phase verification.

| # | Item | Owner | Status |
|---|------|-------|--------|
| 1 | **ser8 first-26.05-boot proofs.** `/IMPERMANENCE-MARKER-09-05` is planted on `rpool/local/root` and confirmed present; it MUST NOT survive ser8's first 26.05 boot, or the stage-1 systemd rollback migrated in 09-01 did not fire and impermanence is silently broken. Separately, ser8's ZFS userland is `2.4.3-1` against `zfs-kmod-2.3.7-1` from the still-booted 25.11 kernel, so `zfs scrub` is rejected; the skew clears only on reboot, and `zfs-scrub.timer` next fires 2026-08-24. | Phase verification / user | **Open — ser8 not rebooted** |
| 2 | **Revoke the third-party cachix trust on the developer machine.** `/etc/nix/nix.custom.conf` still lists `nixos-raspberrypi.cachix.org` as a substituter, trusted substituter, and trusted public key. Repository declarations are clean; only the installed file is stale. The user must run `sudo make update-nix-conf` locally and confirm `grep -c cachix /etc/nix/nix.custom.conf` outputs `0`. Threat T-09-06 stays open until then. | User | **Open — needs root** |
| 3 | **Frigate live-stream 403.** Pre-existing, not bump-caused: go2rtc rejects the cross-origin WebSocket upgrade Home Assistant's proxy forwards, with identical 403s in ser8's journal on 2026-08-14, three days before the first 26.05 activation. The remedy (`go2rtc` `api.origin`) is verified but deliberately not applied because it trades away a CSRF protection. | Deferred, user decision | **Open by choice** |
| 4 | **pi5's `deploy.yaml` entry is stale.** `192.168.0.110` is the only address on `192.168.0.0/24` while every other host is on `192.168.68.0/22`, and `targetUser: nixos` is the installer's default account. Correct it before any plan tries to reach that host. | Phase 10 | **Open** |

**Neither ser8 nor firebat was rebooted in this phase.** Both are activated and selected as boot default. No early-boot or bootloader path has been exercised on either x86 host, and item 1 above is exactly what a reboot would settle.

## Issues Encountered

**`sqlite3` is not on firebat's system PATH.** The store path had to be invoked directly for both the backup and the integrity check. The integrity check reported here was run on ser8's copy instead, where `sqlite3` is available at `/run/current-system/sw/bin/sqlite3`, which is also the stronger check: it validates the copy that would actually be restored from, not just the one that was written.

**Absence of a send attempt read as a failed send.** Covered under Task 2 above. Recording it because the same shape will recur on any human-gated delivery check: a silent log before the human acts is not a negative result.

## Known Stubs

None. This plan created no source files; its only code change was the deviation fix to `scripts/smoketests/gateway/test-caddy.sh`, which replaced skipped assertions with real ones.

## Threat Flags

None. No new network endpoint, auth path, file access pattern, or schema change at a trust boundary was introduced. The Grafana schema migration is upstream's, performed by Grafana itself, and is the reason T-09-36's backup mitigation exists.

## Next Phase Readiness

Phase 09's activation work is complete for both x86 hosts. Phase 10 should start by answering the `.vofi` DNS ownership question recorded in PROJECT.md, since no household service is reachable by name until it has an owner, and by correcting pi5's `deploy.yaml` entry before any plan tries to reach that board. The pending items table above is the full carry-forward list.

## Self-Check: PASSED

All claimed artifacts verified present on disk (`09-07-SUMMARY.md`, both new baseline transcripts, `PROJECT.md`, `STATE.md`), and both prior task commits verified present in git history (`0a35dc1`, `e2e740d`).
