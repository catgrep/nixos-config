---
phase: 09-channel-bump-to-nixos-26-05
reviewed: 2026-08-17T21:10:17Z
depth: standard
files_reviewed: 44
files_reviewed_list:
  - .gitignore
  - CLAUDE.md
  - Makefile
  - deploy.yaml
  - etc/nix/nix.custom.conf
  - flake.lock
  - flake.nix
  - home-manager/default.nix
  - home-manager/flake.lock
  - home-manager/flake.nix
  - hosts/pi4/default.nix
  - hosts/pi5/configtxt.nix
  - hosts/pi5/default.nix
  - hosts/ser8/configuration.nix
  - hosts/ser8/impermanence.nix
  - modules/automation/frigate.nix
  - modules/automation/home-assistant.nix
  - modules/common/networking.nix
  - modules/common/packages.nix
  - modules/dns/adguard-home.nix
  - modules/gateway/Caddyfile
  - modules/gateway/caddy.nix
  - modules/gateway/grafana.nix
  - modules/media/radarr.nix
  - modules/media/sabnzbd.nix
  - modules/media/sonarr.nix
  - modules/raspberrypi/base.nix
  - modules/servers/tailscale.nix
  - scripts/nixos-rebuild.sh
  - scripts/smoketests/gateway/all.sh
  - scripts/smoketests/gateway/test-caddy.sh
  - scripts/smoketests/lib/fanout.sh
  - scripts/smoketests/lib/services.sh
  - scripts/smoketests/nordvpn/all.sh
  - scripts/smoketests/nordvpn/disruptive.sh
  - scripts/smoketests/nordvpn/test-anonymity.sh
  - scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh
  - scripts/smoketests/ser8/all.sh
  - scripts/smoketests/ser8/test-frigate.sh
  - scripts/smoketests/ser8/test-home-assistant.sh
  - scripts/smoketests/ser8/test-vaapi.sh
  - scripts/smoketests/ser8/test-zfs-health.sh
  - scripts/validation/diff-enabled-services.sh
  - scripts/validation/test-actual-module.sh
  - scripts/validation/test-pi-bootloader.sh
  - secrets/firebat.yaml
  - users/bdhill.nix
findings:
  critical: 6
  warning: 19
  info: 6
  total: 31
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-08-17T21:10:17Z
**Depth:** standard
**Files Reviewed:** 44 (of 47 listed; `flake.lock`, `home-manager/flake.lock`, `secrets/firebat.yaml` reviewed for structure only)
**Status:** issues_found

## Summary

The Nix side of this bump holds up under evaluation. All four hosts evaluate offline against
26.05, `statix` is clean, `shellcheck -x` and `shfmt -d` are clean on every changed script,
and the migrations that were most likely to be wrong are provably right:

- `services.resolved.settings.Resolve` renders the same key set the old `extraConfig` block
  produced (verified by evaluating `config.services.resolved.settings.Resolve` on ser8 and firebat).
- The stage-1 `rollback.service` really is emitted into the systemd initrd alongside
  `zfs-import-rpool.service` and `sysroot.mount`, with the correct `After`/`Before` ordering.
- Both Pi hosts resolve to `generic-extlinux-compatible` + mainline `linux` 6.18.44 with the
  intended `system.nixos.tags`.
- The servarr `UMask` force is justified: 26.05's `radarr.nix:82` and `sonarr.nix:104` do set
  `UMask = "0022"`, and the mkForce restores `0002` on both.
- `programs.git.settings` is a real home-manager 26.05 option and renders the expected `user.*` keys.

The problems are concentrated in two places.

**First, the security posture of the gateway.** Two defects predate this phase but sit in files
it modified, and both are exploitable today: Caddy is started with `--environ`, which prints the
just-exported SOPS Tailscale auth key into the journal on every start (CR-01), and Caddy's
unauthenticated admin API is bound to all interfaces and firewall-opened on the LAN (CR-02).
A third, CR-05's cousin, is new: the Grafana `secret_key` was deliberately pinned to the
publicly-known upstream constant that 26.05 removed precisely because it was known (WR-01).

**Second, the "smoketest honesty repair" is itself dishonest in four places.** The phase built
a genuinely good `run_suite` contract and wrote several careful checks whose block comments
explicitly reject skip-on-can't-see behaviour. Four gates violate that stated standard:
`make smoketests-pi4/-pi5` execute the shell builtin `test` and always exit 0 (CR-03),
`test-caddy.sh` prints "all tests passed" after testing zero routes (CR-04),
`test-home-assistant.sh`'s journal assertion passes when SSH fails (CR-05), and
`test-anonymity.sh`'s kill-switch check prints "OK - traffic blocked" when the probe could not
run at all (CR-06). `test-caddy.sh` additionally covers only 13 of the Caddyfile's 25 routes
while reporting completeness (WR-03).

Findings are ordered Critical → Warning → Info. Items already recorded in
`deferred-items.md` are noted as such and not re-litigated; only WR-17 overlaps.

## Critical Issues

### CR-01: Caddy prints the SOPS Tailscale auth key into the journal on every start

**File:** `modules/gateway/caddy.nix:70-71`
**Issue:** The generated start script exports the decrypted tailnet auth key and then runs
Caddy with `--environ`:

