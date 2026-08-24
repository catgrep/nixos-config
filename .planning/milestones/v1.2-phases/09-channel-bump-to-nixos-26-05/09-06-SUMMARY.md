---
phase: 09-channel-bump-to-nixos-26-05
plan: 06
subsystem: smoketests
tags: [smoketests, gateway, nordvpn, dns-retirement, regression-gate]
status: complete

requires:
  - "09-01: channel bump landed, `make check` host loop can fail honestly"
provides:
  - "run_suite fan-out helper whose exit status reflects every test it ran (consumed by plan 03)"
  - "SKIP_VOFI_DNS environment variable governing every remaining pi4 DNS lookup (flipped by Phase 10)"
  - "non-mutating qBittorrent VPN-confinement check on the routine deploy path"
  - "routine-versus-disruptive split of the NordVPN suite"
affects:
  - "plan 03: must call run_suite rather than copying the bare-loop shape"
  - "plan 07: firebat gateway gate no longer routes through the disconnected pi4"

tech-stack:
  added: []
  patterns:
    - "sourced suite helper (no shebang entry path, no shell options of its own), matching scripts/smoketests/lib/services.sh"
    - "fault injection via a temporary PATH shim over `ssh`, never by stopping a live service"
    - "EXIT trap installed inside the remote shell when a heredoc mutates remote network state"

key-files:
  created:
    - scripts/smoketests/lib/fanout.sh
    - scripts/smoketests/nordvpn/disruptive.sh
    - scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh
  modified:
    - scripts/smoketests/nordvpn/all.sh
    - scripts/smoketests/gateway/all.sh
    - scripts/smoketests/nordvpn/test-anonymity.sh
    - scripts/smoketests/lib/services.sh
    - scripts/smoketests/gateway/test-caddy.sh
    - modules/gateway/Caddyfile
    - deploy.yaml
  deleted:
    - scripts/smoketests/dns/all.sh
    - scripts/smoketests/dns/test-dns.sh
    - scripts/smoketests/dns/test-dhcp.sh

decisions:
  - "SKIP_VOFI_DNS defaults to 1 (skip); 0 restores the pi4 lookup. One variable, both call sites."
  - "The kill-switch test moved to a manually-invoked suite rather than being deleted or made safe enough for routine use."
  - "An egress address that cannot be obtained fails the confinement check rather than skipping it."
  - "test-caddy.sh's remote-Caddyfile fallback was repaired rather than removed, and now warns that its routes reflect what is deployed."

metrics:
  duration: "~35 min"
  completed: 2026-08-17

actuals:
  tokens: 71000
  tasks: 3
  commits: 5
---

# Phase 09 Plan 06: Smoketest Gate Repair Summary

The smoketest layer can now fail honestly: suite entry points accumulate every test's status instead of reporting only the last one's, the VPN kill-switch test no longer runs on the deploy path and cannot leave the interface down, qBittorrent's VPN confinement has a routine non-mutating check, and pi4's dead DNS role is gone from the reverse proxy, the deploy metadata, and both smoketest lookups.

## What Was Built

### Task 1 — Real exit status, and the disruptive test split out (commit `9f956e3`)

`scripts/smoketests/lib/fanout.sh` provides `run_suite`. **Calling contract, recorded verbatim for plan 03 to consume:**

```bash
. ./scripts/lib/all.sh
. ./scripts/smoketests/lib/fanout.sh

SUITE_NAME="nordvpn"          # optional label, defaults to "smoketest"
TESTS=(                       # array of script paths
    ./scripts/smoketests/nordvpn/test-veth-interfaces.sh
)
run_suite "$@"                # forward the host argument
```

`run_suite` runs every entry even after one fails, counts run/passed, prints one summary line through the shared logging helpers, and returns non-zero if any test failed. It deliberately does not stop at the first failure — one deploy attempt should surface every broken subsystem.

Both existing entry points were converted. The kill-switch test moved out of `nordvpn/all.sh` into the new `nordvpn/disruptive.sh`, which no `deploy.yaml` entry and no make target reaches (`grep -c 'disruptive.sh' deploy.yaml Makefile` reports 0 for both).

`test-anonymity.sh` now installs `trap restore_vpn EXIT` **inside the remote shell**, immediately before the teardown. `restore_vpn` is the single restore mechanism — idempotent, guarded by a `vpn_is_down` flag, and holding the 20-second re-establishment wait. The two previous success-path restore lines are gone, so there is exactly one mechanism rather than two that can disagree.

### Task 2 — qBittorrent confinement check (commit `f2aa406`)

`scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh` asserts three read-only things: the process sits in the `wgnord` namespace, the namespace egress address differs from the host's, and the web UI answers on localhost:8080 through the nginx proxy. It mutates nothing (`grep -Ec 'ip link set|systemctl (stop|restart)|ip route (add|del)'` → 0) and hard-codes no address (`grep -Ec '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'` → 0).

An address that cannot be obtained is a **failure, not a skip** — an unreadable namespace is indistinguishable from a broken one.

### Task 3 — pi4's DNS role retired (commit `e05ccc8`)

