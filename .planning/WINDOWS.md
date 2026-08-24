---
schema_version: 1
open_count: 11
waived_count: 0
fixed_count: 0
total_count: 11
last_updated: 2026-08-24T01:17:42.094Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 09 | unrun-verify | scripts/smoketests/gateway/test-caddy.sh |  | gateway/all.sh firebat exit-0 not observed: session sandbox blocks bash process substitution used by test-caddy.sh | open |  | 2026-08-17T08:11:07.333Z |  |
| 2 | 09 | unrun-verify | scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh |  | confinement check green-against-real-ser8 not observed: ser8 wgnord tunnel is down (pre-existing outage) | open |  | 2026-08-17T08:11:07.422Z |  |
| 3 | 09 | unrun-verify | scripts/smoketests/ser8/all.sh |  | make smoketests-ser8 exit-0 against pre-bump ser8 not observed: NordVPN suite red from a pre-existing tunnel outage plus test-forwarding.sh querying the retired pi4 resolver | open |  | 2026-08-17T08:28:08.704Z |  |
| 4 | 09 | deviation | scripts/smoketests/ser8/test-zfs-health.sh |  | ZFS feature-flag assertion inverted vs plan wording: requires the upgrade prompt to be PRESENT, since its absence means zpool upgrade ran and the previous generation can no longer import the pool | open |  | 2026-08-17T08:28:08.800Z |  |
| 5 | 09 | deviation | scripts/smoketests/nordvpn/test-forwarding.sh |  | hard-codes 192.168.68.56 (retired pi4 AdGuard resolver); violates the no-literal-address rule, deferred to the .vofi re-establishment work | open |  | 2026-08-17T08:28:08.896Z |  |
| 6 | 10 | deviation | .planning/phases/10-household-foundation-and-mealie/10-01-PLAN.md |  | Task 1 acceptance criterion for the impermanence persistence entry used a nix eval --json of the whole directories list, which errors on the impermanence submodule's removed 'method' option; substituted an equivalent --apply 'map (d: d.directory)' check | open |  | 2026-08-18T06:55:10.333Z |  |
| 7 | 10 | deviation | scripts/smoketests/household/test-mealie-service.sh |  | to_regclass appears once, not twice: the three table checks share one assert_table_non_empty helper rather than duplicating the resolve-then-count sequence; PD-04 intent (named failure on a wrong table name) holds for all three tables | open |  | 2026-08-18T07:09:06.185Z |  |
| 8 | 10 | deviation | scripts/smoketests/gateway/test-tailscale.sh |  | shfmt -d with default tab indent rewrites this pre-existing 2-space file; it is clean under shfmt -i 2 both before and after the one-line mealie append, and the plan requires preserving its indentation | open |  | 2026-08-18T07:09:06.275Z |  |
| 9 | 10 | unmet-truth | scripts/smoketests/household/all.sh |  | Household smoketest area exits 1 after plan 10-04: default_admin_rejected owned by 10-06, tsnet_dns and tsnet_https owned by 10-05 | open |  | 2026-08-18T19:03:17.076Z |  |
| 10 | 10 | deviation | scripts/smoketests/media |  | media area reports SABnzbd HTTP 200 while sabnzbd.service is in the failed state; asserts HTTP only, never unit state | open |  | 2026-08-18T19:03:17.176Z |  |
| 11 | 12 | deviation | modules/media/sabnzbd.nix |  | sabnzbd host_whitelist and local_ranges fixed live via API/ini edit to unblock the tsnet gateway route (D-13); not declared in Nix because services.sabnzbd.configFile->settings migration is a separate deferred item. A future full state loss/rebuild of /var/lib/sabnzbd would need these reapplied manually until that migration lands. | open |  | 2026-08-24T01:17:42.094Z |  |

