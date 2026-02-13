---
phase: 05-hardware-alerts-status-dashboard
plan: 02
subsystem: infra
tags: [grafana, dashboard, uptime, msmtp, zfs-zed, blackbox-exporter, tls, state-timeline]

# Dependency graph
requires:
  - phase: 05-hardware-alerts-status-dashboard
    plan: 01
    provides: "Graduated disk/CPU alerts, Grafana unified alerting with file-provisioned rules pattern"
  - phase: 04-alert-delivery-service-probes
    provides: "Blackbox exporter with HTTP/ICMP/TLS probes, Grafana SMTP email delivery"
provides:
  - "Grafana uptime dashboard with 24h availability stats, HTTP/ICMP state-timelines, TLS cert expiry panels"
  - "msmtp lightweight MTA on ser8 for system email via Gmail SMTP"
  - "ZFS Event Daemon (zed) on ser8 sending scrub error emails to catgrep@sudomail.com"
  - "12 total Grafana dashboards (was 11)"
affects: [monitoring, alerting, zfs]

# Tech tracking
tech-stack:
  added: [msmtp]
  patterns:
    - "Grafana state-timeline with field overrides for friendly display names"
    - "msmtp as system sendmail with SOPS-managed Gmail App Password"
    - "ZFS zed enableMail with msmtp backend for scrub error notifications"

key-files:
  created:
    - dashboards/uptime.json
  modified:
    - modules/gateway/grafana.nix
    - hosts/ser8/configuration.nix

key-decisions:
  - "Use Grafana field overrides (displayName) to map raw IP:port instance labels to friendly service names"
  - "msmtp as lightweight MTA (not full postfix/sendmail) since only zed needs email on ser8"
  - "ZFS zed uses system sendmail (msmtp) rather than custom mail script"
  - "/var/log/msmtp.log persists naturally via ser8 impermanence /var/log bind mount"

patterns-established:
  - "State-timeline with value mappings: 0=DOWN(red), 1=UP(green) for probe_success metrics"
  - "SOPS secret with passwordeval pattern: cat ${config.sops.secrets.NAME.path} for msmtp"
  - "Dashboard provisioning pattern: let binding + tmpfiles symlink + restartTriggers"

# Metrics
duration: 11min
completed: 2026-02-13
---

# Phase 5 Plan 2: Uptime Dashboard and ZFS Zed Email Alerts Summary

**Grafana uptime dashboard with state-timeline service status, 24h availability stats, and TLS cert expiry; msmtp + ZFS zed on ser8 for scrub error email alerts**

## Performance

- **Duration:** 11 min
- **Started:** 2026-02-13T08:19:36Z
- **Completed:** 2026-02-13T08:31:02Z
- **Tasks:** 3 (1 checkpoint + 2 auto)
- **Files created/modified:** 3

## Accomplishments
- Created dashboards/uptime.json with 4 panel sections: 8 service availability stat panels (24h %), HTTP state-timeline, ICMP host reachability timeline, 9 TLS certificate expiry stat panels
- Added uptime dashboard to Grafana provisioning (12 total dashboards)
- Configured msmtp as lightweight MTA on ser8 with Gmail SMTP relay (SOPS-managed password)
- Configured ZFS Event Daemon (zed) on ser8 to email scrub errors to catgrep@sudomail.com
- Deployed both firebat and ser8; verified all services at 100% availability, all 3 hosts reachable, TLS certs 66-78 days remaining

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Gmail SMTP password to ser8 SOPS secrets** - (user action, no commit hash)
2. **Task 2: Create uptime dashboard and configure msmtp + zed** - `f36f448` (feat)

Task 3 was deployment and verification only (no code changes).

## Files Created/Modified
- `dashboards/uptime.json` - Grafana uptime dashboard with service availability stats, HTTP/ICMP state-timelines, TLS cert expiry panels (984 lines)
- `modules/gateway/grafana.nix` - Added uptime dashboard to provisioning (let binding + tmpfiles symlink)
- `hosts/ser8/configuration.nix` - Added msmtp MTA config, ZFS zed email settings, gmail_smtp_password SOPS secret

## Decisions Made
- **Field overrides for friendly names:** Used Grafana field overrides with `displayName` property to map raw instance labels (e.g., `http://192.168.68.65:8096`) to friendly names (e.g., "Jellyfin") in state-timeline panels. This avoids relabeling in Prometheus while keeping dashboard readable.
- **msmtp over full MTA:** Chose msmtp as a minimal sendmail replacement since only ZFS zed needs email capability on ser8. No need for a full Postfix/Exim installation.
- **Shared Gmail App Password:** Reused the same Gmail App Password already configured on firebat for Grafana SMTP. Both hosts use shadbangus@gmail.com as sender.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Non-interactive deployment: The `make switch-*` targets require confirmation prompt. Used `NO_CONFIRM=true` environment variable to bypass in automated context.
- Nix flake dirty tree: New `dashboards/uptime.json` had to be staged (`git add`) before `make check` would pass, since nix evaluates from the git tree and untracked files are invisible.
- SSH quoting: Prometheus API queries with `{job="blackbox-http"}` required `--data-urlencode` via POST to avoid shell escaping issues through SSH.

## User Setup Required
Task 1 required the user to add `gmail_smtp_password` to ser8's SOPS secrets file. This was completed before execution resumed.

## Verification Results
- Grafana dashboard "Service Uptime & Status" (uid: uptime-status) accessible with 23 panels
- All 8 HTTP services at 100.00% availability (24h)
- All 3 hosts (ser8, firebat, pi4) reachable via ICMP
- 9 TLS certificates checked: 66-78 days remaining
- Total Grafana dashboards: 12
- ser8 sendmail at `/run/wrappers/bin/sendmail` (msmtp)
- ser8 zed.rc shows ZED_EMAIL_ADDR="catgrep@sudomail.com", ZED_EMAIL_PROG="/run/wrappers/bin/sendmail"

## Next Phase Readiness
- Phase 5 complete: all hardware alerts (disk, CPU, memory, temperature, ZFS pool health, ZFS scrub errors) and status dashboard implemented
- Ready for Phase 6: Log Aggregation (Loki + Alloy)
- Total monitoring coverage: 11 Grafana alert rules, 8 Prometheus defense-in-depth rules, 12 dashboards, ZFS zed email alerts

## Self-Check: PASSED

All files exist, commit f36f448 verified, dashboard JSON valid (984 lines), grafana.nix references uptime dashboard, ser8 config contains msmtp and zed settings.

---
*Phase: 05-hardware-alerts-status-dashboard*
*Completed: 2026-02-13*
