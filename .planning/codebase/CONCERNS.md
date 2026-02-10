# Codebase Concerns

**Analysis Date:** 2026-02-09

## Tech Debt

**AllDebrid-Proxy Integration:**
- Issue: API integration is completely disabled and non-functional
- Files: `hosts/ser8/media.nix:646-653`
- Impact: Cannot use AllDebrid streaming/download acceleration; feature is partially documented but broken
- Fix approach: Re-enable and test AllDebrid-rs API integration, or remove incomplete code if not planned

**SOPS User Key Management:**
- Issue: User SSH key integration commented out; fallback to GPG-only approach
- Files: `scripts/sops/add-user.sh:8-21` and `scripts/sops/status.sh:6-8`
- Impact: Reduced flexibility for multi-user secret management; relies entirely on single GPG key
- Fix approach: Debug and re-enable SSH-to-age key conversion, or document why GPG-only is preferred

**Tmux Status Bar Hardcoding:**
- Issue: Status bar background color not host-variable driven
- Files: `modules/common/tmux.nix:3`
- Impact: Cannot differentiate hosts visually in tmux across cluster
- Fix approach: Add host-based status-bg configuration option

**Incomplete Gerrit Development Module:**
- Issue: Gerrit module exists but is planned/incomplete
- Files: `modules/development/gerrit.nix` (178 lines)
- Impact: CI/CD pipeline not available; development workflow still manual
- Fix approach: Complete Gerrit implementation or remove placeholder module

## Known Bugs

**SABnzbd Integration Cascade Failure:**
- Symptoms: SABnzbd service fails to start properly; Prowlarr cannot connect; entire media stack setup fails
- Files: `hosts/ser8/media.nix:484-735` (detailed analysis in `.claude/analysis/2025-10-11_sabnzbd-systemd-failures.md`)
- Root causes:
  1. Service dependency missing - `sabnzbd.service` doesn't depend on `sabnzbd-config.service`
  2. Configuration subdirectories not created - `logs`, `admin`, `backup` directories expected but missing
  3. Configuration uses relative paths instead of absolute paths
  4. API wait timeout too short (30 iterations = 60s, needs 60 iterations = 120s)
  5. No health check before Prowlarr integration attempts connection
- Workaround: Manual systemd restart or longer wait times
- Fix: Add explicit dependencies, create subdirectories, use absolute paths, increase timeouts

**Caddy DEBUG Logging on All Tailscale Routes:**
- Symptoms: Excessive Caddy logging overhead on production Tailscale routes
- Files: `modules/gateway/Caddyfile:98-99, 106-107, 114-115, 122-123, 130-131, 139-140, 147-148, 156-157, 166-168`
- Impact: Performance degradation, log disk usage growth, security information disclosure
- Fix approach: Change `level DEBUG` to `level INFO` or remove debug logging blocks entirely

**Frigate CVE With Known Security Vulnerability:**
- Symptoms: Using insecure package version with known vulnerability
- Files: `modules/automation/frigate.nix:16-21`
- Vulnerability: Frigate 0.15.2 has CVE (GHSA-vg28-83rp-8xx4)
- Mitigation: Application is behind Tailscale and firewall; only accessible to authorized users
- Risk: Currently acceptable due to network isolation, but needs upgrade path
- Fix approach: Track upstream Frigate releases and upgrade when stable patched version available

## Security Considerations

**Hardcoded Static IP Addresses Throughout Config:**
- Risk: Network changes require manual updates across multiple files
- Files: `modules/gateway/Caddyfile:89-94, 102-175` (reverse_proxy static IPs), `modules/automation/frigate.nix:170+` (camera IPs), `modules/dns/adguard-home.nix:112-132` (DNS response IPs)
- Current state: IPs documented in comments but hardcoded in multiple places
- Recommendations: Parameterize IP addresses in deploy.yaml or create shared variable definitions

**API Keys Exposed in Systemd Setup Scripts:**
- Risk: API keys passed as command-line arguments visible in `ps` output and systemd logs
- Files: `hosts/ser8/media.nix:550-627` (Prowlarr setup), `hosts/ser8/media.nix:596-607` (download client setup)
- Current mitigation: API sanitization in systemd logs prevents exposure
- Recommendations: Use `LoadCredential` pattern (like jellyfin-exporter) for all setup scripts, not just exporters

**SOPS Secrets File Management:**
- Risk: `.sops.yaml` configuration file checked into git; if private keys leaked, secrets are compromised
- Files: `.sops.yaml` (public), `secrets/` directory (encrypted)
- Current state: Public keys are in config, private keys on host machines only
- Recommendations: Verify no private keys in `.sops.yaml`; ensure all secrets files encrypted before commit