```
export TS_AUTHKEY="$(cat ${config.sops.secrets.tailscale_authkey.path})"
exec ${caddyBin} run --environ --config ${caddyConfig} --adapter caddyfile
```

`caddy run --help` documents `--environ` as "the environment as seen by the Caddy process will
be printed before starting" (verified against the caddy in the dev shell). The plaintext
`TS_AUTHKEY=` line therefore lands in the systemd journal on every Caddy start and restart —
readable by anyone in `systemd-journal`/`adm`, shipped anywhere the journal is shipped, and
persisted across reboots. This violates CLAUDE.md's explicit rule: "Do not expose secret values
in logs, test output, documentation, or diffs."

A Tailscale auth key grants the ability to register new nodes onto the tailnet.

**Fix:**
```nix
exec ${caddyBin} run --config ${caddyConfig} --adapter caddyfile
```
Then rotate `tailscale_authkey` in `secrets/firebat.yaml` (and `secrets/shared.yaml` if the key
is shared), since the current value is already in firebat's journal history.

### CR-02: Caddy's unauthenticated admin API is bound to all interfaces and firewall-opened

**File:** `modules/gateway/Caddyfile:8`, `modules/gateway/caddy.nix:83`
**Issue:** The global options block sets `admin :2019` — an empty host, i.e. all interfaces —
and `caddy.nix` opens 2019 in the firewall. Caddy's admin endpoint has no authentication; a
`POST /load` replaces the entire running configuration. Any host on the LAN (including anything
that lands on the Wi-Fi) can rewrite every reverse-proxy route on firebat, including the
Tailscale-bound vhosts for Jellyfin, Home Assistant, Frigate, Grafana, and Prometheus, and can
point them at an attacker-controlled upstream.

The only consumer is Prometheus, which scrapes `localhost:2019`
(`modules/gateway/prometheus.nix:65`) — from the same host. Nothing needs the exposure.

**Fix:**
```
# modules/gateway/Caddyfile
admin localhost:2019
```
```nix
# modules/gateway/caddy.nix
networking.firewall.allowedTCPPorts = [
  80
  443
];
```

### CR-03: `make smoketests-pi4` and `-pi5` run the shell builtin `test` and always exit 0

**File:** `deploy.yaml:30`, `deploy.yaml:37`, consumed by `Makefile:283`
**Issue:** `Makefile:283` is `@$(call get-host-smoketests,$*) $*`, and
`get-host-smoketests` (`Makefile:37`) reads `.hosts."pi4".smoketests` from `deploy.yaml`, which
this phase set to the literal string `test`. The recipe therefore expands to `test pi4` — the
shell's one-argument `test`, true for any non-empty string. Verified:

```
$ make -n smoketests-pi4
test pi4
$ sh -c 'test pi4'; echo $?
0
```

`make smoketests-pi4` prints nothing and reports success. `make apply-pi4` (`Makefile:286`)
chains `test → switch → reboot → smoketests`, so a full deploy of a Pi now ends with a gate that
verified nothing while appearing green.

This is a regression, not a carry-over: pi4 previously pointed at
`./scripts/smoketests/dns/all.sh`, which this phase deleted along with `test-dns.sh` and
`test-dhcp.sh` — while pi4 still runs AdGuard Home (`flake.nix:219` imports `./modules/dns`;
`hosts/pi4/configuration.nix:69` sets `services.adguardhome.enable = true`). Real DNS/DHCP
coverage on a host that still serves DNS was replaced with a silently-passing no-op.

CLAUDE.md already sets the standard for this situation for a different target: "The
`rollback-HOST` target is currently a placeholder and must not be presented as functional."

**Fix:** either restore a real suite, or make the absence loud:
```yaml
  pi4:
    smoketests: "./scripts/smoketests/pi4/all.sh"   # restore DNS/DHCP coverage
```
or, if coverage is genuinely deferred, a two-line script that prints why and exits non-zero —
never a command that returns 0.

### CR-04: `test-caddy.sh` reports "all tests passed" after testing zero routes

**File:** `scripts/smoketests/gateway/test-caddy.sh:179-198`
**Issue:**

```bash
if [ $services_tested -eq 0 ]; then
	warn "no services were tested"
elif [ $services_passed -eq $services_tested ]; then
	...
```

The zero-route branch only warns. Execution falls through to the caddy-is-running check and then
to `pass "all tests passed"` with exit status 0. Any condition that empties `caddy_routes` —
a Caddyfile whose sites no longer land in `srv0` (see WR-03), a jq path change, an adapted
config with a different server layout — turns this into an unconditionally green deploy gate for
firebat, the host whose whole role is routing.

Every other suite added in this phase gets this right (`test-zfs-health.sh:184-186`,
`test-vaapi.sh:197-199`, `test-frigate.sh:225-227`, `test-home-assistant.sh:138-140`,
`test-qbittorrent-confinement.sh:167-169` all `exit 1` on `tests_run -eq 0`). This file was
rewritten in the same phase and did not receive the same treatment.