The `adguard.internal` vhost is deleted from the Caddyfile, `scripts/smoketests/dns/` is deleted entirely, and pi4's `deploy.yaml` entry now carries `smoketests: "test"` with tags `["arm", "raspberrypi"]` — the `dns` tag is gone so a tag-scoped deploy cannot select a disconnected host by a role it no longer performs.

**Adapted Caddy route list after the AdGuard route's removal (13 routes, no pi4 backend):**

```
prometheus.vofi.app=firebat.local:9090   jellyfin.vofi.app=ser8.local:8096
grafana.vofi.app=firebat.local:3000      jellyfin.vofi=ser8.local:8096
prowlarr.vofi=ser8.local:9696            torrent.vofi=ser8.local:8080
sabnzbd.vofi=ser8.local:8085             frigate.vofi=ser8.local:80
sonarr.vofi=ser8.local:8989              radarr.vofi=ser8.local:7878
bazarr.vofi=ser8.local:6767              nzbget.vofi=ser8.local:6789
hass.vofi=ser8.local:8123
```

`caddy adapt --config modules/gateway/Caddyfile --adapter caddyfile | grep -c 'pi4.local'` → **0**. `make fmt-caddy` exits 0 with "Valid configuration".

**`SKIP_VOFI_DNS` semantics Phase 10 needs to flip:**

| Value | Behaviour |
|-------|-----------|
| `1` (default, and any value other than `0`) | pi4 is never contacted. Both call sites print an explicit per-service skip message and go straight to the Host-header path. |
| `0` | Both call sites attempt the pi4 lookup and degrade to the Host header on failure, exactly as before. The DNS-success branch forces the looked-up address via `--resolve`. |

The variable is read by `scripts/smoketests/lib/services.sh` and `scripts/smoketests/gateway/test-caddy.sh` under the same name — one value governs both. Phase 10 sets it to `0` once `.vofi` ownership is re-established.

## Verification Evidence

### Injected-fault exit statuses (PATH shim over `ssh`, no service stopped)

| Suite | Command | Exit | Summary line |
|-------|---------|------|--------------|
| nordvpn | `PATH=$SHIM:$PATH ./scripts/smoketests/nordvpn/all.sh ser8` | **1** | `[FAIL] nordvpn suite: 0/3 tests passed` |
| gateway | `PATH=$SHIM:$PATH ./scripts/smoketests/gateway/all.sh firebat` | **1** | `[FAIL] gateway suite: 0/3 tests passed` |

Both ran all three tests before reporting — the loop did not abort at the first failure.

**The specific regression, proven directly.** A synthetic suite sourcing the real `fanout.sh` with a failing first test and a passing last test:

```
[FAIL] probe suite: 1/2 tests passed
==> first-fails-last-passes exit=1   (the old bare-loop shape would have exited 0)
```

### Confinement check, red under injected fault

Shim returning the same address for both egress lookups:

```
[done] qbittorrent-nox.service (pid 4242) is confined to the 'wgnord' namespace
[FAIL] VPN LEAK: 'wgnord' egress address equals the host egress address
       (203.0.113.42); qBittorrent is talking to the internet over the home connection
[done] qBittorrent web UI responded with HTTP 200 through the nginx proxy
[FAIL] 2/3 qBittorrent confinement tests passed          exit=1
```

Shim making the namespace lookup unobtainable — confirms fail-not-skip:

```
[FAIL] could not obtain the 'wgnord' namespace egress address; the tunnel is down
       or the namespace is broken                        exit=1
```

### Guard verified in both states

| Run | Exit | Evidence |
|-----|------|----------|
| `./scripts/smoketests/media/all.sh ser8` (guard default) | **0** | 8 skip messages, one per service; `192.168.68.56` appears 0 times; `using host 'pi4' as the DNS server` appears 0 times |
| `SKIP_VOFI_DNS=0 ./scripts/smoketests/media/all.sh ser8` | **0** | 8 pi4 lookups attempted, 0 skip messages |

The guard is a switch, not a deletion.

### Lint

`shellcheck -x` and `shfmt -d` are clean across all eight created or edited scripts.

## Deviations from Plan

### [Rule 1 — Bug] `test-caddy.sh` aborted with exit 127 whenever configs differed

**Found during:** Task 3, triggered directly by this plan's Caddyfile edit.
**Issue:** `./tmp/Caddyfile <(ssh ... 'cat /etc/caddy/caddy_config')` attempted to *execute* `./tmp/Caddyfile` instead of writing to it. The line only runs when local and deployed Caddyfiles differ, which this plan's route deletion made true, so the test died with "command not found" under `set -e`.
**Fix:** `ssh ... 'cat /etc/caddy/caddy_config' >./tmp/Caddyfile`, plus a warning that the routes shown reflect what is deployed rather than the working tree.
**Commit:** `e05ccc8`

### [Rule 2 — Correctness] DNS-success branch did not force the resolved address

Planned. `services.sh`'s comment claimed it forced the looked-up address but curled through the system resolver, so a pass there did not attribute to the resolver under test. Both attempts now carry `--resolve` against the address `nslookup` actually returned. Inert while the guard is active; correct when Phase 10 flips it.

