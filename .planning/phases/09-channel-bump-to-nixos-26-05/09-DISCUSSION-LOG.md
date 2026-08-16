# Phase 9: Channel Bump to NixOS 26.05 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-16
**Phase:** 9-Channel Bump to NixOS 26.05
**Areas discussed:** Pi input strategy, Activation scope, Input update scope, Evidence & verification

---

## Pi input strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate to upstream | pi4 on nixos-hardware + upstream nixpkgs, pi5 on nixos-hardware rpi5 + upstream nixpkgs; drop the nvmd fork | ✓ |
| Keep the pin, record it | Retain nixos-raspberrypi at current rev, verify builds, record decision | |
| Decide by spike result | Time-boxed migration spike with pin fallback | |

**User's choice:** Migrate to upstream.

| Option | Description | Selected |
|--------|-------------|----------|
| Reflash from new images | Fresh images per Pi, clean slate | ✓ |
| In-place migration | Rewrite base.nix and switch over SSH | |
| In-place with reflash fallback | Try in-place with a recovery card ready | |

**User's choice:** Reflash from new images (as the eventual method; no flashing this phase per Activation scope).

| Option | Description | Selected |
|--------|-------------|----------|
| Bootstrap-image pattern | Remove input; minimal upstream sd-images with baked-in SSH keys, deploy remotely (per nixos-pi5-template) | ✓ |
| Full custom installers upstream | Rebuild full installer UX on upstream sd-image | |
| Keep input for installers only | Fork retained just for image generation | |

**User's choice:** Bootstrap-image pattern.
**Notes:** User asked whether BennyDeeDev/nixos-pi5-template had been referenced; it was fetched and adopted as the canonical pattern for the Pi migration.

| Option | Description | Selected |
|--------|-------------|----------|
| Mainline for both | pkgs.linuxPackages on pi4 and pi5, Hydra-cached | ✓ |
| Downstream linux-rpi | Foundation kernel, best peripheral coverage, uncached | |
| Let research decide | Researcher checks nixos-hardware defaults on 26.05 | |

**User's choice:** Mainline for both.

---

## Activation scope

| Option | Description | Selected |
|--------|-------------|----------|
| All four hosts | Everything ends the phase on 26.05 | |
| x86 now, Pis build-only | Activate ser8 + firebat; Pis prove builds only | ✓ |
| ser8 only | Minimum the criteria require | |

**User's choice:** x86 now, Pis build-only.
**Notes:** pi4's AdGuard DNS is disconnected and unused (why its smoketests fail); pi4 will probably be retired or repurposed.

| Option | Description | Selected |
|--------|-------------|----------|
| Build-compat only | pi4 builds on upstream, no image/flash work; record retirement-pending status | ✓ |
| Full parity with pi5 | pi4 gets a bootstrap image too | |
| Drop pi4 from the flake | Remove the host entirely | |

**User's choice:** Build-compat only.

| Option | Description | Selected |
|--------|-------------|----------|
| test first, then switch | Per host: test → smoketests → switch; ser8 then firebat | ✓ |
| ser8 fully, then firebat | Complete ser8 end-to-end with soak before firebat | |
| Switch both directly | Skip temporary activation | |

**User's choice:** test first, then switch.

| Option | Description | Selected |
|--------|-------------|----------|
| Image built + backlog note | pi5 config + tested bootstrap image; reflash as backlog item | |
| Config build only | Only prove pi5 config builds; image deferred | ✓ |
| Reflash pi5 this phase anyway | Flash pi5 now while context is loaded | |

**User's choice:** Config build only.
**Notes:** Installer targets (make pi4-installer/pi5-installer) are removed with the input; bootstrap-image work is noted alongside the deferred reflash.

---

## Input update scope

| Option | Description | Selected |
|--------|-------------|----------|
| nixpkgs + Pi-related only | Smallest diff; other inputs keep locked revs | |
| Full nix flake update | Bump everything in one lock update | |
| Full update, staged commits | Channel+Pi inputs first, validate; then flake update, validate | ✓ |

**User's choice:** Full update, staged commits.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, same phase | Bump home-manager/ subflake to release-26.05 alongside | ✓ |
| No, out of scope | Leave the subflake pinned | |

**User's choice:** Yes, same phase.

| Option | Description | Selected |
|--------|-------------|----------|
| Keep it | nixpkgs-unstable stays as-is, refreshed in the update | |
| Audit and minimize | Keep input, but move anything 26.05-stable-satisfied off unstable | ✓ |
| You decide | Defer to research/planning | |

**User's choice:** Audit and minimize.
**Notes:** overlays/ folded into the same audit; system.stateVersion untouched.

---

## Evidence & verification

| Option | Description | Selected |
|--------|-------------|----------|
| Full system build | nix build the full toplevel for both Pis | |
| Dry-activate / eval only | Evaluation-level checks | ✓ |
| Build + boot-test in VM | Full build plus QEMU boot | |

**User's choice:** Dry-activate / eval only.
**Notes:** pi4 disconnected → local eval evidence; pi5 real dry-activate if reachable.

| Option | Description | Selected |
|--------|-------------|----------|
| Smoketests + risk spots | Existing suites plus one-time manual checks | |
| Existing smoketests only | Trust current coverage | |
| Add permanent smoketests | Commit test-*.sh for ZFS, VPN netns, hw accel | ✓ |

**User's choice:** Add permanent smoketests, and disable pi4 DNS tests and .vofi domain tests (both fail due to the disconnected pi4 DNS).

| Option | Description | Selected |
|--------|-------------|----------|
| Delete pi4's, park .vofi's | Delete pi4 DNS tests; unwire .vofi files but keep them | |
| Delete both | Remove both sets entirely | |
| Skip-flag both | Keep everything wired behind skip guards | |

**User's choice:** Delete pi4 DNS tests; skip-flag the .vofi tests (keep wired with skip guards) for Phase 10 re-enablement.

---

## Claude's Discretion

- Exact base.nix migration mechanics (upstream bootloader options, firmware partition handling) within the template pattern.
- nixos-hardware pin-vs-follow choice, as long as the rpi5 module is current.
- Skip-guard mechanism for the .vofi tests.

## Deferred Ideas

- pi5 bootstrap image + physical reflash (with new bootstrap-image Make targets).
- pi4 retirement or repurposing decision.
- `.vofi` DNS ownership after pi4 — open question Phase 10 planning must resolve before `mealie.vofi`.