**Jellyfin Password Hashing Dependency:**
- Risk: Jellyfin password hashing requires external script `scripts/sops/genhash.py`
- Files: `modules/media/jellyfin.nix:75-76` (hashedPasswordFile dependency)
- Impact: Password changes require manual hash generation via script
- Recommendations: Document the password hashing requirement; consider systemd-based password injection

**Media Service Secrets Sharing Pattern:**
- Risk: Multiple services (Sonarr, Radarr, etc.) can access each other's API keys through SOPS
- Files: `hosts/ser8/media.nix:18-106` (secrets declarations are permissive)
- Impact: One compromised service could be lateral-moved using other services' credentials
- Recommendations: Implement service-level isolation; restrict secret visibility per service

## Performance Bottlenecks

**Large Configuration File - ser8/media.nix:**
- Problem: Monolithic 654-line file containing all media service configuration, setup scripts, and systemd units
- Files: `hosts/ser8/media.nix` (654 lines)
- Impact: Difficult to modify without understanding entire setup flow; high cognitive load
- Improvement path: Split into separate modules (`media-config.nix`, `media-setup.nix`, `exporters.nix`)

**Synchronous Setup Dependencies Chain:**
- Problem: Three sequential systemd setup services run serially: `media-config → servarrs-setup → download-clients-setup`
- Files: `hosts/ser8/media.nix:469-644`
- Impact: Full media stack initialization takes 3-5 minutes minimum; blocks system readiness
- Improvement path: Parallelize independent setup tasks; reduce polling waits with event-driven initialization

**Prometheus Retention at 30 Days:**
- Problem: Retention time configured to 30 days with 10GB size limit
- Files: `modules/gateway/prometheus.nix:135-139`
- Impact: Insufficient retention for ZFS anomaly detection; metrics will be pruned
- Improvement path: Increase retention based on available storage, or implement remote storage

**Network Name Resolution Fallback to Static IPs:**
- Problem: mDNS resolution fails from Tailscale-bound Caddy instances; requires hardcoded static IPs in Caddyfile
- Files: `modules/gateway/Caddyfile:74-94` (detailed explanation of issue)
- Impact: Caddy Tailscale routes use static IPs instead of mDNS; fragile to network changes
- Improvement path: Use split DNS (local names for mDNS, static IPs as fallback); implement Caddy DNS module for dynamic discovery

## Fragile Areas

**Media Stack Setup Service Chain:**
- Files: `hosts/ser8/media.nix:469-644`
- Why fragile:
  - Circular dependencies: setup services wait for other services that haven't started
  - API polling with hardcoded timeouts: if service is slow, setup fails permanently
  - Bash script complexity: 150+ lines of shell with API polling, JSON parsing, error handling
  - Manual retry required on failure: systemd RemainAfterExit prevents auto-retry
- Safe modification:
  1. Always test setup scripts locally first (`bash scripts/smoketests/media/test-integration.sh`)
  2. Increase wait timeouts before reducing them
  3. Add explicit health checks before integration attempts
  4. Log all API requests/responses for debugging
- Test coverage gaps: No automated test for full media stack initialization flow

**Frigate Camera Configuration:**
- Files: `modules/automation/frigate.nix:170-343`
- Why fragile:
  - Hardcoded camera IP addresses (6 cameras with static IPs)
  - RTSP credentials injected via environment variable substitution
  - Two cameras (TP-Link models) require TCP transport workaround for WiFi stability
  - No health checks for camera connectivity
- Safe modification:
  1. Test RTSP connectivity before modifying streams
  2. Camera resets may require manual credential updates in SOPS
  3. Keep TP-Link TCP transport settings; WiFi instability has been debugged
- Test coverage gaps: No automated camera health check or stream availability test

**NordVPN Network Namespace Isolation:**
- Files: `modules/nordvpn/service.nix` (324 lines), `hosts/ser8/configuration.nix:151-175`
- Why fragile:
  - Complex systemd service with veth interface creation
  - qBittorrent confined to network namespace; cannot access local resources
  - Manual routing table management for namespace
  - NordVPN key renewal could interrupt isolation
- Safe modification:
  1. Test netns connectivity before changes
  2. Verify qBittorrent can still reach download directories
  3. Check Prowlarr can still reach qBittorrent on localhost:8080
- Test coverage: Dedicated smoketests exist but integration with media services untested

**Impermanence Configuration for Entire Filesystem:**
- Files: `hosts/ser8/impermanence.nix:1-181`
- Why fragile:
  - Root filesystem rolls back on boot; any changes lost
  - Service data depends on correct persistence rules
  - Missing persistence rule = data loss on reboot
  - Easy to add service without adding persistence directory
