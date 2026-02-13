---
phase: 05-hardware-alerts-status-dashboard
plan: 01
subsystem: infra
tags: [prometheus, grafana, alerting, disk-usage, cpu-usage, promql]

# Dependency graph
requires:
  - phase: 04-alert-delivery-service-probes
    provides: "Grafana unified alerting with SMTP email delivery, file-provisioned alert rules pattern"
provides:
  - "Graduated disk alerts: warning at 80%, critical at 90% with pseudo-filesystem filtering"
  - "CPU sustained usage alert: warning at >90% for 5 minutes"
  - "Prometheus defense-in-depth ruleFiles matching Grafana-managed rules"
  - "deleteRules pattern for removing deprecated file-provisioned alerts"
affects: [05-02, monitoring, alerting]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Grafana deleteRules for removing deprecated file-provisioned alert rules"
    - "Graduated alert thresholds (warning + critical) with severity-based routing"
    - "PromQL filesystem filtering: fstype!~ and mountpoint!~ to exclude pseudo-filesystems"
    - "rate() over irate() for alert expressions requiring smooth signals"

key-files:
  created: []
  modified:
    - modules/gateway/grafana.nix
    - modules/gateway/prometheus.nix

key-decisions:
  - "Use deleteRules to explicitly remove deprecated file-provisioned alert rules from Grafana"
  - "Filter pseudo-filesystems by both fstype and mountpoint for comprehensive coverage"
  - "Use rate() not irate() for CPU usage alerting (smoother signal, less false-positive prone)"

patterns-established:
  - "deleteRules pattern: Grafana file provisioning doesn't auto-delete removed rules; must list UIDs in deleteRules array"
  - "Graduated alerts: same PromQL expression with different thresholds and severity labels"

# Metrics
duration: 10min
completed: 2026-02-13
---

# Phase 5 Plan 1: Graduated Disk Alerts and CPU Usage Alert Summary

**Graduated disk usage alerts (80% warning, 90% critical) with pseudo-filesystem filtering, CPU sustained usage alert, and Prometheus defense-in-depth rules**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-13T07:59:24Z
- **Completed:** 2026-02-13T08:09:24Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Replaced single-threshold disk alert (90%) with graduated warning (80%) and critical (90%) rules
- Added CPU sustained usage alert (>90% for 5 minutes) to both Grafana and Prometheus
- Filtered pseudo-filesystems (tmpfs, overlay, squashfs, devtmpfs, fuse.mergerfs) and system mount points (/boot, /run, /sys, /proc, /dev) from disk alerts
- Updated Prometheus ruleFiles to match Grafana-managed rules as defense-in-depth
- Deployed to firebat and verified all 11 alert rules active in Grafana, all 8 Prometheus rules loaded

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace disk alert with graduated rules and add CPU alert** - `32db5f2` (feat)
2. **Task 1 fix: Add deleteRules for old high_disk_usage** - `1797da5` (fix)

Task 2 was deployment and verification only (no code changes).

## Files Created/Modified
- `modules/gateway/grafana.nix` - Replaced high_disk_usage with disk_usage_warning + disk_usage_critical, added high_cpu_usage, added deleteRules for deprecated rule, added fstype filter to camera_storage_high
- `modules/gateway/prometheus.nix` - Replaced HighDiskUsage with HighDiskUsageWarning + HighDiskUsageCritical, added HighCPUSustained

## Decisions Made
- **deleteRules for deprecated rules:** Grafana file provisioning inserts/updates rules but never deletes them. Added explicit deleteRules list to remove the old high_disk_usage rule. This pattern should be used whenever removing a file-provisioned alert rule.
- **Filesystem filtering:** Used both fstype exclusion (tmpfs, overlay, squashfs, devtmpfs, fuse.mergerfs) and mountpoint exclusion (/boot, /run, /sys, /proc, /dev) for comprehensive pseudo-filesystem filtering.
- **rate() for CPU alerting:** Used rate() instead of irate() for the CPU usage expression because rate() provides a smoother signal more suitable for alerting, reducing false positives from momentary spikes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Old high_disk_usage rule persisted in Grafana after removal from provisioning**
- **Found during:** Task 2 (deployment verification)
- **Issue:** Grafana file-provisioned alert rules persist in the database even after being removed from the provisioning YAML file. The old high_disk_usage rule remained alongside the new graduated rules.
- **Fix:** Added `deleteRules` list to `alerting.rules.settings` in grafana.nix, specifying the old high_disk_usage UID for explicit deletion
- **Files modified:** modules/gateway/grafana.nix
- **Verification:** After redeployment, Grafana API confirmed 11 total rules with no high_disk_usage present
- **Committed in:** `1797da5`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correct rule lifecycle. Established deleteRules pattern for future use.

## Issues Encountered
- mDNS hostname resolution (`firebat`) not available from macOS build host; used direct IP (192.168.68.63) for SSH verification commands
- PromQL query escaping through SSH required careful quoting; used simpler queries for verification

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All hardware alerts (disk, CPU, memory, temperature, ZFS) now have Grafana-managed rules with email delivery
- Ready for Phase 5 Plan 2: Status dashboard implementation
- Total alert rules: 11 Grafana-managed (8 infrastructure + 3 probes), 8 Prometheus defense-in-depth

## Self-Check: PASSED

All files exist, all commits verified, all UIDs present, old rule removed (only in deleteRules), Prometheus rules confirmed.

---
*Phase: 05-hardware-alerts-status-dashboard*
*Completed: 2026-02-13*
