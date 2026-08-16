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

## From 09-05 (ser8 activation)

- **`media` user/group UID/GID drift on ser8** — activation warns `not applying GID change
  of group 'media' (992 -> 1100)` and `not applying UID change of user 'media' (1002 ->
  1100)`. The declaration `modules/common/users.nix:19,43` has said `1100` since commit
  `db0ed6f` (2025-08-18); the live host still carries the ids its `media` user was created
  with. This drift is a year old and entirely independent of the channel bump — activation
  refuses the renumber rather than performing it, which is the protective behaviour, since
  applying it would orphan every file under `/mnt/media` owned by 1002:992. Fixing it means
  a deliberate re-chown across the media pool and belongs in its own plan with its own
  verification, not in an activation plan whose only file is `home-assistant.nix`.
- **Frigate live camera streams fail with 403 — pre-existing, NOT caused by the channel
  bump.** Surfaced by the Task 4 dashboard observation, which reported every camera's live
  stream failing (`wss://.../api/frigate/frigate/mse/api/ws?src=...` → "Invalid frame
  header", and the go2rtc streams GET → 500). The browser-side symptoms are downstream of a
  single server-side fact, visible in ser8's Home Assistant journal:

  ```
  [hass_web_proxy_lib] Reverse proxy error for /api/frigate/frigate/mse/api/ws?src=driveway_main:
    403, message='Invalid response status', url='http://127.0.0.1:5000/live/mse/api/ws?src=driveway_main'
  ```

  The mechanism is go2rtc's cross-site WebSocket origin check. Reproduced directly on ser8
  against the running production go2rtc, with everything else held constant:

  | Request to `http://127.0.0.1:1984/api/ws?src=garage_main` | Result |
  |---|---|
  | WebSocket upgrade, no `Origin` header | `101 Switching Protocols` |
  | WebSocket upgrade, `Origin: https://hass.shad-bangus.ts.net` | `403 Forbidden` |

  Home Assistant's Frigate integration proxies the browser's request to Frigate's nginx on
  `:5000`, which forwards to go2rtc on `:1984`, passing the browser's `Origin` header
  through verbatim. go2rtc's generated config (`modules/automation/frigate.nix:467-482`)
  sets only `api: { listen: :1984 }` and no `origin` key, so go2rtc rejects the mismatched
  origin. The reverse proxy path is not implicated — the 403 reproduces entirely on ser8
  localhost, with no Caddy, Tailscale, or firebat involvement.

  **Pre-existing, with evidence.** Identical 403s for the same three cameras on the same
  endpoint are recorded in ser8's journal at `2026-08-14T01:08:21-07:00`, three days before
  the first 26.05 activation (`switch-to-configuration test` at `2026-08-17T02:03:16-07:00`).
  The journal is continuous back to 2026-07-23, so the pre-bump 25.11 system (Frigate
  0.16.3, go2rtc 1.9.12) produced exactly the same failure. Nothing in Phase 9 caused it and
  nothing in Phase 9 is required to fix it.

  **Remedy, verified but deliberately not applied here.** Setting go2rtc's `api.origin` to
  `"*"` resolves it. Verified on ser8 by running two throwaway go2rtc instances from the
  same store binary and the same production config, differing only in that key: with
  `origin: "*"` the cross-origin upgrade returned `101`, without it `403`. Both probe
  instances were stopped and the production go2rtc was left untouched (still pid 3143739,
  all services active, `systemctl is-system-running` → `running`).

  Not applied because it is out of this plan's scope on three counts: the defect is not
  bump-caused, the fix lives in `modules/automation/frigate.nix` while 09-05's only file is
  `home-assistant.nix`, and `origin: "*"` disables a CSRF protection — go2rtc's guard against
  a hostile web page driving a LAN user's browser into the streaming API. That last point is
  a security tradeoff the repository owner should make explicitly, not one an activation plan
  should slip in. Port 1984 is not in `networking.firewall.allowedTCPPorts`
  (`modules/automation/frigate.nix:508-512` opens only 80, 8554, 8555), which bounds the
  exposure but does not remove it. Needs its own plan with its own ser8 verification and a
  smoketest covering the live-stream path, which today's Frigate smoketest does not — it
  checks HTTP reachability and MQTT only, which is why this stayed invisible.

- **Frigate moved 0.16.3 → 0.17.2 in the bump, unremarked by the plan.** The pre-bump
  baseline records `frigate 0.16.3` (`baseline/ser8-packages-2511.json`); ser8's running
  26.05 system reports `0.17.2` from `/api/version`. The Home Assistant Frigate custom
  component moved 5.11.0 → 5.15.3 and go2rtc 1.9.12 → 1.9.14 alongside it. A Frigate minor
  version is a substantial application upgrade, not a routine package bump, and the phase
  treated it as the latter. It is not the cause of the 403 above, and the Frigate smoketest
  area is green, but the move belongs in the phase summary as a recorded bump fact and
  deserves its own verification of recordings, detection, and retention behaviour.

- **`zfs-scrub.service` fails until ser8 reboots** — after the 26.05 activation the ZFS
  userland is `zfs-2.4.3-1` while the kernel module is still `zfs-kmod-2.3.7-1` from the
  booted 25.11 generation, so `zfs scrub` is rejected with *"the loaded zfs module does not
  support an option for this operation. A reboot may be required."* This is the ordinary
  consequence of activating a new ZFS without rebooting, not a 26.05 defect: pools stay
  healthy and importable, and the skew closes on the first boot onto the 26.05 kernel.
  Nothing in Phase 9 reboots ser8, so the unit stays failed (`systemctl is-system-running`
  → `degraded`) until that reboot happens.
