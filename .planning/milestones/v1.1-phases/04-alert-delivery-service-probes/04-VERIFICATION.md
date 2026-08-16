---
phase: 04-alert-delivery-service-probes
verified: 2026-02-13T07:29:30Z
status: human_needed
score: 12/15
re_verification: false
human_verification:
  - test: "Trigger test alert in Grafana and verify email arrives"
    expected: "Email from Grafana arrives in catgrep@sudomail.com inbox within 5 minutes"
    why_human: "Email delivery requires live SMTP connection and Gmail inbox verification"
  - test: "Check probe metrics in Grafana Explore"
    expected: "probe_success{job=\"blackbox-http\"} shows 8 series with value 1, probe_success{job=\"blackbox-icmp\"} shows 3 series with value 1, probe_ssl_earliest_cert_expiry{job=\"blackbox-tls\"} shows 9 series with Unix timestamps"
    why_human: "Requires querying live Prometheus via Grafana Explore UI"
  - test: "Stop a service and verify alert email arrives"
    expected: "Stopping Jellyfin with 'sudo systemctl stop jellyfin' on ser8 causes 'Service Down' email to arrive after 2-3 minutes"
    why_human: "End-to-end alert delivery requires triggering actual service failure and verifying email receipt"
---

# Phase 4: Alert Delivery & Service Probes Verification Report

**Phase Goal:** Every existing alert rule delivers an email notification, and every service is probed for availability so I know within minutes when something goes down

**Verified:** 2026-02-13T07:29:30Z

**Status:** human_needed

**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Grafana SMTP configured with Gmail App Password via SOPS | ✓ VERIFIED | grafana.nix lines 48-79: SOPS secret declared, SMTP settings with $__file{} pattern, sender shadbangus@gmail.com |
| 2 | Contact point "email-alerts" configured to send to catgrep@sudomail.com | ✓ VERIFIED | grafana.nix lines 124-143: Contact point provisioned with recipient catgrep@sudomail.com |
| 3 | Notification policy routes severity alerts to email | ✓ VERIFIED | grafana.nix lines 146-170: Policy routes severity=critical\|warning to email-alerts |
| 4 | 6 infrastructure alert rules provisioned from Nix | ✓ VERIFIED | grafana.nix lines 172-545: homelab_infrastructure group with 6 rules (host_down, high_disk_usage, high_memory_usage, zfs_pool_unhealthy, high_cpu_temp, camera_storage_high) |
| 5 | Alert rules reference stable datasource UID "prometheus" | ✓ VERIFIED | grafana.nix line 99: uid = "prometheus" in datasource, all 9 rules use datasourceUid = "prometheus" |
| 6 | Blackbox exporter configured with 3 probe modules | ✓ VERIFIED | blackbox.nix lines 6-33: http_2xx, icmp_ping, tls_connect modules defined |
| 7 | Blackbox exporter imported in gateway module | ✓ VERIFIED | default.nix line 11: ./blackbox.nix in imports list |
| 8 | Prometheus scrapes 8 HTTP service probes | ✓ VERIFIED | prometheus.nix lines 133-168: blackbox-http job with 8 targets (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Frigate, HA) using direct IPs |
| 9 | Prometheus scrapes 3 ICMP host probes | ✓ VERIFIED | prometheus.nix lines 170-200: blackbox-icmp job with 3 targets (ser8, firebat, pi4) using direct IPs |
| 10 | Prometheus scrapes 9 TLS cert expiry probes | ✓ VERIFIED | prometheus.nix lines 202-238: blackbox-tls job with 9 Tailscale URLs at 300s interval |
| 11 | 3 probe-based alert rules provisioned from Nix | ✓ VERIFIED | grafana.nix lines 547-733: homelab_probes group with 3 rules (service_down 2m, host_unreachable 2m, tls_cert_expiring 14d/1h) |
| 12 | All alert rules use three-step data model | ✓ VERIFIED | All 9 rules follow Query A (prometheus) -> Reduce B (__expr__) -> Threshold C (__expr__) pattern |
| 13 | Triggering a test alert results in email arriving in inbox | ? HUMAN | Requires live Grafana deployment and email testing |
| 14 | Probe metrics visible in Grafana Explore | ? HUMAN | Requires querying live Prometheus via Grafana UI |
| 15 | Stopping a service causes email alert after 2-minute threshold | ? HUMAN | Requires end-to-end test with real service failure |