### [Rule 2 — Zero-warnings policy] Cleared pre-existing shellcheck warnings

`services.sh` and `test-caddy.sh` carried SC2034 (unused `expected_port` / `expected_backend` parameters) and SC2029 warnings **before** this plan touched them — confirmed by running shellcheck against the `HEAD` versions. Since CLAUDE.md mandates zero warnings and the plan requires `shellcheck -x` to exit 0 for both files, the dead parameters were removed (with their call sites updated) and the three intentional client-side expansions were given `# shellcheck disable=SC2029` directives with justifications.

### [Tooling] `trash` substituted for `rm` in the fault-injection cleanup

The plan's verify block used `rm -rf "$SHIM"`. A repository hook blocks `rm` in favour of `trash` (CLAUDE.md). Shims were created under the session scratchpad and removed with `trash`.

### [Plan defect] Task 2's verify block omits `shellcheck -x`

Tasks 1 and 3 specify `shellcheck -x`; Task 2 specifies plain `shellcheck`. Every script in this tree that sources `./scripts/lib/all.sh` emits SC1091 under plain `shellcheck` and exits 1 — including pre-existing files such as `media/all.sh` and `test-tailscale.sh`. `-x` is the correct invocation and is clean.

## Blocked Verification — ser8's NordVPN tunnel is down (pre-existing)

Two acceptance criteria could not be satisfied, **for reasons this plan did not cause and must not paper over**.

`./scripts/smoketests/nordvpn/all.sh ser8` and the confinement check both exit non-zero against the real host. The cause is a live outage discovered during execution:

```
wg show wgnord transfer          →  0 bytes received, 296 sent
wg show wgnord latest-handshakes →  0   (handshake never completed)
ip netns exec wgnord curl …      →  empty
```

`wgnord-monitor` logged **26 "VPN connection lost, restarting..." events in 10 minutes**, and each restart takes `qbittorrent-nox.service` down with it, so the web UI returns HTTP 502 intermittently. The host itself egresses normally.

The confinement check therefore reports:

```
[done] qbittorrent-nox.service is confined to the 'wgnord' namespace
[FAIL] could not obtain the 'wgnord' namespace egress address; the tunnel is down
       or the namespace is broken
[FAIL] qBittorrent web UI on localhost port 8080 returned HTTP 502
```

**This is the check working correctly.** Weakening it to green would violate the plan's own prohibition — a check that passes when it cannot see is worse than no check. The criterion "exits 0 against ser8's pre-bump generation" is deferred until the tunnel is restored, not waived.

This outage predates the channel bump and is unrelated to it. Repairing it requires mutating live services and probably the SOPS-encrypted NordVPN credentials, which are unavailable in this session.

## Blocked Verification — `test-caddy.sh` cannot run in this session

`./scripts/smoketests/gateway/all.sh firebat` could not be observed exiting 0. `test-caddy.sh` uses bash process substitution (`diff -q <(ssh …)` and `done < <(caddy adapt …)`), both pre-existing, and this session's seatbelt sandbox blocks it:

```
cat <(echo hello)  →  cat: /dev/fd/63: Operation not permitted
```

Ordinary pipes and file redirection work; only `<(...)` is blocked. The script was **not** rewritten to accommodate a local sandbox quirk — process substitution is valid bash and works in the normal dev shell.

The substantive claim was verified another way: the adapted route list from the local Caddyfile contains 13 routes and zero pi4 backends (shown above), and the gateway suite's output contains no contact with `192.168.68.56`.

One caveat for plan 07: **firebat still has the old Caddyfile deployed** (`grep -c 'adguard.internal'` against `/etc/caddy/caddy_config` on firebat → 1). Until firebat is redeployed, `test-caddy.sh` prefers the deployed config and will still iterate the dead route. The gate becomes passable once plan 07 deploys this change.

## Deferred Issues

| Issue | Why deferred |
|-------|--------------|
| ser8's NordVPN tunnel down, qBittorrent restart-looping | Live incident, pre-existing, needs credentials unavailable in this session |
| `gateway/all.sh firebat` exit-0 observation | Sandbox blocks process substitution; re-run in a normal dev shell |
| firebat redeployment to drop the deployed AdGuard route | Plan 07 owns the deploy |
| `test-tailscale.sh` reports 10/24 | Pre-existing, unrelated to this plan's scope |

## Known Stubs

None. Every check added by this plan performs a real assertion and has been observed both green and red, except where the blocked verifications above are explicitly recorded.

## Commits

| Commit | Description |
|--------|-------------|
| `e86a639` | Whitespace-only shfmt reformat of the nordvpn and gateway suites |
| `9f956e3` | Task 1 — `run_suite`, disruptive split, EXIT trap on the kill-switch test |
| `f2aa406` | Task 2 — non-mutating qBittorrent confinement check |
| `75c37ac` | Whitespace-only shfmt reformat of the services helper and caddy test |
| `e05ccc8` | Task 3 — pi4 DNS role retired, `SKIP_VOFI_DNS` guard, two bug fixes |

## Self-Check: PASSED

All three created scripts exist, `scripts/smoketests/dns/` is confirmed removed, and all five task commits are present in git history.
