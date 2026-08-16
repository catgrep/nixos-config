---
status: complete
phase: 09-channel-bump-to-nixos-26-05
source: 09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md, 09-04-SUMMARY.md, 09-05-SUMMARY.md, 09-06-SUMMARY.md, 09-07-SUMMARY.md
started: 2026-08-18T01:01:55Z
updated: 2026-08-18T01:22:00Z
---

## Current Test

[testing complete]

## Tests

### 1. ser8 first 26.05 reboot — impermanence rollback and ZFS kmod skew
expected: After ser8's first reboot on 26.05, the marker file /IMPERMANENCE-MARKER-09-05 written outside persisted paths does not survive (erase-your-darlings rollback still fires from the migrated systemd stage-1 unit), zfs-kmod reaches 2.4.3, and zfs-scrub.service stops failing.
result: pass
note: "make reboot-ser8 reported 'did not come back online after 10 attempts', but ser8 booted fine — verified post-boot: 26.05.20260817.0dd31db, marker absent, zfs-kmod 2.4.3-1, zfs-scrub inactive. Script retry window too short; logged as minor gap."
coverage_id: 09-05 D5

### 2. Home Assistant camera card renders exactly once
expected: After a cache-free reload of the Home Assistant dashboard, the custom camera card renders exactly once, the resource list has one entry for it, and there is no duplicate custom-element error in the browser console. (The lovelace-resources workaround was removed from Nix source and from /var/lib/hass/.storage.)
result: pass
coverage_id: 09-05 D4

### 3. Grafana alert email delivers end to end
expected: In Grafana on firebat, the contact point "email-alerts" Test action sends a message that actually arrives in the catgrep@sudomail.com inbox — proving the pinned legacy secret_key still decrypts the stored SMTP/contact-point secrets after the 12.x → 13.x Grafana bump.
result: pass
coverage_id: 09-07 D3

### 4. Third-party binary cache revoked on the developer machine
expected: Running `make update-nix-conf` (needs root) applies the repo's nix daemon config, after which `grep -c cachix /etc/nix/nix.custom.conf` reports 0 — the third-party trusted cache is gone from the installed daemon file, not just from the repo declarations.
result: pass
coverage_id: 09-02 D4

### 5. Grafana secret_key present in SOPS (re-verify user-attested claim)
expected: From a terminal with your age identity, `sops -d secrets/firebat.yaml | grep -c '^grafana_secret_key:'` outputs 1. (09-01 recorded this as user-attested only; the executor session had no identity and never verified it.)
result: pass
coverage_id: 09-01 deferred item

### 6. make check exits 0 for all four hosts
expected: `make check` (flake checks, statix, dry-run builds for ser8, firebat, pi4, pi5) exits 0 on your machine. 09-07 recorded this passing (D6); this confirms it holds for you locally.
result: pass
coverage_id: 09-02 D5

### 7. Pi FOUND-02 evidence level accepted
expected: You accept the recorded per-host evidence (upstream nixpkgs + nixos-hardware builds, config.txt eval, bootloader gating — but no literal dry-activate on pi4/pi5, with pi4 disconnected) as satisfying the roadmap's all-hosts wording for FOUND-02, as documented in PROJECT.md.
result: pass
coverage_id: 09-02 D6

### 8. Pi hosts build from upstream nixpkgs with no fork input
expected: Both Pi hosts build from upstream nixpkgs and nixos-hardware with no fork input anywhere in the lock
result: pass
source: automated
coverage_id: 09-02 D1

### 9. Extlinux and mainline-kernel override gated in make check
expected: Extlinux and the mainline-kernel override are permanently gated in make check (./scripts/validation/test-pi-bootloader.sh)
result: pass
source: automated
coverage_id: 09-02 D2

### 10. pi5 config.txt renders intended dtparam lines
expected: pi5's config.txt renders the three intended dtparam lines under the upstream schema, with no serial console under the [pi5] filter
result: pass
source: automated
coverage_id: 09-02 D3

### 11. ser8 running 26.05 as boot default with rollback generation
expected: ser8 has NixOS 26.05 activated and selected as boot default, with the previous generation still selectable in the bootloader
result: pass
source: automated
coverage_id: 09-05 D1

### 12. ser8 persistent state captured in quiesced ZFS snapshot
expected: rpool/safe/persist@pre-26.05-2026-08-17T085547Z exists with both restore procedures recorded
result: pass
source: automated
coverage_id: 09-05 D2

### 13. ser8 smoketest suite passes area by area on 26.05
expected: make smoketests-ser8 against the switched system: media 8/8, zfs 7/7, vaapi 5/5, frigate 5/5, home-assistant 3/3; nordvpn 3/4 (pre-existing tunnel outage, not worse than baseline)
result: pass
source: automated
coverage_id: 09-05 D3

### 14. Grafana database backed up, integrity-checked, restorable
expected: Grafana DB backed up consistently against a live writer; sqlite3 PRAGMA integrity_check passes on the ser8 copy
result: pass
source: automated
coverage_id: 09-07 D1

### 15. firebat reversible activation with passing gateway smoketests
expected: firebat activated 26.05 via make test-firebat first; make smoketests-firebat passed against that activation
result: pass
source: automated
coverage_id: 09-07 D2

### 16. firebat running 26.05 as boot default with rollback generation
expected: firebat has 26.05 activated and selected as boot default with the previous generation selectable
result: pass
source: automated
coverage_id: 09-07 D4

### 17. PROJECT.md records Pi input strategy and evidence
expected: PROJECT.md records the Pi input strategy with per-host evidence naming the producing commands, pi4's disconnected status, and the deferred items
result: pass
source: automated
coverage_id: 09-07 D5

### 18. make check exits 0 (executor-verified)
expected: make check exits 0 for all four hosts as recorded by 09-07
result: pass
source: automated
coverage_id: 09-07 D6

## Summary

total: 18
passed: 18
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-09-1
  truth: "make reboot-HOST waits long enough for a rebooted host to come back online before declaring failure"
  status: failed
  reason: "User reported: make reboot-ser8 exited 1 with 'Host 192.168.68.65 did not come back online after 10 attempts', but ser8 booted successfully moments later (verified by direct SSH). The retry window in scripts/nixos-rebuild.sh is shorter than ser8's real boot time."
  severity: minor
  test: 1
  root_cause: "scripts/nixos-rebuild.sh reboot path polls a fixed 10 attempts, which is shorter than ser8's real boot time (ZFS pool import plus service startup on 26.05). The host came online shortly after the script gave up — verified by direct SSH within minutes."
  artifacts:
    - path: "scripts/nixos-rebuild.sh"
      issue: "reboot wait loop caps at 10 attempts; declares failure while host is still booting"
  missing:
    - "Longer or configurable wait window (attempt count or per-attempt delay) so a normal ser8 boot completes inside it"

## Notes

- 09-07-SUMMARY.md coverage block has a malformed entry: D3 verification[0].kind is "manual", not one of the allowed kinds. Treated as a human checkpoint per fail-safe; the SUMMARY should be corrected.
- Gap-closure plans 09-08-PLAN.md and 09-09-PLAN.md exist without SUMMARYs (not yet executed); 09-VERIFICATION.md status is gaps_found.
- Known pre-existing, deferred (not UAT items): ser8 NordVPN tunnel down / qBittorrent 502 (needs SOPS credentials), test-forwarding.sh hard-codes retired pi4 resolver (Phase 10 .vofi work), test-tailscale.sh 10/24.
