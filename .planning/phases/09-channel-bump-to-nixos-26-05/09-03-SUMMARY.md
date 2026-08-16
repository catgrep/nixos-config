---
phase: 09-channel-bump-to-nixos-26-05
plan: 03
subsystem: smoketests
tags: [smoketests, ser8, zfs, vaapi, frigate, home-assistant, mqtt, regression-gate]
status: complete

requires:
  - "09-01: channel bump landed, pre-bump evaluation baseline captured"
  - "09-06: run_suite fan-out helper with an honest exit status, routine/disruptive NordVPN split"
provides:
  - "scripts/smoketests/ser8/all.sh — the single deploy.yaml entry that reaches all six ser8 areas"
  - "pre-bump smoketest baseline at baseline/smoketests-ser8-2511.txt, captured on 25.11.20260518.687f05a"
  - "VAAPI driver string for post-activation comparison: Mesa Gallium driver 25.2.6 (radeonsi, phoenix, LLVM 21.1.7, DRM 3.61, 6.12.90)"
  - "ZFS feature-flag invariant: neither pool is upgraded, so the previous generation can still import them"
affects:
  - "plan 05: compares its post-activation run against baseline/smoketests-ser8-2511.txt"
  - "plan 05: must NOT run 'zpool upgrade' — test-zfs-health.sh now asserts the pools stay importable by the previous generation"

tech-stack:
  added: []
  patterns:
    - "fan-out entry point via run_suite rather than a bare loop (09-06's helper)"
    - "fault injection through a temporary PATH shim over `ssh` that delegates unmatched commands to the real ssh, so only one subsystem is faulted and no live service is stopped"
    - "resolving a tool from a running unit's own store path (systemctl show -p ExecStart) instead of adding it to the host"
    - "asserting hardware capability by executing it under the unprivileged service user, not by observing the device file"

key-files:
  created:
    - scripts/smoketests/ser8/all.sh
    - scripts/smoketests/ser8/test-zfs-health.sh
    - scripts/smoketests/ser8/test-vaapi.sh
    - scripts/smoketests/ser8/test-frigate.sh
    - scripts/smoketests/ser8/test-home-assistant.sh
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2511.txt
    - .planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2511.status
  modified:
    - deploy.yaml

decisions:
  - "The ZFS feature-flag assertion was inverted relative to the plan's wording: the check requires the upgrade prompt to be PRESENT, because its absence means `zpool upgrade` was run and the previous generation can no longer import the pool."
  - "The VAAPI driver string is reported as an uncounted diagnostic, not an assertion — the encode is the gate; the string is the post-activation comparison aid."
  - "The Frigate MQTT client is resolved from the running broker's store path so the check works on any generation without a host change."
  - "HTTP probes for Frigate and Home Assistant originate on ser8 against `localhost`, keeping them assertions about the services rather than about the LAN path, and keeping literal addresses out of the scripts."
  - "The Home Assistant journal assertion is scoped to the current boot: an error from a previous generation is not evidence about the running one."

metrics:
  duration: "~50 min"
  completed: 2026-08-17

actuals:
  tokens: 79000
  tasks: 3
  commits: 3
---

# Phase 09 Plan 03: ser8 Regression Gate Summary

`make smoketests-ser8` now reaches six areas through one `deploy.yaml` entry with an exit status that reflects all of them, and the three subsystems the kernel bump most directly endangers — ZFS, the AMD render node, and the Frigate-to-Home-Assistant MQTT path — are covered by checks that have each been observed green against ser8's pre-bump generation and red under injected fault.

## What Was Built

### Task 1 — Fan-out entry point and ZFS health (commit `f1a940a`)

`scripts/smoketests/ser8/all.sh` defines a `TESTS` array and calls `run_suite`, the helper plan 06 added. `deploy.yaml`'s ser8 entry moved from `./scripts/smoketests/media/all.sh` to `./scripts/smoketests/ser8/all.sh`, which is what makes the NordVPN suite reachable through `make smoketests-ser8` for the first time. The disruptive kill-switch suite is not in the array (`grep -c 'disruptive.sh'` → 0).

`scripts/smoketests/ser8/test-zfs-health.sh` makes seven assertions: `rpool` and `backup` each online, each reporting no known data errors, `rpool/local/root@blank` present, and each pool not feature-upgraded.

### Task 2 — Real VAAPI encode under the service users (commit `e56b7d0`)

`scripts/smoketests/ser8/test-vaapi.sh` runs a synthetic one-second `testsrc` through `-init_hw_device vaapi=va:/dev/dri/renderD128` → `hwupload` → `h264_vaapi` → `-f null`, non-interactively as `jellyfin` and then as `frigate`. Nothing is written to the host and no unit state changes.