````json
[
  {
    "id": 1,
    "kind": "unrun-verify",
    "phase": "09",
    "file": "scripts/smoketests/gateway/test-caddy.sh",
    "line": null,
    "description": "gateway/all.sh firebat exit-0 not observed: session sandbox blocks bash process substitution used by test-caddy.sh",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T08:11:07.333Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "unrun-verify",
    "phase": "09",
    "file": "scripts/smoketests/nordvpn/test-qbittorrent-confinement.sh",
    "line": null,
    "description": "confinement check green-against-real-ser8 not observed: ser8 wgnord tunnel is down (pre-existing outage)",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T08:11:07.422Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "09",
    "file": "scripts/smoketests/ser8/all.sh",
    "line": null,
    "description": "make smoketests-ser8 exit-0 against pre-bump ser8 not observed: NordVPN suite red from a pre-existing tunnel outage plus test-forwarding.sh querying the retired pi4 resolver",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T08:28:08.704Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "09",
    "file": "scripts/smoketests/ser8/test-zfs-health.sh",
    "line": null,
    "description": "ZFS feature-flag assertion inverted vs plan wording: requires the upgrade prompt to be PRESENT, since its absence means zpool upgrade ran and the previous generation can no longer import the pool",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T08:28:08.800Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "deviation",
    "phase": "09",
    "file": "scripts/smoketests/nordvpn/test-forwarding.sh",
    "line": null,
    "description": "hard-codes 192.168.68.56 (retired pi4 AdGuard resolver); violates the no-literal-address rule, deferred to the .vofi re-establishment work",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-17T08:28:08.896Z",
    "resolved_at": null
  },
  {
    "id": 6,
    "kind": "deviation",
    "phase": "10",
    "file": ".planning/phases/10-household-foundation-and-mealie/10-01-PLAN.md",
    "line": null,
    "description": "Task 1 acceptance criterion for the impermanence persistence entry used a nix eval --json of the whole directories list, which errors on the impermanence submodule's removed 'method' option; substituted an equivalent --apply 'map (d: d.directory)' check",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T06:55:10.333Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "deviation",
    "phase": "10",
    "file": "scripts/smoketests/household/test-mealie-service.sh",
    "line": null,
    "description": "to_regclass appears once, not twice: the three table checks share one assert_table_non_empty helper rather than duplicating the resolve-then-count sequence; PD-04 intent (named failure on a wrong table name) holds for all three tables",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T07:09:06.185Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "deviation",
    "phase": "10",
    "file": "scripts/smoketests/gateway/test-tailscale.sh",
    "line": null,
    "description": "shfmt -d with default tab indent rewrites this pre-existing 2-space file; it is clean under shfmt -i 2 both before and after the one-line mealie append, and the plan requires preserving its indentation",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T07:09:06.275Z",
    "resolved_at": null
  },
  {
    "id": 9,
    "kind": "unmet-truth",
    "phase": "10",
    "file": "scripts/smoketests/household/all.sh",
    "line": null,
    "description": "Household smoketest area exits 1 after plan 10-04: default_admin_rejected owned by 10-06, tsnet_dns and tsnet_https owned by 10-05",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T19:03:17.076Z",
    "resolved_at": null
  },
  {
    "id": 10,
    "kind": "deviation",
    "phase": "10",
    "file": "scripts/smoketests/media",
    "line": null,
    "description": "media area reports SABnzbd HTTP 200 while sabnzbd.service is in the failed state; asserts HTTP only, never unit state",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-18T19:03:17.176Z",
    "resolved_at": null
  },
  {
    "id": 11,
    "kind": "deviation",
    "phase": "12",
    "file": "modules/media/sabnzbd.nix",
    "line": null,
    "description": "sabnzbd host_whitelist and local_ranges fixed live via API/ini edit to unblock the tsnet gateway route (D-13); not declared in Nix because services.sabnzbd.configFile->settings migration is a separate deferred item. A future full state loss/rebuild of /var/lib/sabnzbd would need these reapplied manually until that migration lands.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-24T01:17:42.094Z",
    "resolved_at": null
  }
]
````
