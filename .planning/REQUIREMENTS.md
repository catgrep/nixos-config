# Requirements: NixOS Homelab Household Stack

**Defined:** 2026-08-16
**Core Value:** The homelab runs reliably without manual intervention -- when something needs attention, I know about it before it becomes a problem.

## v1.2 Requirements

Requirements for milestone v1.2. Each maps to roadmap phases.

### Foundation

- [x] **FOUND-01**: Flake runs on nixos-26.05; all four hosts build and dry-activate cleanly (25.11 is EOL)
- [x] **FOUND-02**: Decision recorded on replacing the nixos-raspberrypi pin with upstream Pi support (nixos-hardware for pi4, upstream nixpkgs for pi5), with a tested build for each Pi host
- [x] **FOUND-03**: `modules/household/` + `hosts/ser8/household/` scaffold follows the repo's two-layer module pattern
- [x] **FOUND-04**: PostgreSQL enabled on ser8 with an explicitly pinned package version before any service data exists

### Mealie

- [x] **MEAL-01**: Mealie runs on ser8 with a PostgreSQL backend via the native module (package overridden to a current release)
- [x] **MEAL-02**: Both household members have accounts in one shared household; default admin credentials changed; registration closed
- [x] **MEAL-03**: Mealie is reachable at `mealie.shad-bangus.ts.net` through the firebat Caddy Tailscale (tsnet) vhost with correct `BASE_URL`
- [x] **MEAL-04**: Foods and Units are seeded, and both users can see and edit the single shared shopping list
- [x] **MEAL-05**: Recipes, images, and uploads survive two consecutive reboots (impermanence check)

### Backups

- [ ] **BKP-01**: A nightly backup job on ser8 writes to a dedup-off dataset on the backup pool
- [ ] **BKP-02**: Mealie backup captures pg_dump plus the recipe image/upload directory
- [ ] **BKP-03**: SQLite-backed services are backed up via `sqlite3 .backup`/`VACUUM INTO` with `PRAGMA integrity_check`, never a raw copy
- [ ] **BKP-04**: Actual backup captures `account.sqlite` plus the entire `user-files/` blob tree
- [ ] **BKP-05**: A Mealie restore into a scratch instance is demonstrated and documented
- [ ] **BKP-06**: A restore of one SQLite service and of Actual is demonstrated

### TLS Trust

- [ ] **TLS-01**: TLS trust approach decided (Caddy root CA distribution vs public certs) and recorded in Key Decisions
- [ ] **TLS-02**: Household devices reach `.vofi` services over TLS with no browser warnings (required for Actual to function)

### Donetick

- [x] **DTK-01**: Donetick is packaged locally (Go backend + frontend) and builds via `nix build .#donetick`
- [x] **DTK-02**: Donetick runs on ser8 via a local NixOS module with persisted SQLite state and JWT secret from sops
- [x] **DTK-03**: Both household members have accounts in one circle; signup disabled afterward (two-stage deploy)
- [x] **DTK-04**: Donetick is reachable at its `<name>.vofi` hostname through Caddy with an AdGuard DNS entry

### Google Tasks Import

- [ ] **IMP-01**: Google Takeout export requested early (async, hours-to-days) and the real archive inspected before any import code is written
- [ ] **IMP-02**: One-off todos imported into Donetick via the internal `POST /api/v1/chores/` API with a dry-run mode and idempotency guard
- [ ] **IMP-03**: Recurring chores hand-authored in Donetick from a reviewed recurrence map (Takeout has no recurrence data)

### Homebox

- [x] **HBX-01**: Homebox (pinned 0.25.x) runs on ser8 with its static-user state dir explicitly persisted and owned
- [x] **HBX-02**: Both household members have accounts (second via invite); registration disabled afterward; analytics off
- [x] **HBX-03**: Homebox is reachable at its `<name>.vofi` hostname through Caddy with an AdGuard DNS entry

### Actual Budget

- [x] **ACT-01**: Actual Budget runs on ser8 via the 26.05 native module with its data dir persisted
- [x] **ACT-02**: Server password set, one budget file created, end-to-end encryption explicitly declined
- [x] **ACT-03**: Actual is reachable at its `<name>.vofi` hostname over trusted TLS through Caddy with an AdGuard DNS entry

### Access Control & Verification

- [ ] **SEC-01**: No household service is reachable from outside Tailscale/LAN, verified by a negative access smoketest
- [ ] **SEC-02**: No secret for any household service appears in the Nix store
- [ ] **OBS-01**: All four services have blackbox probes and household smoketests wired into deploy.yaml
- [ ] **OBS-02**: All four services retain their data across two consecutive ser8 reboots