Running as the service users rather than the deploy user is the whole point, and the injected-fault run below shows why: the shim left the device present and both units active, and only the encode failed — the exact shape a permission or driver-ABI regression takes.

### Task 3 — Frigate and Home Assistant (commit `a3b28a8`)

`test-frigate.sh` asserts unit state, HTTP on port 80, MQTT-client resolution, the retained `frigate/available` payload, and a live message on `frigate/stats` within 90 seconds. The subscriber is resolved by parsing `systemctl show -p ExecStart --value mosquitto.service` and taking `mosquitto_sub` from the same store directory, so no host package change is needed on any generation.

`test-home-assistant.sh` asserts unit state, HTTP on 8123, and an empty `journalctl -b -u home-assistant --priority=err` for the current boot.

## Verification Evidence

### Pre-bump baseline

Captured **2026-08-17T08:23:25Z**, immediately before the run, against:

```
$ ssh <ser8> nixos-version
25.11.20260518.687f05a (Xantusia)
```

This is a pre-26.05 version, so the recorded output below is a genuine pre-bump baseline rather than a claim to be one. The complete 203-line output is version-controlled at `.planning/phases/09-channel-bump-to-nixos-26-05/baseline/smoketests-ser8-2511.txt`, with its exit status in `smoketests-ser8-2511.status`. That file is what plan 05 compares its post-activation run against.

Result line for every one of the six areas:

| Area | Result line | Status |
|------|-------------|--------|
| media | `[done] All media services smoketests passed` | green |
| NordVPN | `[FAIL] nordvpn suite: 1/4 tests passed` | **red — pre-existing, see below** |
| ZFS | `[done] all 7 ZFS health tests passed` | green |
| hardware acceleration | `[done] all 5 VAAPI tests passed` | green |
| Frigate | `[done] all 5 Frigate tests passed` | green |
| Home Assistant | `[done] all 3 Home Assistant tests passed` | green |
| **fan-out** | `[FAIL] ser8 suite: 5/6 tests passed` | exit 1 |

**The fan-out's exit status is proven against the real suite, not only synthetically.** NordVPN is the second of six entries; the four entries after it all passed, and the suite still exited 1. A bare loop would have reported the last test's status and exited 0, certifying the activation.

### VAAPI encoder and driver strings for post-activation comparison

Recorded from the passing run. If the encode ever fails after activation, these are the values that changed:

```
libva:  VA-API version 1.22.0 (libva 2.22.0)
driver: /run/opengl-driver/lib/dri/radeonsi_drv_video.so
        Mesa Gallium driver 25.2.6 for AMD Radeon 780M Graphics
        (radeonsi, phoenix, LLVM 21.1.7, DRM 3.61, 6.12.90)
encode: VAAPI profile VAProfileH264High (7)
        VAAPI entrypoint VAEntrypointEncSlice (6)
        render target format YUV420 (0x1), RC mode CQP
```

Both `sudo -n -u jellyfin` and `sudo -n -u frigate` completed the encode. Group membership at baseline: `jellyfin` is in `render`; `frigate` is in `video`, `render`, and `media`.

### Frigate MQTT topic and payload received

```
topic:   frigate/available   payload: online          (retained, arrived within 10s)
topic:   frigate/stats       payload: 58345 bytes JSON (live, arrived within 90s)
```

Observed arrival latency for the statistics topic was **13.5s**, comfortably inside the 90s bound. A representative payload prefix:

```json
{"cameras": {"basement": {"camera_fps": 0.0, ...}, "driveway": {"camera_fps": 5.1, ...
```

### Injected-fault red observations

Every red below was produced by a temporary `PATH` shim over `ssh`. **No household service was stopped.** Shims that faulted a single subsystem delegated every unmatched command to the real `ssh`, so the rest of the host answered normally and the red is attributable to the injected fault alone. All shims were created under the session scratchpad and removed with `trash`.

| Check | Injected fault | Exit | Summary line | Assertion named |
|-------|----------------|------|--------------|-----------------|
| ZFS | `ssh` prints a DEGRADED pool with 2 data errors, no snapshot, no upgrade prompt | **1** | `[FAIL] 0/7 ZFS health tests passed` | all seven, individually |
| VAAPI | only the `ffmpeg` invocation exits 1 (`Failed to initialise VAAPI connection: -1`) | **1** | `[FAIL] 3/5 VAAPI tests passed` | `vaapi_encode_jellyfin`, `vaapi_encode_frigate` |
| Frigate | `systemctl is-active` reports inactive | **1** | `[FAIL] 4/5 Frigate tests passed` | `frigate_unit_active` |
| Frigate | only `mosquitto_sub -h …` times out (exit 27) | **1** | `[FAIL] 3/5 Frigate tests passed` | `mqtt_availability`, `mqtt_live_publication` |
| Frigate | `test -x …/mosquitto_sub` fails (client unresolvable) | **1** | `[FAIL] 2/5 Frigate tests passed` | `mqtt_client_resolved` + both dependants |
| Home Assistant | `systemctl is-active` reports inactive | **1** | `[FAIL] 2/3 Home Assistant tests passed` | `hass_unit_active` |
| Home Assistant | journal returns two error-level lines | **1** | `[FAIL] 2/3 Home Assistant tests passed` | `hass_no_startup_errors` |

