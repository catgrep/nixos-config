---
phase: 09-channel-bump-to-nixos-26-05
verified: 2026-08-17T22:40:00Z
status: gaps_found
score: 3/4 roadmap success criteria fully verified (1 partial), 2 additional documented must-haves unmet
behavior_unverified: 2
overrides_applied: 0
gaps:
  - truth: "Every host (ser8, firebat, pi4, pi5) dry-activates without evaluation errors (ROADMAP Phase 9 SC1)"
    status: partial
    reason: "ser8 and firebat each have a real remote `make dry-activate-<host>` transcript (verified present and non-trivial). pi4 and pi5 do NOT — pi4 is physically disconnected and pi5's `deploy.yaml` address (192.168.0.110, user nixos) does not answer SSH/ICMP from this session or, per 09-02-SUMMARY, from the executor's session either. Both Pi hosts were validated only at `nix build --dry-run ... toplevel` (local evaluation), which is a materially weaker guarantee than a remote activation preview — it cannot catch a build-time-only failure (exactly the class of bug 09-01 hit with the caddy vendor hash, which `--dry-run` could not see). This gap was self-disclosed and reconciled in 09-02-SUMMARY.md against SC2's alternate evidence bar (D-13), not hidden — but SC1's literal wording is still unmet for 2 of 4 hosts."
    artifacts:
      - path: ".planning/phases/09-channel-bump-to-nixos-26-05/09-02-SUMMARY.md"
        issue: "Explicitly states: \"The criterion is not met literally by either Pi, and that gap is named here rather than redefined away.\""
    missing:
      - "A real `make dry-activate-pi4` / `make dry-activate-pi5` transcript, OR an explicit human decision to accept the evaluation-level bar as sufficient for this milestone (recordable as an override below)."
  - truth: "The third-party (nvmd/nixos-raspberrypi) trusted binary cache is fully revoked, not merely undeclared in the repo (09-02-PLAN must_haves truth)"
    status: failed
    reason: "The repository's `etc/nix/nix.custom.conf` is clean (0 cachix references), and `flake.nix`'s `nixConfig` block is clean. The *installed* daemon configuration this machine actually uses, `/etc/nix/nix.custom.conf`, still lists `nixos-raspberrypi.cachix.org` as a substituter, a trusted substituter, and a trusted public key — verified directly in this session (`grep -c cachix /etc/nix/nix.custom.conf` → 3). `make update-nix-conf` cannot succeed without root, which this environment does not have. Threat T-09-06 stays open."
    artifacts:
      - path: "/etc/nix/nix.custom.conf"
        issue: "Still trusts nixos-raspberrypi.cachix.org as of this verification"
    missing:
      - "User must run `sudo make update-nix-conf` locally, then confirm `grep -c cachix /etc/nix/nix.custom.conf` outputs 0."
  - truth: "The smoketest layer introduced/repaired by this phase does not contain a check that always passes (multiple plans' explicit prohibitions: 09-03 \"MUST NOT write a smoketest that always exits 0\", 09-06 \"MUST NOT write a suite entry point whose exit status is that of its last test\")"
    status: failed
    reason: "Independent code review (09-REVIEW.md, dated after all 7 SUMMARYs) found, and this verification directly reconfirmed in the current tree, three still-unfixed instances of exactly this anti-pattern introduced or left unrepaired by this phase's own work: (1) `deploy.yaml`'s pi4/pi5 `smoketests: \"test\"` entries expand to the shell builtin `test <hostname>`, which is true for any non-empty string — `make smoketests-pi4`/`-pi5` (and therefore `make apply-pi4`/`-pi5`) always report success and assert nothing (CR-03, reconfirmed live: `make -n smoketests-pi4` → `test pi4`, `sh -c 'test pi4'` → exit 0). This replaced pi4's real, deleted DNS/DHCP smoketests with a silent no-op, on a host that still runs AdGuard Home. (2) `scripts/smoketests/gateway/test-caddy.sh` prints \"all tests passed\" and exits 0 when zero routes were extracted from the Caddyfile (CR-04, reconfirmed by reading lines 178-198 — the zero-route branch only warns, then execution falls through to the pass path). (3) `scripts/smoketests/ser8/test-home-assistant.sh`'s journal check treats an SSH/journal-read failure identically to \"journal read successfully, zero errors found\" (CR-05, reconfirmed by reading `remote()` at lines 56-62, which swallows every SSH failure into an empty string, and `test_hass_no_startup_errors` at lines 106-115, which reads empty as pass)."
    artifacts:
      - path: "deploy.yaml"
        issue: "pi4/pi5 smoketests set to the literal string \"test\", not a real script or a loud-failure placeholder"
      - path: "scripts/smoketests/gateway/test-caddy.sh"
        issue: "services_tested == 0 branch only warns; falls through to pass \"all tests passed\""
      - path: "scripts/smoketests/ser8/test-home-assistant.sh"
        issue: "remote() returns \"\" on any SSH failure; test_hass_no_startup_errors reads \"\" as \"no errors\" rather than \"could not check\""
    missing:
      - "deploy.yaml: point pi4/pi5 at a real suite, or a two-line script that prints why coverage is deferred and exits non-zero."
      - "test-caddy.sh: fail (not warn) and exit 1 when services_tested == 0."
      - "test-home-assistant.sh: distinguish \"could not read the journal\" from \"read it, found nothing\", per the pattern the sibling scripts in this same phase (test-zfs-health.sh, test-qbittorrent-confinement.sh) already use correctly."