## Future Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Home Assistant Integration

- **HAI-01**: Mealie HA integration (meal-plan calendar, shopping list to-do on phones) via API token
- **HAI-02**: Donetick HA to-do sync

### Monitoring & Alerting (v1.1 remainder, shelved)

- **HW-01..05**: Hardware alert rules (disk, ZFS, CPU, memory, temperature)
- **LOG-01..05**: Loki + Alloy log aggregation and log-based alerts
- **DASH-01..03**: Uptime dashboard, HA monitoring dashboards
- **HA-01..04**: HA infrastructure-alert automations

### Recipes

- **MEAL-F1**: Evaluate Tandoor Recipes if Mealie ingredient search proves inadequate -- before the catalog grows large

## Out of Scope

Explicitly excluded. Documented so we don't revisit.

| Feature | Reason |
|---------|--------|
| Grocy / pantry stock tracking | Evaluated and rejected; consumption logging drifts and gets abandoned |
| Sync or glue between the four services | Standalone by design; no integration layer |
| Second shopping list app | Mealie's list is the only list |
| Barcode scanning, expiry tracking, stock levels | Perpetual-inventory anti-features |
| Recipe-to-inventory decrement, meal-plan-to-calendar sync | Same |
| Homebox maintenance schedules | Would compete with Donetick as a second chore system |
| Homebox CSV bulk import of belongings | Grocy failure mode with a different noun |
| Actual end-to-end encryption | Makes server-side backups opaque ciphertext; conflicts with restore requirement |
| SimpleFIN bank sync provisioned in Nix | Configured in-app only, per upstream design |
| Mealie AI/OpenAI import features | Not asked for |
| Public exposure / port forwarding / inbound ACME | Tailscale/LAN only |
| Automated recurrence inference in the Google Tasks import | Takeout has no recurrence data; inference produces silently wrong schedules |

## Traceability

Which phases cover which requirements. Filled by roadmap.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 9 | Complete |
| FOUND-02 | Phase 9 | Complete |
| FOUND-03 | Phase 10 | Complete |
| FOUND-04 | Phase 10 | Complete |
| MEAL-01 | Phase 10 | Complete |
| MEAL-02 | Phase 10 | Complete |
| MEAL-03 | Phase 10 | Complete |
| MEAL-04 | Phase 10 | Complete |
| MEAL-05 | Phase 10 | Complete (formal reboot drill waived) |
| IMP-01 | Deferred | Deferred (descoped 2026-08-20) |
| BKP-01 | Deferred | Deferred (descoped 2026-08-20) |
| BKP-02 | Deferred | Deferred (descoped 2026-08-20) |
| BKP-03 | Deferred | Deferred (descoped 2026-08-20) |
| BKP-05 | Deferred | Deferred (descoped 2026-08-20) |
| TLS-01 | Deferred | Deferred (descoped 2026-08-20) |
| TLS-02 | Deferred | Deferred (descoped 2026-08-20) |
| HBX-01 | Phase 11 | Complete |
| HBX-02 | Phase 11 | Complete |
| HBX-03 | Phase 11 | Complete |
| ACT-01 | Phase 11 | Complete |
| ACT-02 | Phase 11 | Complete |
| ACT-03 | Phase 11 | Complete |
| BKP-04 | Deferred | Deferred (descoped 2026-08-20) |
| BKP-06 | Deferred | Deferred (descoped 2026-08-20) |
| DTK-01 | Phase 11 | Complete |
| DTK-02 | Phase 11 | Complete |
| DTK-03 | Phase 11 | Complete |
| DTK-04 | Phase 11 | Complete |
| IMP-02 | Deferred | Deferred (descoped 2026-08-20) |
| IMP-03 | Deferred | Deferred (descoped 2026-08-20) |
| SEC-01 | Deferred | Deferred (descoped 2026-08-20) |
| SEC-02 | Deferred | Deferred (descoped 2026-08-20) |
| OBS-01 | Deferred | Deferred (descoped 2026-08-20) |
| OBS-02 | Deferred | Deferred (descoped 2026-08-20) |

**Coverage:** 19/34 original requirements active (9 complete, 10 in Phase 11); 15 deferred by the 2026-08-20 descope (backups, TLS, Tasks import, access-control gate).

---
*Requirements defined: 2026-08-16*
*Last updated: 2026-08-20 after descope to a single app-spin-up phase*
