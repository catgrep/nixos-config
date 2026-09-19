---
created: 2026-09-19T04:35:00.000Z
title: Restore Frigate object detection - model wiped by impermanence rollback
area: automation
severity: critical
files:
  - modules/automation/frigate.nix:98-108
  - hosts/ser8/impermanence.nix
---

## Problem

Frigate's detector config points at `/var/cache/frigate/model_cache/yolov8s.onnx`, a manually exported file (ultralytics) in a directory that is not in ser8's impermanence persist list.
The 2026-08-28 reboot rolled back `/var/cache`, the directory was recreated empty, and the ONNX detector process died at startup; Frigate keeps running without it and nothing alerted.
Verified live on 2026-09-18: `model_cache/` is empty, the detector pid from `/api/stats` does not exist, `frigate_detection_fps` has been 0 for all cameras for the full 30-day Prometheus window, and the last detection event is 2026-08-18.
The dead detect pipeline cascades: camera processes skip ~98% of frames (`process_fps` 0.1-0.4 vs `camera_fps` 5-10), which starves the record maintainer (the thread that moves 10-second cache segments to disk), producing the chronic "Too many unprocessed recording segments" warnings (1,500-4,300/day) and real recording gaps, plus stale "No frames have been received" camera tiles in the live UI.

## Solution

Move the model to `/var/lib/frigate/model_cache/yolov8s.onnx`: this is Frigate's documented `/config/model_cache` location on a bare-metal install, and `/var/lib/frigate` is the persisted ZFS dataset (`rpool/safe/persist/frigate`) that the nightly backup engine snapshots, replicates to `backup/persist-replica/frigate`, and verifies — so the model survives reboots and is backed up.
frigate.nix changes (done 2026-09-18): model.path points at the new location, a tmpfiles rule creates the directory, and an ExecStartPre check fails the unit loudly with the regeneration command when the model is missing, instead of letting the detector die silently.
Regenerate the model with nixpkgs tooling (ultralytics 8.4.48 is packaged): `nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.ultralytics p.onnx ])' -c yolo export model=yolov8s.pt format=onnx imgsz=320`, then install to the model_cache path owned by frigate:frigate.
Deploy with `make test-ser8` and verify: detector pid alive, `frigate_detection_fps` > 0 under motion, `skipped_fps` near 0, record-maintainer warnings stop, live-view tiles update.
The companion alerting todo (2026-09-18-frigate-camera-down-alerting-and-status-panel.md) gains a detector-stall rule so this failure mode can never be silent again.