- Safe modification:
  1. Before adding new service, add its state directory to persistence rules
  2. Test service after reboot to verify state persistence
  3. Document which directories are critical for service function
- Test coverage gaps: No automated test for impermanence; manual reboot verification only

## Scaling Limits

**Camera Storage - /mnt/cameras:**
- Current capacity: Alert triggered at 20% available
- Limit: Single ZFS backup pool; no tiered storage or archiving
- Scaling path: Implement video retention policy (30/7/1 day for high/medium/low priority); migrate old footage to cold storage

**Prometheus Time-Series Database:**
- Current capacity: 30-day retention, 10GB size limit
- Limit: Will drop metrics when retention period expires or size limit hit
- Scaling path: Implement long-term storage (Thanos, Cortex, or remote write); increase retention based on available storage

**Media Library - /mnt/media:**
- Current architecture: Single MergerFS mount across multiple ZFS pools
- Limit: MergerFS has no sharding; single controller bottleneck
- Scaling path: Implement distributed media storage (NFS, S3) or split into dedicated mount points

**Caddy Reverse Proxy - Single Instance:**
- Current state: Firebat is single reverse proxy for all services
- Limit: No redundancy; single point of failure for all service access
- Scaling path: Implement Caddy clustering or separate load balancer

## Dependencies at Risk

**Frigate Package Using Insecure Version:**
- Risk: Known security vulnerability (CVE-vg28-83rp-8xx4) in 0.15.2
- Impact: If exposed to untrusted network, vulnerability could be exploited
- Current mitigation: Tailscale + firewall isolation
- Migration plan: Monitor Frigate releases; upgrade to patched version (0.16+) when stable

**AllUnfree Packages Globally Enabled:**
- Risk: All unfree packages allowed (media codecs, drivers, etc.)
- Impact: Some packages may have licensing/support concerns
- Current state: Necessary for media transcoding, AMD VA-API drivers
- Recommendation: Document specific unfree packages needed; consider enabling only required packages

## Missing Critical Features

**No Backup Strategy for ZFS Snapshots:**
- Problem: ZFS snapshots configured but no remote backup
- Files: CLAUDE.md references snapshots but no backup automation
- Blocks: Data loss risk if hardware fails; no disaster recovery
- Implementation path: Add ZFS send/receive to remote storage or cloud backup

**No Monitoring for NordVPN Connection Status:**
- Problem: qBittorrent isolated in VPN namespace; no alerting if VPN drops
- Files: No exporter for NordVPN connectivity
- Blocks: qBittorrent could leak traffic if VPN fails without alert
- Implementation path: Add systemd service to monitor netns default route

**No Gerrit Code Review System:**
- Problem: Module exists but incomplete; no CI/CD pipeline
- Files: `modules/development/gerrit.nix`
- Blocks: Cannot enforce code review for configuration changes
- Implementation path: Complete Gerrit implementation with integrated CI

**No Grafana Dashboards for ZFS Metrics:**
- Problem: ZFS exporter running but dashboards not provisioned
- Files: `modules/gateway/prometheus.nix` (exporter configured), but no matching dashboard
- Blocks: Cannot visualize ZFS pool health without manual queries
- Implementation path: Add ZFS dashboard from grafana.com/dashboards

## Test Coverage Gaps

**Media Stack Integration:**
- What's not tested: Full initialization flow (media-config → servarrs-setup → download-clients-setup)
- Files: `hosts/ser8/media.nix:469-644`
- Risk: Configuration changes could break entire stack; only discovered on deployment
- Priority: High - this is most fragile area

**Impermanence Persistence:**
- What's not tested: Automated verification that all service data persists across reboot
- Files: `hosts/ser8/impermanence.nix`
- Risk: Missing persistence rule = silent data loss; discovered only when service fails
- Priority: High - data loss is critical

**Frigate Camera Connectivity:**
- What's not tested: Automated health check for all 6 cameras
- Files: `modules/automation/frigate.nix:170-343`
- Risk: Broken RTSP feed goes unnoticed; NVR appears running but capturing no footage
- Priority: High - security camera failure undetected

**NordVPN Isolation:**
- What's not tested: Automated verification that qBittorrent traffic stays in namespace
- Files: `modules/nordvpn/service.nix`
- Risk: VPN isolation could silently fail; traffic leaks to clearnet undetected
- Priority: Medium - privacy impact

**Caddy Reverse Proxy:**
- What's not tested: Automated verification that all service routes functional
- Files: `modules/gateway/Caddyfile`, `modules/gateway/caddy.nix`
- Risk: Service endpoint changes could break reverse proxy routing; not discovered until manual test
- Priority: Medium - affects service availability

---

*Concerns audit: 2026-02-09*