deferred: []
behavior_unverified_items:
  - truth: "ser8's stage-1 systemd impermanence rollback (migrated in 09-01 from boot.initrd.postDeviceCommands) actually fires on first 26.05 boot"
    test: "Reboot ser8, then check whether /IMPERMANENCE-MARKER-09-05 (planted on rpool/local/root) survived the boot."
    expected: "The marker file must NOT survive the reboot. Its presence proves the rollback ran; its survival would mean impermanence is silently broken on the new initrd."
    why_human: "Requires physically rebooting a live production host (ser8) and inspecting post-boot state — this session confirmed via live SSH that ser8 is still running its 25.11 kernel (/run/booted-system unchanged) and the marker is still present, which is the expected pre-reboot state, not evidence either way about the rollback."
  - truth: "ser8's ZFS userland/kmod version skew (zfs-2.4.3-1 userland vs zfs-kmod-2.3.7-1 from the still-booted 25.11 kernel) clears on reboot, and zfs-scrub.service completes"
    test: "Reboot ser8, then run `zfs version` and check that userland and kmod versions match, and that the next `zfs-scrub.service` run (or a manual `zpool scrub`) completes without the \"loaded zfs module does not support an option\" error."
    expected: "zfs version reports matching userland/kmod after reboot; zfs-scrub.service completes successfully."
    why_human: "Requires a live reboot of ser8 (production host) and waiting for/triggering the scrub timer. This session confirmed live via SSH that the skew is present exactly as documented (zfs-2.4.3-1 / zfs-kmod-2.3.7-1, pools healthy) — consistent with 'not yet rebooted', not a failure of this phase's work."
human_verification:
  - test: "Reboot ser8 and confirm /IMPERMANENCE-MARKER-09-05 does not survive the boot"
    expected: "Marker absent after reboot; if present, the 26.05 stage-1 systemd rollback did not fire and impermanence is silently broken"
    why_human: "Live production reboot; cannot be exercised from this session"
  - test: "After ser8 reboots, confirm zfs version reports matching userland/kmod and zfs-scrub.service completes"
    expected: "No userland/kmod skew; scrub completes without the module-support error"
    why_human: "Live production reboot; cannot be exercised from this session"
  - test: "Decide whether the pi4/pi5 evaluation-level evidence (local `nix build --dry-run` + `test-pi-bootloader.sh`, no real dry-activate) is an acceptable substitute for ROADMAP Phase 9 SC1's literal \"every host dry-activates\" wording, or whether it should remain an open gap until the hosts are reachable"
    expected: "An explicit accept/reject decision, recordable as a VERIFICATION.md override if accepted"
    why_human: "Judgment call the plan's own authors (09-02-SUMMARY D6) explicitly assign to the user, not to a command"
---