Three of these deserve calling out because they are the failure shapes a weaker check cannot see:

**VAAPI — device present, units active, encode broken.**

```
[done] render node '/dev/dri/renderD128' is present
[FAIL] VAAPI h264_vaapi encode FAILED as the 'jellyfin' user on /dev/dri/renderD128
[FAIL]   [AVHWDeviceContext @ 0x0] Failed to initialise VAAPI connection: -1 ...
[FAIL] VAAPI h264_vaapi encode FAILED as the 'frigate' user on /dev/dri/renderD128
[done] 'jellyfin' unit is active
[done] 'frigate' unit is active
[FAIL] 3/5 VAAPI tests passed                                            exit=1
```

A presence-plus-unit-state check would have reported 3/3 green here.

**Frigate — up, serving HTTP, silent on the broker.**

```
[done] 'frigate' unit is active
[done] Frigate web interface responded with HTTP 200 on port 80
[done] MQTT subscriber resolved from the running broker: /nix/store/…/mosquitto_sub
[FAIL] Frigate's retained availability message is 'absent', not 'online'
[FAIL] no message on 'frigate/stats' within 90s
[FAIL]   Frigate is not publishing; detections are not reaching Home Assistant
[FAIL] 3/5 Frigate tests passed                                          exit=1
```

**Home Assistant — active, frontend answering, component failed to load.**

```
[done] 'home-assistant' unit is active
[done] Home Assistant frontend responded with HTTP 200 on port 8123
[FAIL] 2 error-level journal entries for 'home-assistant' in the current boot
[FAIL]   Error setting up entry frigate for camera
[FAIL]   Error during setup of component mqtt
[FAIL] 2/3 Home Assistant tests passed                                   exit=1
```

**Fail-not-skip confirmed.** The missing-MQTT-client shim produces `[FAIL] no executable mosquitto_sub beside the running broker` and a non-zero exit, never a pass. No check in this plan has a branch where an unavailable tool, device, or address calls `pass`.

### `.vofi` skip guard, both states

The baseline run exercised the guard in its default (skip) state. Each of the eight media services printed exactly one explicit skip message and exactly one result:

```
[info] Jellyfin: SKIPPED the '.vofi' DNS path (pi4 resolver retired, pending
       .vofi re-establishment); testing via Host header instead
[done] Jellyfin HTTP responded with HTTP 200 (via Host header)
[done] Jellyfin connectivity test passed
```

A skipped lookup is reported as skipped and never silently counted, and the DNS and Host-header paths do not both run — each service contributes one result to the tally. Plan 06 recorded the inactive-guard run (`SKIP_VOFI_DNS=0`, 8 lookups attempted, 0 skip messages, exit 0); this run is the active-guard half.

### Lint

`shellcheck -x` exits 0 and `shfmt -d` produces no diff for all five created scripts. `yq -e '.hosts.ser8.smoketests == "./scripts/smoketests/ser8/all.sh"' deploy.yaml` → `true`. No created script contains a literal dotted-quad address (`grep -Ec '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'` → 0 for each).

## Deviations from Plan

### [Rule 1 — Bug] The ZFS feature-flag assertion was inverted

**Found during:** Task 1, on first contact with the live host.

**Issue:** The plan specifies asserting that "`zpool status` reports no pending feature-flag upgrade prompt." Both ser8 pools report that prompt today:

```
status: Some supported and requested features are not enabled on the pool.
action: Enable all features using 'zpool upgrade'. Once this is done,
        the pool may no longer be accessible by software that does not
        support the features.
```

Implemented literally, the check would be permanently red on the untouched pre-bump host, contradicting the plan's own acceptance criterion that it exit 0 against that generation. Worse, the only way to turn it green is to run `zpool upgrade` — which, as the prompt itself warns, makes the pool unimportable by older ZFS. During a channel bump that is precisely the action that destroys the ability to boot the previous generation. A gate that pressures the operator toward the single most dangerous mid-bump action is not a safety check.

**Fix:** The assertion requires the prompt to be **present** — i.e. the pools have not been feature-upgraded and the previous generation's ZFS can still import them. The inversion is documented in the script with its rationale and a note that the phase which deliberately upgrades the pools should flip it. The substantive intent (feature-flag state is asserted, not ignored) is preserved; only the sign is corrected.

