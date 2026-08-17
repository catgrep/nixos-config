## From 09-03 (ser8 regression gate)

- **`scripts/smoketests/nordvpn/test-forwarding.sh` hard-codes `192.168.68.56`** — the
  retired pi4 AdGuard resolver. Surfaced for the first time by this plan's baseline run,
  because the NordVPN suite had never been reachable through `make smoketests-ser8`.
  Violates the no-literal-address rule; belongs with the `.vofi` re-establishment work
  (Phase 10), not with this phase's files.
- **ser8's NordVPN tunnel down / qBittorrent restart-looping** — live incident, first
  recorded by 09-06. Repair needs SOPS-encrypted NordVPN credentials.

## From 09-04 (input refresh)

- **`services.sabnzbd.configFile` is deprecated in 26.05** — nixpkgs wants
  `services.sabnzbd.settings` instead. The setter is `hosts/ser8/media/sabnzbd.nix:8`,
  which 09-04 was explicitly told to leave untouched (its brief covered only the
  package-version overlay). Migrating is not mechanical: `sabnzbd.ini` is mutable at
  runtime and SABnzbd rewrites it, so moving to a declarative `settings` block risks
  clobbering live state and needs its own plan with a real ser8 verification.
- **`stdenv.isDarwin is deprecated, use stdenv.hostPlatform.isDarwin`** — emitted from a
  third-party flake input, not from repository sources (no in-tree `.nix` file references
  `stdenv.isDarwin`). Resolves on its own when that input next bumps; nothing to fix here.