**Fix:**
```bash
if [ $services_tested -eq 0 ]; then
	fail "no services were tested: no routes were extracted from ${CADDYFILE_PATH}"
	exit 1
elif [ $services_passed -eq $services_tested ]; then
```

### CR-05: `test-home-assistant.sh`'s journal assertion passes when it cannot read the journal

**File:** `scripts/smoketests/ser8/test-home-assistant.sh:106-115` (with `remote()` at 56-62)
**Issue:** `remote()` is defined as `ssh "$user@$ipaddr" "$remote_command" 2>/dev/null || echo ""`.
It returns an empty string for *every* failure mode: SSH unreachable, host down, `journalctl`
not on PATH, and — the realistic one — the deploy user not being in `systemd-journal`/`adm` and
therefore seeing no unit journal at all. Test 3 then does:

```bash
errors=$(remote journalctl -b -u "$HASS_UNIT" --priority=err --no-pager -q -o cat)

if [ -z "$errors" ]; then
	pass "no error-level journal entries for '...' in the current boot"
	return 0
fi
```

Empty is interpreted as "healthy". A completely unreachable ser8 scores this test as a pass.

This is the exact failure mode the sibling scripts written in this same phase call out as
unacceptable: "An address it cannot obtain is treated as a FAILURE, never a skip: ... a check
that passes when it cannot see is worse than no check at all"
(`test-qbittorrent-confinement.sh:19-22`). `test-zfs-health.sh:76-79` and `:99-102` implement
that standard correctly by failing on empty. This file does not.

**Fix:** separate "could not run" from "ran and found nothing" by asserting a positive signal:
```bash
test_hass_no_startup_errors() {
	local probe
	probe=$(remote sh -c 'journalctl -b -u home-assistant --priority=err --no-pager -q -o cat; echo "__RC=$?"')

	if [[ "$probe" != *"__RC=0"* ]]; then
		fail "could not read the journal for '$HASS_UNIT' on $host"
		return 1
	fi

	local errors=${probe%__RC=0}
	...
}
```

### CR-06: `test-anonymity.sh`'s kill-switch check passes whenever the probe cannot run

**File:** `scripts/smoketests/nordvpn/test-anonymity.sh:106-117`
**Issue:** The remote heredoc runs without `set -e` and uses `sudo` without `-n`. `ssh` is
invoked without `-t`, so there is no TTY; if the sudoers policy for the deploy user ever
changes, `sudo` exits non-zero rather than prompting. Both of these then fail silently:

```bash
vpn_is_down=1
sudo ip netns exec wgnord ip link set wgnord down   # line 108 — may not have run
sleep 2

if sudo ip netns exec wgnord timeout 5 curl ... http://httpbin.org/ip >/dev/null 2>&1; then
	echo "FAILED - traffic leaked when VPN down"
	exit 1
else
	echo "OK - traffic blocked when VPN down"     # line 116
fi
```

The `else` branch is reached by *any* non-zero exit: sudo refused, `wgnord` netns missing,
`timeout` absent, or a transient DNS failure. The script prints "OK - traffic blocked" and
counts a pass — for a kill switch it never actually tested, on an interface it may never have
brought down. This is the load-bearing assertion of the file that `disruptive.sh` exists to run.

Secondary defect on the same block: `trap restore_vpn EXIT` (line 104) does not cover `HUP`,
`INT`, or `TERM`. A dropped SSH session between lines 108 and 120 sends `SIGHUP` to the remote
shell, which terminates without running the `EXIT` trap — leaving `wgnord` down until someone
notices.

**Fix:**
```bash
trap restore_vpn EXIT HUP INT TERM

if ! sudo -n ip netns exec wgnord ip link set wgnord down; then
    echo "FAILED - could not bring wgnord down; kill switch untested"
    exit 1
fi
sleep 2

probe_rc=0
sudo -n ip netns exec wgnord timeout 5 curl -s --connect-timeout 3 --max-time 5 \
    http://httpbin.org/ip >/dev/null 2>&1 || probe_rc=$?
case "$probe_rc" in
  0)      echo "FAILED - traffic leaked when VPN down"; exit 1 ;;
  6|7|28) echo "OK - traffic blocked when VPN down" ;;   # curl: DNS/connect/timeout
  *)      echo "FAILED - probe could not run (rc=$probe_rc); kill switch untested"; exit 1 ;;
esac
```
Adding `set -euo pipefail` as the first line inside the heredoc would also prevent the whole
class of silent-continuation bugs in this file.

## Warnings

### WR-01: Grafana `secret_key` pinned to the publicly known upstream constant

**File:** `modules/gateway/grafana.nix:56-62,78`, `secrets/firebat.yaml:1`
**Issue:** The comment states the sops value "pins the LEGACY upstream constant so existing
grafana.db ciphertext stays decryptable"; the ciphertext length in `secrets/firebat.yaml:1`
(`data:HnN8xC7SnSUehasUy1Yh6vv8MM8=`, 20 bytes) matches the 20-character upstream default.
26.05 removed that default precisely because a shipped constant is not a key.

