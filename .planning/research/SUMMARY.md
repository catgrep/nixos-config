# Project Research Summary

**Project:** Monitoring, Alerting & Log Aggregation for NixOS Homelab
**Domain:** Infrastructure observability
**Researched:** 2026-02-10
**Confidence:** HIGH

## Executive Summary

This project adds centralized logging, alert delivery, and comprehensive service monitoring to an existing Prometheus + Grafana metrics stack. The homelab already collects metrics from all hosts but has two critical gaps: (1) alert rules exist but nobody receives notifications, and (2) logs are scattered across hosts with no aggregation or search capability. The research confirms the Grafana stack (Loki + Alloy + Grafana Unified Alerting) is the right choice for NixOS homelabs, with strong module support and straightforward integration patterns.

The recommended approach uses Loki for log aggregation on firebat (the monitoring host), Grafana Alloy on all hosts for journal shipping (replacing deprecated Promtail), Blackbox Exporter for HTTP/ICMP probing, and Grafana Unified Alerting for notification delivery via email or webhooks. All components have mature NixOS modules and fit the existing declarative provisioning patterns. The stack integrates naturally with existing Prometheus metrics and Home Assistant automations.

The primary risk is impermanence-related data loss on ser8 (which uses ZFS rollback). Loki MUST run on firebat where state persists naturally, and Promtail/Alloy positions files MUST be added to ser8's persistence configuration. Secondary risks include schema version mismatches (Loki 3.x requires TSDB + v13), silent permission failures (journal access), and alert delivery confusion (Prometheus vs Grafana alerting). All critical pitfalls have known mitigations with strong documentation.

## Key Findings

### Recommended Stack

The research identified seven technology additions, all available in nixpkgs 25.05 with native NixOS modules. No unstable packages required. Core additions center on the Grafana ecosystem for natural integration with the existing Prometheus/Grafana setup.

**Core technologies:**

- **Grafana Loki 3.4.5** (log backend) — Native NixOS module with filesystem storage, TSDB indexing, 30-day retention matching Prometheus. Runs on firebat where state persists naturally.
- **Grafana Alloy 1.8.3** (log collector) — Replaces Promtail (EOL March 2026). NixOS module available, uses loki.source.journal for systemd scraping. Future-proof official replacement.
- **Blackbox Exporter 0.27.0** (HTTP/ICMP probes) — Native NixOS exporter module. Probes 12+ services for uptime, latency, cert expiry. Runs on firebat with Prometheus.
- **Grafana SMTP config** (email alerting) — Built into Grafana, uses services.grafana.settings.smtp with Gmail App Password via SOPS. No new service.
- **Grafana Unified Alerting** (alert rules + delivery) — Declarative provisioning via services.grafana.provision.alerting. Replaces need for standalone Alertmanager.
- **Home Assistant Prometheus integration** (HA metrics) — Built-in HA feature exposing /api/prometheus endpoint. Enables entity state tracking in Grafana.
- **Loki datasource provisioning** — Standard Grafana datasource config alongside existing Prometheus datasource.

**Version confidence:** All packages verified in nixpkgs 25.05. Loki and Alloy are 2-5 minor versions behind upstream but stable for homelab use (filesystem storage and journal scraping APIs unchanged).

### Expected Features

Research categorized features into table stakes (monitoring broken without them), differentiators (elevate setup quality), and anti-features (avoid complexity). MVP focuses heavily on table stakes since existing alert rules fire into the void.

**Must have (table stakes):**

- Alert delivery via email — Existing Prometheus rules are decorative without notification delivery
- Service HTTP probes — Need to know if Jellyfin/Sonarr/Radarr/etc respond, not just that processes run
- Disk space alerting per mount — Graduated severity for root, /mnt/media, /mnt/cameras
- ZFS health alerting — Scrub errors, capacity thresholds, ARC hit ratio monitoring
- Service crash/restart alerting — systemd-exporter already tracks, needs alert rules
- Uptime status dashboard — Single-pane green/red for every service
- Host down alerting with delivery — Existing rule needs notification path

**Should have (competitive):**

- Log aggregation across hosts — Searchable journald history, currently 1GB per-host with no central view
- Log-based error alerting — Catch OOM kills, ZFS errors, service crash patterns metrics miss
- HA entity tracking dashboard — Camera online/offline, MQTT status, automation success rates
- Grafana alerting provisioned as code — Declarative YAML avoids click-ops
- Network connectivity monitoring — ICMP probes, DNS resolution checks against pi4 AdGuard
- Certificate expiry monitoring — Tailscale + Caddy cert expiry tracking

