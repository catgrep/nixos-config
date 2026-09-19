---
created: 2026-09-19T04:10:00.000Z
title: Upgrade Frigate to 0.18 via multiverse pin
area: automation
severity: minor
files:
  - modules/automation/frigate.nix
  - multiverse.lock
---

## Problem

ser8 runs Frigate 0.17.2 from the flake's nixpkgs 25.11.
Frigate 0.18.0 (released 2026-09-12) adds a generic process watchdog that auto-restarts stalled subprocesses (targets the chronic "Too many unprocessed recording segments" stalls seen daily on driveway/garage), per-role MQTT camera status topics, a camera connection quality indicator on the metrics page, UI-based config management, motion search, and go2rtc 1.9.14 / ffmpeg 8.1.1.
As of nixpkgs history through 2026-09-17, the newest packaged version is 0.17.2 (`mvs query versions frigate`), so there is no rev to pin yet.
The packaging work is tracked in nixpkgs PR #541441, open since ~July 2026 (predating the final 0.18.0 release), so expect a wait; watch the PR rather than polling `mvs query`.

## Solution

Once `mvs query versions frigate` shows 0.18.0: `nix flake update mvs`, `mvs lock add frigate` (frigate is not yet in multiverse.lock), and point `services.frigate.package` at `config.multiverse.locked.frigate` following the mealie/homebox pattern from commit 99ae4ca.
Two caveats need explicit validation before deploying.
First, 0.18 has breaking config changes (zones gain `enabled`/`friendly_name`, snapshots `clean_copy` removed, `sync_recordings`/`timelapse_args`/`ui.date_format`/`ui.time_format` removed, ffmpeg 8 needs a go2rtc transcode config tweak); Frigate's runtime auto-migration cannot rewrite a Nix-managed config, so the settings block in modules/automation/frigate.nix must be migrated by hand against the 0.18 reference config.
Second, the PYTHONPATH tensorflow-filtering override and the ROCm/HSA environment in modules/automation/frigate.nix are coupled to the 0.17.2 package's closure and must be revalidated against the 0.18 derivation.
Validate with `make build-ser8` and `make test-ser8` before switching.