`secret_key` is what Grafana uses to encrypt datasource credentials and alerting secrets inside
`grafana.db`. With a known value, anyone holding a copy of that database can decrypt them — and
copies exist: `/persist` on firebat, and whatever the `backup` ZFS pool retains. Wrapping the
constant in SOPS makes it *look* protected while changing nothing about its strength, which is
worse than storing it in plaintext, because a reader of `grafana.nix` sees `$__file{...}` and
stops there.

`deferred-items.md` does not track this, so there is currently no plan to rotate it.

**Fix:** rotate now while the deployment is small:
1. Record the current datasource credentials.
2. Generate a real key (`openssl rand -base64 32`) into `secrets/firebat.yaml` via
   `make sops-edit-firebat`.
3. Re-encrypt or re-enter secrets (`grafana cli admin data-keys re-encrypt`, or re-add the
   datasources) after activation.
4. Replace the comment with one describing the key as a real secret.

### WR-02: Both live x86 hosts still point primary DNS at the "retired" pi4

**File:** `modules/common/networking.nix:20-31`, `modules/common/networking.nix:161-186`
**Issue:** `networking.internal.adguard.enabled` defaults to `true` and `.address` defaults to
the literal `192.168.68.56` — pi4. Neither ser8 nor firebat overrides it. Evaluated:

```
$ nix eval '.#nixosConfigurations.ser8.config.services.resolved.settings.Resolve'
{"DNS":["192.168.68.56","192.168.68.1"],"Domains":["~."],...}
# identical on firebat
```

This phase's own smoketests declare that host gone: "pi4 runs the AdGuard resolver that answers
the `.vofi` names, and it is physically disconnected pending retirement or repurposing"
(`scripts/smoketests/lib/services.sh:8-10`), and the phase removed pi4's proxy route
(`modules/gateway/Caddyfile`), its `dns` tag, and its smoketest suite. But the resolver
configuration that makes *both live hosts* send every lookup to that dead address first was left
untouched, and both hosts were activated onto 26.05 in this phase with it. `Domains = ["~."]`
routes all names there. Every DNS query on ser8 and firebat now waits out a timeout before
falling back.

Note the sharper edge: `mode = "strict"` yields `FallbackDNS = []`
(`modules/common/networking.nix:172-175`), which with a disconnected pi4 is total DNS failure on
the host. Nothing prevents that mode from being selected.

**Fix:** in the same change that retired pi4's role, flip the default or set it per-host:
```nix
# modules/common/networking.nix
adguard.enabled = mkOption {
  type = types.bool;
  default = false;   # pi4 resolver retired; re-enable with .vofi re-establishment
  ...
};
```

### WR-03: `test-caddy.sh` inspects only `srv0`; 12 of 25 routes are never tested, yet the summary claims completeness

**File:** `scripts/smoketests/gateway/test-caddy.sh:141-145`
**Issue:** The jq expression hardcodes `.apps.http.servers.srv0.routes[]`. Adapting the current
Caddyfile locally shows Caddy splits it across thirteen servers, because every
`bind tailscale/...` site gets its own listener:

```
srv0:  listen=[":443"]                    routes=13
srv1:  listen=["tailscale/bazarr:443"]    routes=1
srv2:  listen=["tailscale/frigate:443"]   routes=1
...
srv12: listen=["tailscale/torrent:443"]   routes=1
```

So every Tailscale-exposed vhost — jellyfin, sabnzbd, nzbget, radarr, sonarr, bazarr, prowlarr,
torrent, grafana, prom, frigate, hass — is silently skipped. The script then prints
`pass "all 13 caddy proxy services passed"`, which reads as full coverage of the Caddyfile.
The Tailscale routes are the ones reachable from outside the LAN and the ones whose
`caddy-tailscale` plugin was rebuilt against a new vendor hash in this very phase
(`modules/gateway/caddy.nix:15-20`) — precisely the surface most at risk from the bump.

