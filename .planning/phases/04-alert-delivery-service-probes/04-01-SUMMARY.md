---
phase: 04-alert-delivery-service-probes
plan: 01
subsystem: infra
tags: [grafana, smtp, alerting, sops, nix]

requires:
  - phase: 03-camera-dashboard
    provides: working Grafana instance on firebat with Prometheus datasource
provides:
  - Grafana SMTP email delivery via Gmail
  - Contact point "email-alerts" sending to catgrep@sudomail.com
  - Notification policy routing severity labels to email
  - 6 Grafana-managed alert rules mirroring Prometheus ruleFiles
  - Stable datasource UID "prometheus" for alert rule references
affects: [04-02-blackbox-probes, 05-hardware-alerts]

tech-stack:
  added: []
  patterns: [grafana-provisioned-alerting, sops-file-secret-pattern]

key-files:
  created: []
  modified:
    - modules/gateway/grafana.nix
    - secrets/firebat.yaml

key-decisions:
  - "Gmail App Password via SOPS $__file{} pattern — password never in Nix store"
  - "Alert recipient catgrep@sudomail.com, sender shadbangus@gmail.com"
  - "Kept existing Prometheus ruleFiles as defense-in-depth alongside Grafana-managed rules"
  - "Stable datasource uid = prometheus for cross-referencing in alert rules"

patterns-established:
  - "Grafana alert rule three-step data model: Query A → Reduce B → Threshold C"
  - "SOPS secret with owner=grafana for Grafana service secrets"

duration: ~25min
completed: 2026-02-12
---

# Plan 04-01: Grafana SMTP Email Delivery Summary

**Gmail SMTP alerting with 6 provisioned infrastructure rules (host down, disk, memory, ZFS, CPU temp, camera storage) delivering to catgrep@sudomail.com**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3 (1 checkpoint + 1 auto + 1 verification)
- **Files modified:** 2

## Accomplishments
- Grafana sends email alerts via Gmail SMTP with App Password secured in SOPS
- 6 Grafana-managed alert rules mirror existing Prometheus rules — all infrastructure alerts now actionable
- Contact point, notification policy, and alert rules all declaratively provisioned from Nix
- Test email verified arriving at catgrep@sudomail.com

## Task Commits

1. **Task 1: Add Gmail App Password to SOPS** - (user action, secrets/firebat.yaml)
2. **Task 2: Configure Grafana SMTP, alerting, 6 alert rules** - `e1a2c29`
3. **Task 3: Verify email delivery** - `ec44129` (fix: recipient address update)

## Files Created/Modified
- `modules/gateway/grafana.nix` - SMTP config, contact point, notification policy, 6 alert rules, datasource UID
- `secrets/firebat.yaml` - grafana_smtp_password and grafana_smtp_user SOPS secrets

## Decisions Made
- Used catgrep@sudomail.com as alert recipient (separate from sender shadbangus@gmail.com)
- Kept Prometheus ruleFiles alongside Grafana rules for defense-in-depth

## Deviations from Plan

### Auto-fixed Issues

**1. Contact point recipient address**
- **Found during:** Task 3 (verification)
- **Issue:** Plan used shadbangus@gmail.com as both sender and recipient; user wanted alerts at catgrep@sudomail.com
- **Fix:** Updated contact point addresses to catgrep@sudomail.com
- **Committed in:** ec44129

---

**Total deviations:** 1 auto-fixed
**Impact on plan:** Minor recipient address change per user preference. No scope creep.

## Issues Encountered
None — build and deployment succeeded after SOPS secrets were added.

## Next Phase Readiness
- Email delivery foundation complete for plan 04-02 (blackbox probes)
- 04-02 will add 3 more probe-based alert rules to the existing alerting config

---
*Phase: 04-alert-delivery-service-probes*
*Completed: 2026-02-12*