# Phase 09: Channel Bump to NixOS 26.05 Verification Report

**Phase Goal:** Move the homelab off the EOL nixos-25.11 channel onto nixos-26.05 across all four hosts, with the channel bump judged by an automated regression gate and both x86 hosts activated into service on the new channel.
**Verified:** 2026-08-17T22:40:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Phase 9 Success Criteria)

| # | Truth | Status | Evidence |
|---|---|---|---|
| SC1a | `make check` passes on nixos-26.05 | ✓ VERIFIED | Ran live in this session: `make check` exits 0. All four `nix build --dry-run` toplevels succeed, `nix flake check` and `statix check` pass, `test-nzbget-permissions.sh`/`test-actual-module.sh`/`test-pi-bootloader.sh` all pass. Two pre-existing, documented evaluation warnings remain (`stdenv.isDarwin`, third-party input; `sabnzbd.configFile` deprecation, explicitly deferred in 09-04-SUMMARY) — neither is new or hidden. |
| SC1b | Every host (ser8, firebat, pi4, pi5) dry-activates without evaluation errors | ⚠ PARTIAL / gap | ser8 and firebat each have a genuine `make dry-activate-<host>` transcript (`baseline/dry-activate-ser8-2605-task1.txt`, `baseline/dry-activate-firebat-2605-task1.txt`, both present and substantive). pi4 and pi5 do **not** — evidence is local `nix build --dry-run` only, because pi4 is physically disconnected and pi5's `deploy.yaml` address does not answer (reconfirmed: this session's own SSH/ICMP probes to both hosts also failed). See Gaps. |
| SC2 | Both Pi hosts build under a recorded input strategy, decision + evidence in PROJECT.md Key Decisions | ✓ VERIFIED | `flake.lock` has zero nodes owned by `nvmd` (`jq` check run live). `.planning/PROJECT.md:127-130` records the FOUND-02 decision (nixos-hardware pin, mainline kernel, pi4 disconnected status, evaluation-level evidence caveat) plus a dedicated evidence subsection naming the exact producing commands for each host separately. `grep -ci 'booted\|tested on hardware\|verified on device' PROJECT.md` → 0, so no claim overstates what was actually run. |
| SC3 | `services.actual` on ser8 evaluates with real `user`/`group`/`dataDir` options (26.05 module, not 25.11 hard-coded `DynamicUser`) | ✓ VERIFIED | Ran `scripts/validation/test-actual-module.sh` live in this session: exits 0, confirms `options.services.actual.user`/`group` type `nullOr` and `config.services.actual.settings.dataDir = "/var/lib/actual"` — options that do not exist on 25.11. |
| SC4 | ser8 activates the bumped configuration and the existing media, Frigate, and Home Assistant smoketests still pass | ✓ VERIFIED | Live-checked via SSH: ser8's `/nix/var/nix/profiles/system` resolves to the 26.05 generation (boot default). Ran `make smoketests-ser8` live in this session (not just read from a SUMMARY): media 8/8 pass, ZFS 7/7 pass, VAAPI 5/5 pass, Frigate 5/5 pass (including a live `frigate/stats` MQTT publication), Home Assistant 3/3 pass. Only the pre-existing, independently-tracked NordVPN `test-forwarding.sh` (hard-codes the retired pi4 DNS resolver, deferred to Phase 10's `.vofi` work) is red, exactly as documented pre- and post-bump. |
| Goal clause | Both x86 hosts (ser8, firebat) activated into service on the new channel | ✓ VERIFIED | Live-checked via SSH on both hosts: `nixos-version` reports `26.05.20260817.0dd31db` and `/nix/var/nix/profiles/system` resolves to each host's 26.05 generation. `make smoketests-firebat` re-run live in this session: gateway suite 3/3, all 13 Caddy proxy routes reachable, all 24 Tailscale checks pass. Neither host has been *rebooted* (booted-system is still 25.11 on both) — this is accurately and consistently disclosed throughout the SUMMARYs and does not contradict "activated into service", since `switch` applies the new configuration to the running system immediately (confirmed live: Grafana 13.0.6 and Prometheus 3.12.0, the 26.05 versions, are the ones actually running on firebat). |
| Goal clause | Channel bump judged by an automated regression gate | ⚠ PARTIAL / gap | The gate exists and does real work for the two activated hosts (ser8, firebat): `run_suite` genuinely aggregates failures (proven by fault injection in 09-03/09-06), and several new checks were proven red under injected fault. But an independent code review found, and this verification directly reconfirmed in the current tree, three still-unfixed instances of the exact "check that cannot fail" anti-pattern this phase's own plans explicitly prohibited — see Gaps and Anti-Patterns. |