**Fix:**
```bash
caddy adapt --config "${CADDYFILE_PATH}" --adapter caddyfile | jq -r '
      .apps.http.servers | to_entries[] | .value.routes[] as $route |
      ($route.match[].host[] | tostring) + "=" +
      ($route.handle[].routes[].handle[].upstreams[].dial | tostring)
    ' >"${adapted_routes}"
```
The Tailscale vhosts will need a different reachability strategy than
`--resolve "$domain:443:$ipaddr"` (which points at firebat's LAN address, not its tsnet node);
if they genuinely cannot be probed from the deploy host, say so in the summary rather than
omitting them from the count.

### WR-04: `route_reached` accepts 404, which is Caddy's "no matching route" response

**File:** `scripts/smoketests/gateway/test-caddy.sh:25-35`; same defect in
`scripts/smoketests/lib/services.sh:29`, `:36`, `:55`, `:63`
**Issue:**

```bash
route_reached() {
	[[ "$1" =~ ^[1-4][0-9]{2}$ ]]
}
```

The block comment above it asserts "Only a 5xx, which is what Caddy returns when it cannot
reach a backend, or 000 for no response at all, is a routing failure." That is incomplete:
Caddy answers a request whose Host matches no site block with a bare 404. So the one response
that proves the route is *missing* is scored as proof the route works. `services.sh` has the
same hole with its explicit `^(200|301|302|404)$` whitelist.

Today the domains are extracted from the same Caddyfile being tested, so they match — which
means the check is self-fulfilling and would not notice a vhost silently dropped from the
adapted config (exactly what happened to `adguard.internal` in this phase).

**Fix:** distinguish Caddy's own 404 from an upstream's. Caddy's unmatched-route response has
an empty body and no `Server`-identifying upstream headers; the cheapest discriminator is to
require a non-empty body or a known upstream header:
```bash
route_reached() {
	local code="$1" body_bytes="$2"
	[[ "$code" =~ ^[1-4][0-9]{2}$ ]] && { [ "$code" != "404" ] || [ "$body_bytes" -gt 0 ]; }
}
```
capturing `%{size_download}` alongside `%{http_code}` in the curl `-w` format.

### WR-05: `test_pool_not_upgraded` is a guaranteed future false failure on the deploy path

**File:** `scripts/smoketests/ser8/test-zfs-health.sh:130-162`
**Issue:** The test asserts that `zpool status` *still* prints "features are not enabled" — i.e.
that the pools have never been upgraded. The moment the pools are legitimately upgraded, or a
pool is recreated with current ZFS, this fails permanently and blocks every
`make smoketests-ser8`, and therefore `make apply-ser8`, for a healthy system.

The comment acknowledges it ("Flip this assertion in the phase that deliberately upgrades the
pools") without providing any mechanism to make that happen — a booby trap in the deploy gate
with no expiry, in a repo that already has an open ZFS mirror migration
(`.planning/SER8-ZFS-MIRROR-MIGRATION.md`) queued.

**Fix:** make the transient intent explicit and opt-out-able:
```bash
# Set ZFS_ALLOW_POOL_UPGRADE=1 once the pools are deliberately upgraded.
ZFS_ALLOW_POOL_UPGRADE="${ZFS_ALLOW_POOL_UPGRADE:-0}"

test_pool_not_upgraded() {
	if [ "$ZFS_ALLOW_POOL_UPGRADE" = "1" ]; then
		pass "pool upgrade explicitly permitted; skipping the rollback-compatibility assertion"
		return 0
	fi
	...
}
```

### WR-06: `test-vaapi.sh` exercises the wrong ffmpeg and overclaims what it proves

**File:** `scripts/smoketests/ser8/test-vaapi.sh:6-23`, `:97-131`
**Issue:** The encode invokes the bare `ffmpeg` first on the non-interactive SSH PATH. Jellyfin
transcodes with `jellyfin-ffmpeg` and Frigate ships its own build; neither is what this test
runs. A pass proves the render node is openable by the `jellyfin` and `frigate` accounts —
worth having — but not that either service can transcode, which is what the header claims
("Proves VAAPI transcoding by running a real hardware encode"). A `jellyfin-ffmpeg` built
against a different mesa/libva than the system ffmpeg would break invisibly.

`test-frigate.sh:121-154` already demonstrates the right technique: resolve the binary from the
running unit's `ExecStart` rather than from PATH.

**Fix:** resolve each service's actual encoder the same way, e.g.
`systemctl show -p ExecStart --value jellyfin.service` → derive the store path → run that
package's ffmpeg; and narrow the header claim to what the check covers.

### WR-07: `test-frigate.sh` builds the HTTP probe URL out of `MQTT_HOST`

**File:** `scripts/smoketests/ser8/test-frigate.sh:43`, `:107-108`
**Issue:**
```bash
MQTT_HOST="localhost"
...
response=$(remote curl ... "http://${MQTT_HOST}:${FRIGATE_HTTP_PORT}/")
```
The HTTP test is keyed off the MQTT broker's hostname. It works only because both are
`localhost`; the moment the broker moves, the Frigate web-interface probe silently retargets to
the broker host. `test-home-assistant.sh:35` gets this right with a dedicated `HASS_HTTP_HOST`.

**Fix:** add `FRIGATE_HTTP_HOST="localhost"` and use it at line 108.

### WR-08: `run_test`, `remote`, and the summary block are copy-pasted into five scripts, with divergent semantics

**File:** `scripts/smoketests/ser8/test-zfs-health.sh:43-66`,
`scripts/smoketests/ser8/test-vaapi.sh:60-72`,
`scripts/smoketests/ser8/test-frigate.sh:61-82`,
`scripts/smoketests/ser8/test-home-assistant.sh:41-62`,
`scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh:50-71`
**Issue:** Five near-identical copies of `run_test`, four of `remote`, and five of the
tests_run/tests_passed summary. The copies have already drifted in a way that matters: three
`remote()` implementations end in `|| echo ""` while
`test-qbittorrent-confinement.sh:65-71` deliberately does not — an important semantic
difference recorded nowhere, and the direct cause of CR-05.

The project standard is "don't create utilities until you've written the same code three times";
this is five. The phase already established `scripts/smoketests/lib/fanout.sh` as the home for
shared suite logic, so the destination exists.

**Fix:** add `scripts/smoketests/lib/harness.sh` exporting `run_test`, `summarize`, and two
explicitly named remote helpers — `remote_or_empty` and `remote_strict` (propagating status) —
and have all five scripts source it. Make the "empty means failure" contract a property of the
helper rather than of each call site.

### WR-09: Deploy gates depend on third-party internet services, one of them over plaintext HTTP

**File:** `scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh:45`, `:110`, `:116`;
`scripts/smoketests/nordvpn/test-anonymity.sh:22`, `:28`, `:112`, `:124`, `:140`, `:159`
**Issue:** Two separate problems.

1. `test-qbittorrent-confinement.sh` is on the routine `make smoketests-ser8` path
   (`scripts/smoketests/ser8/all.sh:32` → `nordvpn/all.sh:23`) and calls `https://ipinfo.io/ip`
   twice per run. An ipinfo outage or rate limit fails the deploy gate for reasons unrelated to
   the deployment.
2. `test-anonymity.sh` derives its *anonymity verdict* from `http://httpbin.org/ip` — plaintext
   HTTP, six times. An on-path party can forge the response, which is the adversary a VPN leak
   test exists to detect. httpbin.org has also been intermittently unavailable for years.

Neither script validates that the payload is an address before comparing. `curl -s` without
`--fail` returns an HTML error body with exit 0, and
`${host_egress//[[:space:]]/}` then compares two whitespace-stripped HTML blobs — which are
equal, so the check reports "VPN LEAK".

**Fix:** use HTTPS in both, and validate before asserting:
```bash
is_ip() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || [[ "$1" == *:* ]]; }

if ! is_ip "$netns_egress"; then
	fail "could not obtain a valid '$NETNS' egress address (got '${netns_egress:0:40}')"
	return 1
fi
```

### WR-10: Two of `test-anonymity.sh`'s three DNS assertions assert nothing

**File:** `scripts/smoketests/nordvpn/test-anonymity.sh:65-83`
**Issue:**
- Line 76: the "External DNS leak test" fetches `https://1.1.1.1/cdn-cgi/trace` and compares
  the `ip=` field to `vpn_ip`. That field is the *HTTP client* address, the same fact `vpn_ip`
  already holds. It always matches and always prints OK. Nothing about DNS is measured.
- Line 67: the "DNS resolution uses configured servers" check greps for the hardcoded
  `192.168.68.56` — pi4, which this phase retired. It now permanently prints
  "WARNING - not using expected DNS server", and by design (line 71) never fails.

The literal address also duplicates `deploy.yaml`, against the repo's stated rule that
`deploy.yaml` is the source of address truth. (`deferred-items.md` records the same violation in
`test-forwarding.sh` but not here.)

**Fix:** either implement a real DNS leak test (resolve a unique subdomain of a
resolver-logging service from inside the namespace and confirm which resolver queried it), or
delete both checks. A check that cannot fail is noise that trains readers to skim output.

### WR-11: CLAUDE.md still describes the pre-bump repository

**File:** `CLAUDE.md:8`, `:18`, `:42`, `:72`, `:123`
**Issue:** Three separate staleness clusters in the file this phase edited (it changed lines
20, 29, 38-41 and left these):

- Line 8: "This repository is a NixOS homelab flake built around NixOS 25.11." That is the
  single fact this phase changed. `config.system.nixos.release` on every host is now `26.05`.
- Lines 72 and 123 still direct contributors to `nixfmt-rfc-style`, while the phase moved
  `modules/common/packages.nix:51`, `flake.nix:269`, `home-manager/default.nix:15`, and
  `Makefile:156` to `nixfmt`.
- Lines 18 and 42 still describe pi4 as the "AdGuard Home DNS and DHCP server" that "runs
  AdGuard Home plus its Prometheus exporter" — contradicting `deploy.yaml:29` (the `dns` tag was
  removed), `deploy.yaml:30` (the suite was removed), and `modules/gateway/Caddyfile` (the route
  was removed). A reader cannot tell from the repo whether pi4 serves DNS. The code says yes
  (`hosts/pi4/configuration.nix:69`), the metadata says no.

**Fix:** update lines 8, 72, 123; and reconcile 18/42 with whatever the pi4 decision actually is
— including the resolver defaults in WR-02.

### WR-12: `unstable` specialArg is dead plumbing retained for a speculative future phase

**File:** `flake.nix:171-176`
**Issue:**
```nix
# Retained with no in-tree consumers: Phase 10 needs this plumbing.
unstable = import nixpkgs-unstable {
  inherit system;
  config.allowUnfree = true;
};
```
The last two consumers were removed in this phase (`modules/servers/tailscale.nix` moved to
`pkgs.tailscale`; `modules/media/sabnzbd.nix` dropped its overlay). Grepping `modules/`,
`hosts/`, and `users/` confirms no module references `unstable`. The comment documents the
retention as speculative, which the project's own standards forbid: "No speculative features —
don't add features, flags, or configuration unless users actively need them" and "Replace,
don't deprecate ... Proactively flag dead code — it adds maintenance burden and misleads both
developers and LLMs."

It also costs a full extra `import nixpkgs-unstable` per host evaluation, with
`allowUnfree = true` applied unconditionally.

**Fix:** delete the `unstable` specialArg. Re-add it in the phase that has a consumer, in the
same commit as that consumer.

### WR-13: `scripts/validation/diff-enabled-services.sh` has no callers

**File:** `scripts/validation/diff-enabled-services.sh` (whole file)
**Issue:** Added this phase; not referenced by `make check` (`Makefile:140-152`, which invokes
`test-nzbget-permissions.sh`, `test-actual-module.sh`, and `test-pi-bootloader.sh` but not this),
not referenced by `deploy.yaml`, and not referenced by any script — the only hit for
`diff-enabled-services` in the repo is its own usage string. Its header describes it as
"a contract consumed by later Phase 9 plans"; Phase 9 closed at commit `265008a`.

It is a well-written regression detector (the array-vs-`keys` note is a real trap it avoids)
that will never run. Baselines exist in the phase directory but nothing compares against them.

**Fix:** wire it into `make check` against a committed baseline per host —
```make
	@./scripts/validation/diff-enabled-services.sh ser8 .planning/baselines/ser8-enabled-services.json
```
— or delete it and the baselines together.

### WR-14: `test-actual-module.sh` gates every `make check` on a module this repository never uses

**File:** `scripts/validation/test-actual-module.sh` (whole file), wired at `Makefile:144`
**Issue:** `services.actual` appears nowhere in `modules/` or `hosts/`, and
`config.services.actual.enable` evaluates to `false` on ser8. The script asserts the `type.name`
of two options and the *default* value of `services.actual.settings.dataDir` — facts about
upstream nixpkgs, not about this repository. It is nevertheless on the critical path of
`make check`, costing a full ser8 evaluation on every validation run, and its two `nullOr`
assertions will break whenever upstream retypes those options for reasons that have nothing to
do with this repo.

The thing it is trying to prove is "the flake resolves 26.05", which is directly observable.

**Fix:** replace with the direct assertion, which is cheaper, cannot drift, and says what it
means:
```bash
check_eval "channel" \
	".#nixosConfigurations.${host}.config.system.nixos.release" \
	'"26.05"'
```

### WR-15: Three scripts source their library before enabling strict mode

**File:** `scripts/nixos-rebuild.sh:4-7`, `scripts/smoketests/nordvpn/test-anonymity.sh:4-6`,
`scripts/smoketests/gateway/test-caddy.sh:4-6`
**Issue:**
```bash
. ./scripts/lib/all.sh      # line 4

set -euo pipefail           # line 7
```
Everything the five sourced library files do — including `scripts/lib/cleanup.sh`'s
`trap cleanup EXIT` and all of `yq.sh`/`ssh.sh`/`prompt.sh` — runs without `-e`, `-u`, or
`pipefail`. A failure during sourcing is silently ignored. `scripts/nixos-rebuild.sh` is the
entry point for every `make build/test/switch/reboot` target.

Every script *added* in this phase gets the order right (`ser8/all.sh:22-27`,
`test-zfs-health.sh:4,17`, `test-vaapi.sh:4,25`, `test-frigate.sh:4,25`,
`test-home-assistant.sh:4,18`), so the codebase is inconsistent with itself. Shellcheck does not
flag ordering.

**Fix:** move `set -euo pipefail` above the source line in all three.

### WR-16: `test-caddy.sh` silently discards the shared cleanup trap

**File:** `scripts/smoketests/gateway/test-caddy.sh:126-129`
**Issue:** `scripts/lib/cleanup.sh`, sourced via `all.sh` at line 4, installs
`trap cleanup EXIT`. Line 129 then installs `trap "rm -f '...'" EXIT`, which *replaces* it —
bash keeps one handler per signal. This test alone loses the shared
"script '<name>' failed with exit code: N" diagnostic, and the divergence is invisible to a
reader of either file.

**Fix:** chain rather than replace:
```bash
trap "rm -f '${deployed_caddyfile}' '${adapted_routes}'; cleanup" EXIT
```
or define `cleanup_hook`, which `cleanup.sh:6-8` already supports for exactly this purpose.

### WR-17: ser8 still evaluates with a deprecation warning after the bump

**File:** `hosts/ser8/media/sabnzbd.nix:8` (setter), surfaced through
`modules/media/sabnzbd.nix`
**Issue:** `config.warnings` on ser8 is non-empty:

```
["`sabnzbd.configFile` is deprecated, consider using `sabnzbd.settings` instead.
  If you have values set in `sabnzbd.settings` set, they will be ignored."]
```

firebat, pi4, and pi5 are clean. CLAUDE.md: "Treat warnings from formatters, linters,
evaluators, and tests as failures to resolve." The migration risk is real and
`deferred-items.md` justifies deferring it, so this is recorded rather than disputed — but note
the structural gap it reveals: `make check` (`Makefile:140-152`) has no assertion on
`config.warnings`, so a *new* renamed-option warning introduced by the next channel bump would
also pass unnoticed. That is how this one survived.

**Fix (the gate, not the sabnzbd migration):** add a warnings check to `make check` with an
explicit allowlist:
```bash
# scripts/validation/test-no-new-warnings.sh
for host in ser8 firebat pi4 pi5; do
	nix eval --json ".#nixosConfigurations.$host.config.warnings" \
		| jq --slurpfile allow "baselines/$host-warnings.json" -e '. - $allow[0] | length == 0'
done
```

### WR-18: 26.05's servarr module rewrite was reviewed only for `UMask`

**File:** `modules/media/radarr.nix:24-29`, `modules/media/sonarr.nix:24-29`
**Issue:** The `UMask` force is correct and well-justified — verified against
`$nixpkgs/nixos/modules/services/misc/servarr/radarr.nix:82` and `sonarr.nix:104`, both of which
set `UMask = "0022"` in 26.05. But the same `serviceConfig` block also carries
`PrivateUsers = true`, `ProtectHome = true`, `ProtectProc = "invisible"`, `PrivateDevices`,
`RestrictAddressFamilies`, and a `SystemCallFilter` with `~@mount`. None of these were assessed
against radarr/sonarr writing into the FUSE-backed MergerFS mount at `/mnt/media`, and
`scripts/smoketests/ser8/all.sh` contains no check that exercises an import or hardlink into the
media pool — `media/all.sh` tests HTTP reachability only.

The failure mode is not a crash: the services start, answer HTTP, and stop moving files.
Every gate on the ser8 deploy path would stay green.

**Fix:** add one write-through assertion to the media suite — as the `radarr` user, create and
hardlink a temp file under the same MergerFS path radarr imports into, confirm mode `0664` and
group `media`, remove it. That is the property `UMask = 0002` exists to guarantee, and nothing
currently asserts it.

### WR-19: Commented-out code left in modified files

**File:** `modules/common/networking.nix:47-71`, `:112-132`;
`hosts/pi4/configuration.nix:37-56`
**Issue:** Three blocks of commented-out option declarations and configuration
(`staticIP`, `gateway`, `defaultGateway`, the pi4 static-IP block). The pi4 block opens with
"Bottom is WRONG" and then preserves twenty lines of the wrong approach. Project standard:
"No commented-out code—delete it. If you need a comment to explain WHAT the code does, refactor
the code instead."

The pi4 block's *reasoning* (the DHCP circular dependency) is valuable; the dead Nix around it
is not.

**Fix:** delete the commented option/config blocks; keep the pi4 circular-dependency
explanation as a two-line prose comment.

## Info

### IN-01: `test-qbittorrent-confinement.sh`'s `EGRESS_URL` comment does not describe the line it annotates

**File:** `scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh:43-45`
**Issue:** "A hostname, never a literal address, so deploy.yaml stays the only source of address
truth" — `ipinfo.io` is a third-party service that has no relationship to `deploy.yaml`. The
rationale appears to have been copied from a different constant.
**Fix:** describe what the constant is (an external egress-address reporter) and why it is
trusted.

### IN-02: `test-caddy.sh`'s jq produces a cartesian product and the map keeps only the last upstream

**File:** `scripts/smoketests/gateway/test-caddy.sh:141-149`
**Issue:** `($route.match[].host[]) + "=" + ($route.handle[].routes[].handle[].upstreams[].dial)`
emits every host × every upstream in a route, and `caddy_routes["$server"]="$upstream"`
keeps the last write. Harmless today (each site block has exactly one upstream), silently lossy
the first time a block gets two.
**Fix:** key the map by `host` to a list, or emit one line per (host, upstream) pair and iterate
lines rather than an associative array.

### IN-03: Redundant `set -e` in the Makefile host loop

**File:** `Makefile:147-152`
**Issue:** `.SHELLFLAGS := -e -c` (line 5) already applies `-e` to every recipe, so the `set -e;`
added to the `check` loop is a no-op. Harmless, but it implies the surrounding recipe is not
under `-e`, which it is.
**Fix:** drop the `set -e;` or drop the confusion by dropping `-e` from `.SHELLFLAGS` and being
explicit per recipe.

### IN-04: SIGPIPE status leaks out of the Home Assistant error printer

**File:** `scripts/smoketests/ser8/test-home-assistant.sh:120-122`
**Issue:** `echo "$errors" | head -10 | while ...` under `pipefail` returns 141 when there are
more than ten errors, because `head` exits and `echo` takes SIGPIPE. The function then returns
141 rather than 1. Both count as a failure through `run_test`, so behaviour is correct, but the
status is misleading in any future caller that inspects it.
**Fix:** `printf '%s\n' "$errors" | head -10 | while ...; do ...; done || true`, or slice with
bash rather than piping.

### IN-05: Sourced-only libraries carry executable shebangs but are mode 644

**File:** `scripts/smoketests/lib/fanout.sh:1`, `scripts/smoketests/lib/services.sh:1`
**Issue:** Both start with `#!/usr/bin/env bash` while being `-rw-r--r--` and documented as
"Sourced, never executed" (`fanout.sh:6`). The shebang invites someone to `chmod +x` and run
them, which would do nothing useful.
**Fix:** keep the shebang solely as a shellcheck shell directive but add
`# shellcheck shell=bash` and drop the shebang, or leave as-is and note it — low stakes either
way.

### IN-06: Untracked cache directory is not gitignored

**File:** `.gitignore`
**Issue:** `git status` shows `.planning/research/.cache/` untracked. The phase added `.gsd/` to
`.gitignore` but not this.
**Fix:** add `.planning/research/.cache/` alongside the `.gsd/` entry.

---

_Reviewed: 2026-08-17T21:10:17Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