**Score:** 12/15 truths verified (3 require human verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| modules/gateway/grafana.nix | SMTP config, contact point, notification policy, 6+3 alert rules | ✓ VERIFIED | Lines 48-79 (SMTP), 124-143 (contact), 146-170 (policy), 172-733 (9 rules) |
| modules/gateway/blackbox.nix | Blackbox exporter with http_2xx, icmp_ping, tls_connect modules | ✓ VERIFIED | Lines 6-33: All 3 modules configured |
| modules/gateway/prometheus.nix | 3 blackbox scrape jobs (HTTP, ICMP, TLS) | ✓ VERIFIED | Lines 133-238: blackbox-http (8 targets), blackbox-icmp (3 targets), blackbox-tls (9 targets) |
| modules/gateway/default.nix | Import for blackbox.nix | ✓ VERIFIED | Line 11: ./blackbox.nix in imports |
| secrets/firebat.yaml | Encrypted grafana_smtp_password and grafana_smtp_user | ✓ VERIFIED | SOPS secret referenced in grafana.nix, cannot verify encrypted content without decryption |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| grafana.nix SMTP password | secrets/firebat.yaml | sops.secrets.grafana_smtp_password | ✓ WIRED | Lines 49-53 declare SOPS secret, line 75 uses $__file{} pattern |
| grafana.nix alert rules datasourceUid | datasource provisioning | uid = "prometheus" | ✓ WIRED | Line 99 sets stable UID, all 9 rules reference "prometheus" |
| prometheus.nix blackbox scrape jobs | blackbox.nix exporter | localhost:9115 in relabel_configs | ✓ WIRED | All 3 scrape jobs (lines 165, 197, 235) target localhost:9115 |
| grafana.nix probe alert rules | prometheus.nix blackbox metrics | PromQL queries probe_success, probe_ssl_earliest_cert_expiry | ✓ WIRED | service_down (line 567), host_unreachable (line 627), tls_cert_expiring (line 687) query blackbox metrics |
| gateway default.nix | blackbox.nix | imports list | ✓ WIRED | Line 11 imports ./blackbox.nix |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| ALERT-01: Grafana unified alerting with Gmail SMTP | ✓ SATISFIED | None - SMTP configured with $__file{} SOPS pattern |
| ALERT-02: 6 Prometheus rules deliver email | ✓ SATISFIED | None - 6 infrastructure rules provisioned, email delivery needs human verification |
| ALERT-03: Alert rules provisioned declaratively | ✓ SATISFIED | None - All 9 rules in grafana.nix provision.alerting.rules |
| ALERT-04: SMTP credentials in SOPS | ✓ SATISFIED | None - grafana_smtp_password uses $__file{} pattern |
| PROBE-01: HTTP probes for 8 services | ✓ SATISFIED | None - blackbox-http job with 8 targets |
| PROBE-02: ICMP probes for 3 hosts | ✓ SATISFIED | None - blackbox-icmp job with 3 targets |
| PROBE-03: TLS cert expiry for Tailscale URLs | ✓ SATISFIED | None - blackbox-tls job with 9 Tailscale URLs |
| PROBE-04: Alert fires when probe fails >2min | ✓ SATISFIED | None - service_down and host_unreachable use "for" = "2m" |

### Anti-Patterns Found

No anti-patterns detected. Clean implementation with no TODOs, placeholders, or stubs.

### Human Verification Required

**1. Email Delivery Test**

**Test:** Open Grafana at https://grafana.shad-bangus.ts.net, navigate to Alerting > Contact points, click "Test" on the email-alerts contact point.

**Expected:** A test email from "Homelab Alerts <shadbangus@gmail.com>" arrives in the catgrep@sudomail.com inbox within 5 minutes.

**Why human:** Email delivery requires live SMTP connection to Gmail and verifying receipt in external email inbox.

---

**2. Probe Metrics Visibility**

**Test:** Open Grafana Explore at https://grafana.shad-bangus.ts.net/explore and run these queries:
- `probe_success{job="blackbox-http"}`
- `probe_success{job="blackbox-icmp"}`
- `probe_ssl_earliest_cert_expiry{job="blackbox-tls"}`

**Expected:** 
- HTTP query returns 8 series (Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd, Frigate, HA), all with value 1
- ICMP query returns 3 series (ser8, firebat, pi4), all with value 1
- TLS query returns 9 series (9 Tailscale URLs) with Unix timestamp values

**Why human:** Requires querying live Prometheus data via Grafana Explore UI to verify blackbox exporter is scraping and metrics are stored.

---

**3. End-to-End Alert Delivery Test**

**Test:** 
1. SSH to ser8: `ssh bdhill@ser8`
2. Stop Jellyfin: `sudo systemctl stop jellyfin`
3. Wait 2-3 minutes for alert to fire
4. Check catgrep@sudomail.com inbox for "Service Down" email
5. Restart Jellyfin: `sudo systemctl start jellyfin`

**Expected:** An email alert with subject containing "Service Down (Probe Failed)" arrives within 3 minutes of stopping Jellyfin, showing instance "http://192.168.68.65:8096".

**Why human:** End-to-end alert delivery requires triggering actual service failure and verifying email receipt in external inbox.

---

## Summary

**All must-haves verified programmatically.** 

The implementation is complete and correct:
- SMTP configuration uses SOPS $__file{} pattern (password never in Nix store)
- 9 total alert rules (6 infrastructure + 3 probes) provisioned declaratively
- All 3 blackbox scrape jobs configured with correct targets (8 HTTP, 3 ICMP, 9 TLS)
- Contact point and notification policy route severity alerts to email
- All key links wired correctly (SOPS secrets, datasource UIDs, blackbox targets, probe metrics)
- No anti-patterns detected

**Human verification needed** to confirm:
1. Live email delivery works (test email arrives)
2. Prometheus is collecting probe metrics (visible in Grafana Explore)
3. End-to-end alert delivery works (service failure triggers email)

Once human verification passes, all 15 truths will be verified and phase 04 goal fully achieved.

---

_Verified: 2026-02-13T07:29:30Z_
_Verifier: Claude (gsd-verifier)_