**Score:** 3 of 4 roadmap Success Criteria fully verified; SC1 is verified for the `make check` clause and for 2 of 4 hosts on the dry-activate clause. 2 additional documented must-haves from the phase's own plans (09-02, 09-03/09-06) remain unmet or newly re-broken as of this verification.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `flake.nix` / `flake.lock` | nixpkgs locked to `nixos-26.05`, no `nvmd` fork node | ✓ VERIFIED | `jq -r '.nodes[.nodes.root.inputs.nixpkgs].original.ref' flake.lock` → `nixos-26.05`; 0 nodes with `.locked.owner == "nvmd"` |
| `home-manager/flake.nix` / `flake.lock` | `home-manager` on `release-26.05` at both levels | ✓ VERIFIED | `jq -r '.nodes[.nodes.root.inputs["home-manager"]].original.ref' flake.lock` → `release-26.05` |
| `scripts/validation/test-actual-module.sh` | Pure-eval SC3 gate | ✓ VERIFIED | Present, executable, ran live, exits 0, wired into `make check` (Makefile:144) |
| `scripts/validation/test-pi-bootloader.sh` | Permanent extlinux/mainline-kernel gate for both Pis | ✓ VERIFIED | Present, wired into `make check` (Makefile:145), part of the passing live `make check` run |
| `scripts/validation/diff-enabled-services.sh` | Array-aware service regression diff | ✓ VERIFIED | Present; both x86 baselines exist under `baseline/` |
| `scripts/smoketests/ser8/*.sh` (zfs-health, vaapi, frigate, home-assistant, all.sh) | ser8 regression suite | ✓ VERIFIED, but see CR-05 | All present, executable, ran live and passed against the current activated ser8 |
| `scripts/smoketests/gateway/test-caddy.sh` | Firebat route-reachability gate | ⚠ VERIFIED functionally, latent stub risk | Passed live (13/13 routes) but contains the CR-04 zero-route silent-pass branch |
| `deploy.yaml` (pi4/pi5 `smoketests` entries) | Real or loudly-absent smoketest coverage | ✗ STUB | `smoketests: "test"` on both — a silently-passing shell-builtin no-op, not a real check and not a loud failure |
| `.planning/PROJECT.md` | FOUND-02 decision + per-host evidence | ✓ VERIFIED | Confirmed present with the exact producing commands named, per host |
| `.planning/STATE.md` | Home Manager warning baseline corrected | ✓ VERIFIED | Phase 08's stale entry replaced with an accurate Phase 09 entry (line 94) |
| `etc/nix/nix.custom.conf` (repo) | No cachix trust | ✓ VERIFIED | 0 cachix references |
| `/etc/nix/nix.custom.conf` (installed, this machine) | No cachix trust after `sudo make update-nix-conf` | ✗ NOT APPLIED | Still lists `nixos-raspberrypi.cachix.org` 3 times; `sudo` unavailable in this environment, confirmed live |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Makefile:144` | `scripts/validation/test-actual-module.sh` | `check` target invocation | ✓ WIRED | Confirmed by the passing live `make check` run |
| `Makefile:145` | `scripts/validation/test-pi-bootloader.sh` | `check` target invocation | ✓ WIRED | Confirmed by the passing live `make check` run |
| `modules/gateway/grafana.nix` | `secrets/firebat.yaml` | `sops.secrets.grafana_secret_key` path interpolation | ✓ WIRED | `nix eval` confirms the secret path resolves; 09-07's live alert-delivery test is end-to-end proof the pinned key decrypts real ciphertext |
| `deploy.yaml` (pi4/pi5) | a real smoketest suite | `Makefile:283` `get-host-smoketests` | ✗ NOT_WIRED | Wired to the literal string `test`, which is not a script and asserts nothing (CR-03) |
| `scripts/smoketests/ser8/all.sh` | `scripts/smoketests/lib/fanout.sh` | `run_suite` | ✓ WIRED | Confirmed by the live `make smoketests-ser8` run reporting `5/6 tests passed` (per-area, not last-test-only) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| `make check` passes | `make check` (run live in this session) | exit 0, "✓ All host configurations are valid" | ✓ PASS |
| SC3 module evidence | `./scripts/validation/test-actual-module.sh` (run live) | exit 0, all three assertions ok | ✓ PASS |
| ser8 smoketest gate | `make smoketests-ser8` (run live) | media 8/8, zfs 7/7, vaapi 5/5, frigate 5/5, home-assistant 3/3, nordvpn 3/4 (pre-existing), suite 5/6 | ✓ PASS (matches documented state) |
| firebat gateway gate | `make smoketests-firebat` (run live) | caddy 13/13, tailscale 24/24, suite 3/3 | ✓ PASS |
| ser8/firebat activation state | live SSH: `nixos-version`, `readlink -f /nix/var/nix/profiles/system`, `readlink -f /run/booted-system` | both hosts: version + profile = 26.05, booted-system = 25.11 (unchanged) | ✓ PASS (matches documented "activated, not rebooted" claim) |
| Impermanence marker still present pre-reboot | live SSH: `test -e /IMPERMANENCE-MARKER-09-05` | present | ✓ PASS (expected state — this is not the reboot proof itself) |
| ZFS userland/kmod skew | live SSH: `zfs version` on ser8 | `zfs-2.4.3-1` userland vs `zfs-kmod-2.3.7-1` | ✓ PASS (matches documented skew, pools healthy) |
| CR-03 (pi4/pi5 fake smoketest gate) | `make -n smoketests-pi4` then `sh -c 'test pi4'` | `test pi4`; exit 0 | ✗ CONFIRMED — gate is a no-op |
| CR-04 (test-caddy.sh zero-route pass) | read `scripts/smoketests/gateway/test-caddy.sh:178-186` | zero-route branch only `warn`s, falls through to `pass "all tests passed"` | ✗ CONFIRMED — defect still present |
| CR-05 (test-home-assistant.sh false pass on unreachable journal) | read `scripts/smoketests/ser8/test-home-assistant.sh:56-62,106-115` | `remote()` swallows every SSH failure to `""`; empty is read as "no errors" | ✗ CONFIRMED — defect still present |
| Third-party cachix trust (installed daemon config) | `grep -c cachix /etc/nix/nix.custom.conf` | `3` | ✗ CONFIRMED — not yet revoked on this machine |
| `nvmd` fork removed from lock | `jq` query on `flake.lock` | 0 nodes owned by `nvmd` | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| FOUND-01 | 01, 02, 03, 04, 05, 06, 07 | Flake runs on nixos-26.05; all four hosts build and dry-activate cleanly | ⚠ PARTIALLY SATISFIED | Build (`nix build --dry-run`) succeeds for all four hosts; `make check` is green; literal dry-activate is proven for ser8/firebat only, not pi4/pi5 (see Gaps). REQUIREMENTS.md marks this `[x]` and "Complete" — this verification finds that status optimistic on the literal wording, though the underlying engineering work (channel bump, activation of both x86 hosts, regression gate) is real. |
| FOUND-02 | 02, 07 | Decision recorded on replacing the nixos-raspberrypi pin with upstream Pi support, with a tested build for each Pi host | ✓ SATISFIED | Decision recorded in PROJECT.md with honest, separately-stated per-host evidence levels; fork fully removed from the lock; both Pi toplevels build. "Tested build" is explicitly evaluation-level per D-13's own definition, which this verification confirms was applied consistently and not overstated. |

No orphaned requirements found — both FOUND-01 and FOUND-02 are claimed by plans in this phase and appear in REQUIREMENTS.md's traceability table mapped to Phase 9.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `deploy.yaml` | 30, 37 | `smoketests: "test"` — shell builtin, always exits 0 | 🛑 Blocker | `make smoketests-pi4`/`-pi5` and `make apply-pi4`/`-pi5` silently certify nothing; regression on a host (pi4) that still runs a live service (AdGuard Home) |
| `scripts/smoketests/gateway/test-caddy.sh` | 178-198 | Zero-route condition only warns, falls through to unconditional pass | 🛑 Blocker (latent) | A Caddyfile/jq-path regression that empties `caddy_routes` would make firebat's routing gate unconditionally green |
| `scripts/smoketests/ser8/test-home-assistant.sh` | 56-62, 106-115 | `remote()` collapses every SSH failure to `""`; empty journal output is read as "no errors" | 🛑 Blocker (latent) | An unreachable ser8, or a deploy user without journal read access, scores this check as a pass rather than a failure |
| `modules/gateway/caddy.nix` | 70-71 | `caddy run --environ` prints the decrypted Tailscale auth key to the systemd journal on every start | ⚠ Warning | Pre-existing (not introduced by this phase), but present in a file this phase modified for the vendor-hash fix; not remediated by this phase |
| `modules/gateway/Caddyfile` / `caddy.nix` | 8, 83 | Unauthenticated Caddy admin API bound to all interfaces, firewall-opened | ⚠ Warning | Pre-existing, same as above |
| `scripts/smoketests/nordvpn/test-anonymity.sh` | 106-117 | Kill-switch probe's failure paths (sudo refusal, missing netns, transient DNS failure) are indistinguishable from "traffic genuinely blocked" | ⚠ Warning | Not in the routine deploy path (moved to `disruptive.sh`, manually invoked only, by this phase's own design) — lower priority than CR-03/04/05 |

No `TBD`/`FIXME`/`XXX` debt markers found in files this phase modified.

## Gaps Summary

The channel-bump engineering itself is solid and independently re-verified live in this session: `make check` is genuinely green, `services.actual`'s 26.05 module genuinely evaluates with real options, both x86 hosts are genuinely running the 26.05 configuration with their smoketests genuinely passing right now, the Pi hosts genuinely build from upstream nixpkgs with the fork fully gone from the lock, and PROJECT.md's FOUND-02 record is honest about what was and wasn't tested. The SUMMARYs' claims held up under independent re-execution rather than being taken on faith.

Three things keep this phase from a clean pass:

1. **ROADMAP Phase 9 SC1's literal "every host dry-activates" is unmet for pi4 and pi5.** This was disclosed transparently by the executor at the time (09-02-SUMMARY explicitly refuses to redefine the criterion away) and has a documented rationale (physical disconnection, stale `deploy.yaml` address), but it remains a fact that 2 of 4 hosts never received the stronger evidence class the roadmap asks for. This is a strong override candidate — the disclosure is thorough and the rationale is sound — but it is not yet formally accepted.

2. **One of 09-02's own must-have truths is unmet and cannot be closed from this environment**: the third-party cachix trust is still live on the developer machine's installed Nix daemon config, confirmed directly in this session. This needs `sudo make update-nix-conf` run by the user.

3. **The phase's own "automated regression gate" goal has three live, unfixed holes**, independently found by code review and independently reconfirmed here by reading the current code: a fake-pass smoketest gate for both Pi hosts (introduced by this phase, replacing real DNS/DHCP checks that existed before), a fake-pass path in the firebat gateway gate, and a fake-pass path in the ser8 Home Assistant gate. None of these caused a false certification *in the specific runs this phase used to justify activating ser8 and firebat* (independently re-verified live, and all three hosts involved were reachable with non-empty results throughout) — but they are real defects in exactly the honesty property this phase set out to establish, and they were still present in the tree at verification time, several hours after all 7 SUMMARYs were written.

Two further items are not gaps against any stated must-have, but are open and worth carrying forward explicitly rather than assuming resolved: ser8 has not yet been rebooted, so the impermanence-rollback proof and the ZFS userland/kmod-skew proof that 09-01 and 09-05 both flagged as necessary are still outstanding (routed to Human Verification below, since they require a live production reboot this session cannot perform).

---

*Verified: 2026-08-17T22:40:00Z*
*Verifier: Claude (gsd-verifier)*
