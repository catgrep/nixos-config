---
phase: 04-alert-delivery-service-probes
plan: 02
subsystem: infra
tags: [blackbox-exporter, prometheus, grafana, probes, tls]

requires:
  - phase: 04-alert-delivery-service-probes
    plan: 01
    provides: Grafana email delivery, contact point, notification policy
provides:
  - Blackbox exporter with HTTP, ICMP, and TLS probe modules
  - Prometheus scrape jobs for 8 HTTP services, 3 ICMP hosts, 9 TLS URLs
  - 3 probe-based Grafana alert rules (service_down, host_unreachable, tls_cert_expiring)
  - TLS certificate expiry metrics for all Tailscale URLs
affects: [05-hardware-alerts, 05-status-dashboard]

tech-stack:
  added: [prometheus-blackbox-exporter]
  patterns: [blackbox-relabel-config, multi-target-exporter-pattern]

key-files:
  created:
    - modules/gateway/blackbox.nix
  modified:
    - modules/gateway/default.nix
    - modules/gateway/prometheus.nix
    - modules/gateway/grafana.nix

key-decisions:
  - "Use direct IPs instead of .local mDNS for blackbox probe targets — blackbox exporter cannot resolve mDNS"
  - "TLS probes use Tailscale URLs (real Let's Encrypt certs) at 5-min interval"
  - "HTTP probes hit direct service ports, not Caddy reverse proxy"

patterns-established:
  - "Blackbox multi-target relabel: __address__ → __param_target → instance, then __address__ = localhost:9115"
  - "Probe alert rules use same three-step data model as infrastructure rules"

duration: ~20min
completed: 2026-02-12
---

# Plan 04-02: Blackbox Exporter & Service Probes Summary

**Blackbox HTTP/ICMP/TLS probes for 8 services, 3 hosts, and 9 Tailscale URLs with 3 probe-based alert rules delivering email on failure**

## Performance

- **Duration:** ~20 min
- **Tasks:** 3 (2 auto + 1 verification)
- **Files modified:** 4

## Accomplishments
- Blackbox exporter running on firebat with http_2xx, icmp_ping, and tls_connect modules
- All 8 HTTP service probes returning probe_success=1
- All 3 ICMP host probes returning probe_success=1
- TLS certificate expiry metrics visible for all 9 Tailscale URLs
- 3 new probe-based alert rules: service_down (2m), host_unreachable (2m), tls_cert_expiring (14 days)

## Task Commits

1. **Task 1: Create blackbox exporter and scrape jobs** - `b5eb3aa`
2. **Task 2: Add 3 probe-based alert rules** - `abf087d`
3. **Task 3: Verify probes** - `9823b96` (fix: .local → direct IPs)

## Files Created/Modified
- `modules/gateway/blackbox.nix` - New module: blackbox exporter with 3 probe modules
- `modules/gateway/default.nix` - Added blackbox.nix import
- `modules/gateway/prometheus.nix` - 3 blackbox scrape jobs (HTTP, ICMP, TLS)
- `modules/gateway/grafana.nix` - homelab_probes rule group with 3 alert rules

## Decisions Made
- Used direct IP addresses for blackbox probe targets — blackbox exporter process cannot resolve .local mDNS
- Kept 5-minute interval for TLS probes (certificates change infrequently)

## Deviations from Plan

### Auto-fixed Issues

**1. Blackbox exporter mDNS resolution failure**
- **Found during:** Task 3 (verification)
- **Issue:** All HTTP probes returning 0, ICMP probes to remote hosts returning 0. Blackbox exporter process cannot resolve .local mDNS hostnames.
- **Fix:** Replaced .local hostnames with direct IP addresses (ser8=192.168.68.65, firebat=192.168.68.63, pi4=192.168.68.56)
- **Files modified:** modules/gateway/prometheus.nix
- **Verification:** All probes returning value 1 after redeployment
- **Committed in:** 9823b96

---

**Total deviations:** 1 auto-fixed
**Impact on plan:** mDNS workaround required for blackbox exporter. No scope creep.

## Issues Encountered
- Stale .local series persisted in Prometheus after switching to IPs — cleaned via admin API delete_series + clean_tombstones

## Next Phase Readiness
- Phase 4 complete — email alerts and service probes fully operational
- Ready for Phase 5: Hardware Alerts & Status Dashboard

---
*Phase: 04-alert-delivery-service-probes*
*Completed: 2026-02-12*