**Files modified:** `scripts/smoketests/ser8/test-zfs-health.sh`
**Commit:** `f1a940a`

**Action required of plan 05:** do not run `zpool upgrade` during or after activation. This check will go red if you do, and that red is correct.

### [Rule 2 — Correctness] Added assertions the plan did not enumerate

Two assertions were added because their absence would have left a real gap:

- **`errors: No known data errors` per pool.** `zpool status -x` reports a pool healthy while `errors:` reports checksum errors, so health alone is not a data-integrity statement.
- **MQTT-client resolution as its own counted assertion.** The plan required resolution failure to fail rather than skip. Making it a discrete test means the report says *which* thing broke — an unresolvable client and a silent Frigate are different diagnoses with different fixes.

### [Interpretation] `sudo -n -u jellyfin` / `sudo -n -u frigate` appear as documentation

Task 2's acceptance criteria require the script to contain the literal strings `sudo -n -u jellyfin` and `sudo -n -u frigate`. The runtime invocation builds them from a `SERVICE_USERS=(jellyfin frigate)` array, so the literals appear in the header comment that documents the exact command executed. Both literals are present and accurate; the loop is what actually runs. Flagged rather than silently satisfied.

### [Tooling] `trash` substituted for `rm` in shim cleanup

As in plan 06: a repository hook blocks `rm` in favour of `trash` (CLAUDE.md). All fault-injection shims were created under the session scratchpad and removed with `trash`.

## Blocked Verification — `make smoketests-ser8` exits 1, not 0

The acceptance criterion "`make smoketests-ser8` exits 0 against ser8's pre-bump generation" is **not met**, for a cause this plan did not create and must not paper over.

The NordVPN suite reports `1/4 tests passed`. Two distinct pre-existing faults:

**1. The NordVPN tunnel is down and thrashing** (the live incident plan 06 recorded and could not repair — it needs SOPS credentials unavailable in this session):

```
[FAIL] qbittorrent-nox.service has no running process on ser8
[FAIL] could not obtain the 'wgnord' namespace egress address; the tunnel is
       down or the namespace is broken
[FAIL] qBittorrent web UI on localhost port 8080 returned HTTP 502
```

**2. `test-forwarding.sh` still queries the retired pi4 resolver** — a fault this baseline surfaced for the first time, because the NordVPN suite had never been reachable through `make smoketests-ser8` before this plan wired it in:

```
Testing DNS resolution in VPN namespace...
  - Local AdGuard DNS (192.168.68.56): FAILED
```

That is a hard-coded address pointing at a host whose DNS role plan 06 retired. It is a real violation of the same prohibition this plan enforces on its own scripts, but it lives in a file outside this plan's `<files>` and belongs with the `.vofi` re-establishment work. Logged to `deferred-items.md`; **not** fixed here, and **not** softened.

**Both reds are the suite working correctly.** Weakening either to reach exit 0 would violate this plan's prohibition against a check that cannot fail, and would defeat the point of building the gate. The criterion is deferred until the tunnel is restored and the pi4 DNS assertion is retired — not waived.

What this means for plan 05: compare **per-area** results against the baseline, not the top-level exit status. The five green areas above are the pre-bump contract; NordVPN's red is the known starting state, and it must not get *worse*.

## Deferred Issues

| Issue | Why deferred |
|-------|--------------|
| ser8's NordVPN tunnel down, qBittorrent restart-looping | Live incident, pre-existing (recorded by 09-06), needs credentials unavailable in this session |
| `nordvpn/test-forwarding.sh` hard-codes `192.168.68.56` (retired pi4 resolver) | Outside this plan's files; belongs with the `.vofi` re-establishment work in Phase 10 |
| `make smoketests-ser8` exit-0 observation | Blocked by both of the above |

## Known Stubs

None. Every check added by this plan performs a real assertion, and every one has been observed both green against the live pre-bump host and red under injected fault. No check has a branch where a missing tool, device, or address results in a pass.

## Threat Flags

None. This plan adds no network endpoint, no auth path, and no schema change. Its scripts execute read-only remote commands plus one discarded synthetic transcode, using tools already on the host or resolved from a running unit's own store path.

## Commits

| Commit | Description |
|--------|-------------|
| `f1a940a` | Task 1 — ser8 fan-out entry point, ZFS health check, deploy.yaml rewire |
| `e56b7d0` | Task 2 — real VAAPI encode under the jellyfin and frigate users |
| `a3b28a8` | Task 3 — Frigate MQTT-publication check and Home Assistant check |

## Self-Check: PASSED

All five created scripts exist and are executable, the baseline artifact and its status file exist under `baseline/`, `deploy.yaml` points at the fan-out, and all three task commits are present in git history.
