# Incident: firebat Caddy will not start, shared Tailscale auth key rejected

**Date:** 2026-08-18
**Found during:** plan 10-05, Task 1, `make test-firebat`
**Status:** UNRESOLVED, active outage, blocked on a human action
**Severity:** high. Every service behind firebat's reverse proxy is unreachable.

## What happened

`make test-firebat` activated the configuration carrying the mealie tsnet vhost.
`caddy.service` failed to start:

```
Error: loading initial config: loading new config: http app module: start:
starting HTTP/3 QUIC listener: tsnet.Up: backend: invalid key: API key does not exist
```

The configuration was rolled straight back by re-activating the boot default
(`sudo /nix/var/nix/profiles/system/bin/switch-to-configuration test`,
generation 73, the configuration **without** the mealie vhost).

**Caddy fails identically on the rolled-back configuration.**
That is the decisive fact.
A clean `systemctl restart caddy` on generation 73 produces the same error, and
the only tsnet node that even begins to start is `frigate`, the first one:

```
tsnet starting with hostname "frigate", varRoot "/var/lib/caddy/.config/tsnet-caddy-frigate"
Authkey is set; but state is NoState. Ignoring authkey. Re-run with TSNET_FORCE_LOGIN=1 to force use of authkey.
Error: ... tsnet.Up: backend: invalid key: API key does not exist
```

## This was latent, not caused by the mealie vhost

firebat had an uptime of 64 days (booted 2026-06-14) and `caddy.service` had been
running continuously across that window.
A long-lived Caddy process holds its tsnet sessions in memory, so nothing
re-authenticated during those 64 days.

The shared Tailscale auth key stopped being valid at some point inside that
window. Nothing surfaced it, because nothing restarted Caddy.

**Any** caddy restart would have detonated this: a reboot, a `switch` for an
unrelated gateway change, an OOM kill, a power cut.
Plan 10-05's activation is what performed the restart; it is not what broke the
key. The mealie vhost is incidental — the failure reproduces without it.

## The auth key plumbing is intact; the key itself is rejected

Checked without printing the value:

| Check | Result |
|---|---|
| `/run/secrets/tailscale_authkey` present | yes |
| mode / owner | `400`, `caddy:caddy` |
| length | 61 bytes |
| prefix class | `tskey` |

So SOPS decryption, the age identity, the secret mount, and the `TS_AUTHKEY`
export in `modules/gateway/caddy.nix` all work.
The Tailscale control plane is rejecting the credential itself.

`API key does not exist` is the response for a key that has been deleted or
revoked, rather than one that is merely expired.

Rotation history of the secret:

| Commit | Date | Subject |
|---|---|---|
| `9311c21` | 2026-07-26 | `secerts: update tailscale_authkey` |
| `8d8cb12` | 2026-01-31 | `secrets: Rotate tailscale_authkey` |
| `8c5c1ff` | 2026-01-31 | Add shared SOPS secrets for Tailscale auto-authentication |

The key in place is 23 days old and already invalid.
This has now happened at least three times, which suggests the keys being minted
are single-use or short-expiry when the deployment needs a reusable, long-lived
one: thirteen tsnet nodes authenticate from this one value.

## Outage scope

`caddy.service` is `failed` on firebat as of this writing.

- Every `*.shad-bangus.ts.net` service endpoint is down: `jellyfin`, `grafana`,
  `prom`, `radarr`, `sonarr`, `bazarr`, `prowlarr`, `sabnzbd`, `nzbget`,
  `frigate`, `hass`, `torrent`. Tailnet status shows them dropping to `offline`
  progressively as the control plane ages them out.
- Every LAN `.vofi` vhost is down. `https://grafana.vofi.app` returns `000`
  (connection failed) from firebat itself.
- The backing services are healthy and untouched: `prometheus` and `grafana`
  units are `active`, `tailscaled` is `active`. Only the proxy in front of them
  is down.
- ser8 is unaffected. Mealie continues to serve on its loopback port and on
  `192.168.68.65:9000`, exactly as plan 10-04 left it.

Note that `blackbox-exporter` reports `inactive`, which is its state from before
this incident and is not part of it.

## What was NOT done, deliberately

- **No new auth key was minted.** That requires the Tailscale admin console.
- **No Caddyfile change to disable the tsnet vhosts.** Commenting out the tsnet
  blocks would restore the LAN `.vofi` routes while leaving every tailnet
  endpoint down, and it would land a temporary mutilation in the repository for
  a fault whose real fix takes a few minutes in the admin console. That tradeoff
  belongs to the operator, not to the executor.
- **`TSNET_FORCE_LOGIN=1` was not tried.** Forcing a login with a credential the
  control plane says does not exist cannot succeed.
- **`make switch-firebat` was NOT run.** The activation gate failed, so the boot
  default was never moved. firebat's boot default remains generation 73.

## Remediation

1. In the Tailscale admin console, under Settings then Keys, generate a new auth
   key. It must be **reusable**, because thirteen tsnet nodes share this one
   value, and **non-ephemeral**, so the nodes are not removed when Caddy stops.
   Choose the longest expiry available and record the expiry date, because this
   is the third time this credential has gone bad.
2. Write it into the shared secret with `make sops-edit-shared`, under the
   `tailscale_authkey` key. Do not paste it into a shell, a commit message, or
   any planning artifact.
3. Re-activate firebat. `make test-firebat` is enough to prove it: `caddy.service`
   should reach `active` and all thirteen nodes, including `mealie`, should
   register.
4. Consider disabling key expiry on the long-lived service nodes in the admin
   console, so that a dead auth key stops being able to take the whole gateway
   down.

## Consequence for the phase

RESEARCH.md assumption A5 — *that adding a tsnet vhost needs no Tailscale
admin-console action because the shared authentication key covers new nodes* —
is **falsified**. An admin-console action is required, and it was required
before this plan started.

Plan 10-05 carried this assumption as its single flagged risk and made it an
explicit acceptance step precisely so it would surface as a named failure rather
than a mystery 502. It did.

Phases 12 and 13 each add three more tsnet nodes on the same assumption. They
must treat a valid, reusable, non-expiring auth key as a **precondition** rather
than an inherited given, and they should verify it by restarting Caddy on
purpose rather than by trusting a process that has been up for weeks.
