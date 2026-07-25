---
status: resolved
trigger: "ser8.local is absent from Grafana host selectors except Service Uptime & Status"
created: 2026-07-25
updated: 2026-07-25
---

# ser8 Metrics Missing from Grafana

## Symptoms

- Expected behavior: ser8.local appears as a host option in ser8-backed Grafana dashboards.
- Actual behavior: ser8.local is absent from Node Exporter Full, Systemd Service Dashboard, ZFS, Services Resource Usage, Jellyfin, and similar dashboards.
- Error messages: none reported.
- Timeline: previously worked; exact start time unknown.
- Reproduction: open the affected dashboard and inspect its host or instance selector.
- Known exception: Service Uptime & Status still reports ser8.
- Environmental note: pi4 is intentionally offline and its failures are out of scope.

## Current Focus

- hypothesis: Confirmed. Avahi renamed ser8 to ser8-31.local after hostname conflicts triggered during NordVPN veth churn, and systemd-resolved lacked per-link mDNS resolution.
- test: Compared NSS, resolved, and Avahi queries; captured mDNS packets on both hosts; inspected Avahi state and collision logs.
- expecting: Confirmed. firebat sends valid queries for ser8.local, but ser8 advertises only ser8-31.local after repeated hostname conflicts.
- next_action: Deploy ser8 first, verify it reclaims ser8.local, then deploy firebat and verify that all nine Prometheus targets become healthy.
- reasoning_checkpoint:
- tdd_checkpoint:

## Evidence

- timestamp: 2026-07-25
  observation: All affected dashboard variables query exporter metrics whose Prometheus targets use ser8.local.
  implication: Missing selector values mean the corresponding series are absent or stale in Prometheus.
- timestamp: 2026-07-25
  observation: The working uptime dashboard is backed by blackbox targets using 192.168.68.65 directly.
  implication: Basic ser8 reachability can remain visible even if firebat cannot resolve ser8.local.
- timestamp: 2026-07-25
  observation: All nine live ser8 exporter targets are down with `dial tcp: lookup ser8.local: device or resource busy`.
  implication: Prometheus cannot ingest the series used by the affected dashboard selectors.
- timestamp: 2026-07-25
  observation: Direct HTTP requests to ser8 exporter ports 9100, 9134, 9558, 9256, and 9711 all return HTTP 200.
  implication: ser8 and its exporters are healthy; the failure occurs before connection, during name resolution on firebat.
- timestamp: 2026-07-25
  observation: All direct-IP blackbox HTTP and ICMP targets for 192.168.68.65 are up.
  implication: This explains why Service Uptime & Status still shows ser8.
- timestamp: 2026-07-25
  observation: Prometheus returns no current ser8 series for node, systemd, process, or Jellyfin selector metrics.
  implication: Grafana correctly omits ser8 from variables derived from those series.
- timestamp: 2026-07-25
  observation: The Caddy configuration documents the same resolver error and already uses static IPs as its solution.
  implication: Prometheus configuration did not receive the established static-IP resolution fix.
- timestamp: 2026-07-25
  observation: A simultaneous packet capture showed firebat's mDNS questions arriving on ser8, with no answer for ser8.local.
  implication: LAN multicast transport and firewalls are working; ser8 declined to answer for that name.
- timestamp: 2026-07-25
  observation: Avahi on ser8 reports its active hostname as ser8-31.local, which resolves successfully from firebat.
  implication: ser8.local disappeared because Avahi automatically renamed the host after conflicts.
- timestamp: 2026-07-25
  observation: The rename occurred during repeated teardown and recreation of the NordVPN veth-host interface.
  implication: Allowing Avahi on transient virtual interfaces made hostname publication vulnerable to interface churn.
- timestamp: 2026-07-25
  observation: systemd-resolved reported mDNS disabled on both physical LAN links.
  implication: Applications using the resolved DNS stub could not use mDNS even when Avahi publication was healthy.

## Eliminated

- hypothesis: Grafana lost or misconfigured its Prometheus datasource.
  evidence: firebat and other healthy targets remain queryable through the same datasource, while only failed target series are absent.
- hypothesis: ser8 or its exporters are down.
  evidence: ser8 direct-IP probes are up and five representative exporter endpoints return HTTP 200.
- hypothesis: Dashboard variables are statically missing ser8.
  evidence: affected variables use `label_values` over live Prometheus series, so values disappear when series become stale.

## Resolution

- root_cause: Avahi monitored the transient NordVPN veth-host interface and renamed ser8 to ser8-31.local after repeated hostname conflicts. Separately, systemd-resolved had mDNS disabled on the physical links, preventing DNS-stub clients from resolving healthy Avahi names.
- fix: Restricted Avahi publication to each host's configured physical LAN interface. Configured systemd-resolved for resolver-only mDNS globally and per link. Removed duplicate Raspberry Pi mDNS settings. Restored Prometheus to ser8.local targets.
- verification: Formatting, Statix, diff checks, targeted settings evaluation, and full derivation evaluation pass for ser8, firebat, pi4, and pi5. Live deployment verification remains.
- files_changed: modules/common/networking.nix, modules/raspberrypi/base.nix, and this diagnostic record.