**Defer (v2+):**

- SMART disk monitoring — Useful but hardware-specific, nixpkgs smartctl_exporter has quirks
- Standalone Alertmanager — Grafana Unified Alerting handles everything for homelab scale
- Uptime Kuma / status page — Redundant with Blackbox + Grafana dashboard
- Multi-tenant features — auth_enabled: false is correct for single-operator homelab

### Architecture Approach

The architecture centers on firebat as the monitoring hub (Prometheus, Grafana, Loki, Blackbox all co-located). Agents on each host (node-exporter, systemd-exporter, Alloy) push metrics and logs to firebat. This follows the existing pattern and avoids cross-host query dependencies.

**Major components:**

1. **Loki on firebat** — Log aggregation backend with TSDB index, filesystem chunks, compactor-based retention. Uses /var/lib/loki for state. Co-located with Grafana for localhost datasource queries.

2. **Alloy on all hosts (ser8, firebat, pi4)** — Scrapes local systemd journal via loki.source.journal, adds labels (host, unit, priority), pushes to Loki HTTP API. Stateless except positions file (must persist on ser8).

3. **Blackbox Exporter on firebat** — Runs HTTP, TCP, ICMP probe modules. Prometheus scrapes it using multi-target relabel pattern. Probes direct service ports (http://ser8.local:8096) not Caddy proxies to avoid self-signed cert issues.

4. **Grafana Unified Alerting on firebat** — Evaluates alert rules from Prometheus AND Loki datasources. Routes via notification policies to contact points (email via SMTP, webhook to HA). Replaces need for Prometheus Alertmanager.

5. **Home Assistant Prometheus integration on ser8** — Enables /api/prometheus endpoint via prometheus: in HA config. Prometheus scrapes with bearer token. Exposes entity states as metrics.

**Key patterns:**

- Push model for logs (Alloy pushes, Loki receives) — unlike Prometheus pull model
- Declarative provisioning for all Grafana resources (datasources, dashboards, alerting) — matches existing pattern
- Host label consistency (config.networking.hostName) — enables metric/log correlation
- SOPS for all credentials (SMTP password, HA token, etc.) — extends existing secrets pattern

### Critical Pitfalls

The research identified 17 pitfalls across critical, moderate, and minor severity. Top 5 have rewrites-or-data-loss consequences.

1. **Loki on wrong host (ser8 vs firebat) + impermanence** — ser8 uses ZFS rollback on boot. Deploying Loki there loses all log data on every reboot. Alloy positions file also needs persistence on ser8 (/var/lib/promtail or /var/lib/alloy). Deploy Loki on firebat, persist Alloy state on ser8.

2. **Loki 3.x schema mismatch** — nixpkgs 25.05 ships Loki 3.4.5 which requires TSDB index + v13 schema. Old examples use boltdb-shipper + v11/v12 and Loki refuses to start. Use schema: "v13", store: "tsdb", object_store: "filesystem" from day one.

3. **Grafana SMTP password in Nix store** — services.grafana.settings.smtp.password writes plaintext to world-readable /nix/store. Use $__file{${config.sops.secrets.grafana_smtp_password.path}} provider pattern (same as grafana_admin_password).

4. **Alloy cannot read journald without group membership** — Alloy user needs systemd-journal group or service fails silently (no errors, zero logs). Add users.users.alloy.extraGroups = [ "systemd-journal" ] on all hosts or use systemd.services.alloy.serviceConfig.SupplementaryGroups.

5. **Blackbox exporter relabeling pattern** — Multi-target exporter requires specific relabel_configs: copy __address__ to __param_target, copy to instance, replace __address__ with localhost:9115. Wrong config = scraping exporter instead of targets.

**Moderate pitfalls:** Loki retention requires compactor.retention_enabled (not automatic), Grafana file-provisioned alerts are UI-locked (plan workflow), HA Prometheus integration needs manual prometheus: in config, Prometheus vs Grafana alerting confusion (choose one notification path), Loki datasource not auto-provisioned.

**Minor pitfalls:** Gmail App Password format (16 chars, port 587, STARTTLS), Loki WAL silent data loss on disk full, blackbox TLS verification fails on Caddy local_certs, Alloy backlog after ser8 reboot if max_age too large.

## Implications for Roadmap

Research suggests a 4-phase approach based on dependencies, risk mitigation, and incremental value delivery. Each phase stands alone and delivers observable improvement.

### Phase 1: Alert Delivery + Core Probes

**Rationale:** Existing Prometheus rules fire silently. This is the highest-impact gap — monitoring exists but notifications don't work. Blackbox probes add service-level health checks (not just process checks). Both are foundational for later phases.

**Delivers:** Email notifications for existing alerts, HTTP/ICMP uptime monitoring for 12+ services, uptime dashboard

**Addresses features:**
- Alert delivery via email (table stakes)
- Service HTTP probes (table stakes)
- Uptime status dashboard (table stakes)
- Host down alerting with delivery (table stakes)

**Avoids pitfalls:**
- SMTP password in Nix store (use SOPS + $__file{})
- Gmail config mistakes (port 587, STARTTLS, App Password)
- Blackbox relabeling pattern (use exact multi-target config)
- Existing rules fire silently (connect to Grafana Alertmanager first)

**Stack elements:** Grafana SMTP, Blackbox Exporter, Grafana Unified Alerting

**Research flag:** NONE — well-documented patterns, existing codebase provides model

### Phase 2: Log Aggregation

**Rationale:** Depends on Phase 1 being stable (don't add log infrastructure until basic alerting works). Log aggregation is the second-biggest gap after alert delivery. Enables "what happened on ser8 at 3am" queries and log-based alerting.

**Delivers:** Centralized searchable logs from all 3 hosts, LogQL queries in Grafana Explore, 30-day log retention

**Addresses features:**
- Log aggregation (differentiator)
- Log-based error alerting (differentiator, enables OOM/crash pattern detection)

**Avoids pitfalls:**
- Loki on wrong host (deploy on firebat, NOT ser8)
- Loki 3.x schema (use TSDB + v13)
- Alloy journal permissions (systemd-journal group on all hosts)
- Alloy positions persistence (add /var/lib/alloy to ser8 impermanence)
- Loki retention not working (enable compactor from start)
- Loki datasource not auto-provisioned (add to grafana.nix)
- Network access (open port 3100 on firebat)
- Backlog after ser8 reboot (max_age: 12h + persist positions)

**Stack elements:** Loki, Alloy (all hosts), Loki datasource

**Research flag:** MEDIUM — Alloy config format (HCL-like) different from Promtail, verify NixOS module behavior. Consider starting with Promtail (EOL Feb 28, 2026 but simpler NixOS integration) and migrating to Alloy in Phase 4.

### Phase 3: Refined Alert Rules + Dashboards

**Rationale:** With alert delivery (Phase 1) and logs (Phase 2) working, refine and expand alerting. Migrate existing Prometheus rules to Grafana, add graduated severity, add log-based alerts, provision everything as code.

**Delivers:** Graduated alert severity (warning/critical), per-mount disk alerts, ZFS scrub error alerts, service restart alerts, log-based error alerts, provisioned alert rules as YAML

**Addresses features:**
- Disk space alerting per mount (table stakes)
- ZFS health alerting (table stakes)
- Service crash/restart alerting (table stakes)
- Grafana alerting provisioned as code (differentiator)

**Avoids pitfalls:**
- Grafana file-provisioned alerts UI-locked (start with UI rules, provision after stable)
- Prometheus vs Grafana alerting confusion (migrate Prometheus rules to Grafana)

**Stack elements:** Grafana alert provisioning, LogQL alert rules

**Research flag:** LOW — alert rule catalog provided in FEATURES.md, provisioning pattern documented

### Phase 4: Home Assistant Monitoring

**Rationale:** Independent of log aggregation, depends on alert delivery working. Complements Prometheus with HA-native monitoring. Enables camera/automation-specific alerts via mobile push.

**Delivers:** HA entity metrics in Prometheus/Grafana, entity tracking dashboard, HA infrastructure automations (camera offline → mobile push)

**Addresses features:**
- HA entity tracking dashboard (differentiator)
- Network connectivity monitoring (differentiator, via HA binary sensors)

**Avoids pitfalls:**
- HA Prometheus integration not enabled (add prometheus: to config)
- Auth token needed (Long-Lived Access Token via SOPS)

**Stack elements:** HA Prometheus integration, HA automations

**Research flag:** NONE — HA integration well-documented, existing HA config provides pattern

### Phase Ordering Rationale

- **Phase 1 first** because existing monitoring is broken without alert delivery. Immediate value.
- **Phase 2 before Phase 3** because log-based alerts (Phase 3) depend on Loki running (Phase 2).
- **Phase 4 independent** can happen anytime after Phase 1, but deferred to avoid too many changes at once.
- **Pitfall mitigation front-loaded:** All critical pitfalls addressed in Phase 1-2 (impermanence, schema, permissions, secrets).

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 2 (Log Aggregation):** Alloy vs Promtail decision (Promtail simpler but EOL March 2026, Alloy future-proof but newer). Verify NixOS Alloy module behavior and HCL config format. May start with Promtail and migrate.

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Grafana SMTP, Blackbox Exporter, alert provisioning all have strong NixOS module docs and existing codebase examples.
- **Phase 3:** Alert rule catalog provided by research (awesome-prometheus-alerts), provisioning follows Phase 1 pattern.
- **Phase 4:** HA Prometheus integration official and simple (one-line config), automation patterns already in codebase.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All packages verified in nixpkgs 25.05, NixOS modules exist for all components, versions stable |
| Features | HIGH | Clear table stakes vs differentiators, existing alert rules catalog (awesome-prometheus-alerts), codebase review confirms gaps |
| Architecture | HIGH | Extends existing Prometheus/Grafana pattern on firebat, component placement verified against impermanence config |
| Pitfalls | HIGH | 17 pitfalls identified with sources, all critical ones have documented mitigations, several confirmed from codebase analysis |

**Overall confidence:** HIGH

### Gaps to Address

**Alloy vs Promtail timing:** Promtail EOL is February 28, 2026 (18 days from research date). If Phase 2 timeline extends beyond that, start with Alloy directly. If Phase 2 starts immediately, Promtail is simpler and can be migrated later using `alloy convert --source-format=promtail`.

**firebat impermanence status:** Research found firebat imports impermanence modules but no impermanence.nix file. Needs verification during Phase 2: if firebat does NOT rollback root, Loki state persists naturally. If it does, add /var/lib/loki to persistence config.

**Blackbox TLS verification:** Caddy uses local_certs (self-signed). Blackbox probes should target direct HTTP ports (http://ser8.local:8096) not Caddy HTTPS proxies. For external accessibility checks, probe Tailscale URLs (*.shad-bangus.ts.net) which have real Let's Encrypt certs.

**Alert rule tuning window:** Grafana file-provisioned alert rules are UI-locked. Plan for iteration: start with UI-created rules during tuning phase, migrate to provisioned YAML once thresholds stable. Or accept rebuild cycle for changes.

**HA entity filtering:** HA Prometheus integration exposes all entities by default. May want to filter with include_domains to reduce metric cardinality. Test with full export first, refine if Prometheus performance issues appear.

## Sources

### Primary (HIGH confidence)

- NixOS Wiki: Grafana Loki — Module usage, configuration patterns
- NixOS Wiki: Grafana — Provisioning patterns including alerting
- NixOS Wiki: Prometheus — Exporter module patterns
- nixpkgs module sources (loki.nix, blackbox.nix, alloy.nix, promtail.nix) — Implementation details
- MyNixOS options reference (services.loki, services.alloy, services.grafana.provision.alerting.*) — Configuration options
- Grafana official docs (Loki, Alloy, Unified Alerting, file provisioning) — Architecture and features
- Home Assistant Prometheus integration docs — Configuration and endpoint spec
- Prometheus official docs (multi-target exporter guide, alerting) — Blackbox pattern, alert rules
- Awesome Prometheus Alerts (samber.github.io) — Alert rule catalog with expressions
- Loki 3.0 release notes, upgrade guide — Schema changes, TSDB requirements
- Loki retention documentation — Compactor configuration
- Loki WAL documentation — Silent data loss behavior
- Grafana community forums (SMTP setup, provisioning patterns) — Common configurations
- GitHub issues (Loki #7836, nixpkgs #2865) — Known bugs and workarounds
- Existing codebase (modules/gateway/prometheus.nix, grafana.nix, modules/automation/home-assistant.nix, hosts/ser8/impermanence.nix) — Current patterns and gaps

### Secondary (MEDIUM confidence)

- Promtail deprecation blog posts (techanek.com) — EOL timeline context
- Grafana blog: provisioning notification policies — API workarounds
- Prometheus Alertmanager vs Grafana Alerts analysis articles — Decision criteria
- nixpkgs issues (#293088) — Loki config validation discussions

### Tertiary (LOW confidence, reference only)

- Third-party NixOS observability examples (github.com/shinbunbun/nixos-observability) — Pattern validation
- Community Home Assistant blueprints — Automation ideas (not using blueprints, patterns only)

---
*Research completed: 2026-02-10*
*Ready for roadmap: yes*
