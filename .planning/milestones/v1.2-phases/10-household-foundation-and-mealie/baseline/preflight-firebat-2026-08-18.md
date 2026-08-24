# Firebat pre-activation preflight (plan 10-05, 2026-08-18)

Captured before any activation command was run against firebat.
This is the record plan 10-05 Task 1 requires so that the mealie tsnet node's
appearance is provable as a delta and so a bad boot has a named recovery path.

## Reachability

`make status` initially reported every host Offline.
That was a defect in the target itself, not a real outage: it pinged
`<host>.internal`, a name that resolves nowhere on this network.
Fixed in commit `e6547ca` to use `get-host-ip`, the resolver every other host
target already uses.

After the fix:

| Host | Result | Address used |
|---|---|---|
| ser8 | Online | `ser8.shad-bangus.ts.net` |
| firebat | Online | `firebat.shad-bangus.ts.net` |
| pi4 | Offline | `pi4.shad-bangus.ts.net` |
| pi5 | Offline | `pi5.shad-bangus.ts.net` |

pi4 and pi5 do not answer on their tailnet names or on their `deploy.yaml` LAN
addresses (`192.168.68.56`, `192.168.0.110`).
Their tailnet record shows pi4 last seen 64 days ago.
Genuinely unreachable, pre-existing, and outside this plan's scope.

Direct confirmation for the host this plan touches: `ping 192.168.68.63`
answered in 3.6 ms and `ssh bdhill@192.168.68.63` returned hostname `firebat`.
Task 1's precondition is met.

## Generation and recovery path

Current system profile store path:

```
/nix/store/kmfznlnwnq9r24fay4r3mfik2s1sdnj1-nixos-system-firebat-26.05.20260817.0dd31db
```

| Generation | Date | Channel | Role |
|---|---|---|---|
| 73 | 2026-08-17 13:48 | 26.05.20260817 | current profile, boot `(default)` |
| 72 | 2026-08-12 22:37 | 25.11.20260518 | previous entry, the recovery path |
| 71, 70, 69, 68 | 2026-06 to 2026-07 | 25.11.20260518 | older entries still present |

Bootloader entries present in `/boot/loader/entries`:
`nixos-generation-68.conf` through `nixos-generation-73.conf`.

**Recovery from a bad boot:** select `nixos-generation-72.conf` in the
systemd-boot menu.
`make rollback-HOST` prints a TODO and is not a recovery path.

Two facts worth carrying forward:

1. Rolling back to 72 crosses a channel boundary (26.05 back to 25.11), so it is
   a heavier step than the ser8 268 to 269 rollback plan 10-04 recorded.
2. `bootctl list` reports the *selected* entry as `nixos-generation-64.conf`
   `(reported/absent)`, a file that no longer exists.
   firebat has therefore been switched several times since it last booted, and
   the running kernel is older than the boot default.
   This is pre-existing and is not created by this plan, but it means a reboot
   of firebat is itself an untested transition.

## Tailnet node list

Full redacted output: `tailscale-nodes-firebat-pre-activation.txt`.

Service nodes present (created by caddy-tailscale):
`bazarr`, `frigate`, `grafana`, `hass`, `jellyfin`, `nzbget`, `prom`,
`prowlarr`, `radarr`, `sabnzbd`, `sonarr`, `torrent`.

Host nodes: `firebat`, `ser8`, `pi4` (offline 64d).

**No node named `mealie` is present.**
This is the baseline against which Task 2 demonstrates the delta.

Tailscale reports one health warning on firebat:
`Tailscale can't reach the configured DNS servers. Internet connectivity may be
affected.`
Recorded because it is the layer a later DNS failure would be blamed on.

## Caddyfile

`make fmt-caddy` completed with `Valid configuration` and
`git diff --exit-code -- modules/gateway/Caddyfile` exited 0.
Plan 10-01's formatting stuck and the mealie vhost is syntactically valid.

The adapt output shows servers `srv2` through `srv13`, confirming
RESEARCH.md's finding that each tsnet block creates its own server rather than
joining the default one.

## Gateway suite baseline

Full transcript: `smoketests-gateway-pre-activation.txt`.
`./scripts/smoketests/gateway/all.sh firebat` exits **1**.

| Script | Result |
|---|---|
| `test-caddy.sh` | pass, all tests |
| `test-subgen.sh` | pass, all tests |
| `test-tailscale.sh` | **fail, 23/27** |

The four failing subtests, verbatim:

| Subtest | Message |
|---|---|
| `tailscale_nodes` | `missing Tailscale nodes: mealie` |
| `dns_mealie` | `DNS resolution failed for 'mealie.shad-bangus.ts.net'` |
| `https_mealie` | `mealie HTTPS connection failed` |
| `https_sabnzbd` | `sabnzbd HTTPS returned unexpected code: 502` |

Three are this plan's to close.
`https_sabnzbd` is **not**: it is the gateway-visible symptom of the dead
`sabnzbd.service` on ser8 that plan 10-04 diagnosed (uid/gid remap to `38:194`,
`sqlite3.OperationalError: unable to open database file`) and logged to
`deferred-items.md`.
Caddy returns 502 because the backend is down.

This means the gateway suite cannot exit 0 at the end of this plan for a reason
this plan does not own, so the real gate is the per-test comparison the plan's
action text specifies, not the suite's exit status.

## Finding: the TLS certificate subtests are vacuous

All eight `tls_*` subtests report
`openssl not available on firebat, skipping TLS certificate check` and are then
counted as **passes**.
No certificate chain is inspected by the suite on any node, including mealie.

This does not block the plan and is not fixed here (installing openssl on
firebat would change what `make test-firebat` activates, mid-activation).
It is logged to `deferred-items.md`.

It also confirms why this plan's blocking human checkpoint exists: threat T-10-18
cannot be discharged by the automated suite, because the suite's certificate
tests assert nothing at all.
