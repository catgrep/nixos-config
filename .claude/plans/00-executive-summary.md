# Architectural Analysis - Executive Summary

**Date:** 2025-10-05
**Analysis Type:** Comprehensive Infrastructure Gap Analysis
**Overall Health Score:** 6/10

## Status Overview

The NixOS homelab configuration validates successfully (`make check` passes) but has **critical gaps between declared infrastructure and actual implementation**. The primary issues center around storage initialization and impermanence patterns.

## Top 5 Critical Issues

### 1. 🔴 CRITICAL: Backup ZFS Pool Not Mounted
- **Severity:** Critical
- **Impact:** 4x6TB (RAID-Z2) = ~12TB usable storage unavailable
- **Location:** `hosts/ser8/disko-config.nix:236-265`
- **Status:** Defined but never imported/activated
- **Risk:** Data loss if configuration expects this storage

### 2. 🔴 CRITICAL: Media Disks Not Mounted
- **Severity:** Critical
- **Impact:** 2x12TB = ~24TB ext4 storage unavailable
- **Location:** `hosts/ser8/disko-config.nix:113-160`
- **Status:** Defined but filesystems never created/mounted
- **Risk:** MergerFS and Samba services are broken

### 3. 🔴 CRITICAL: Samba Shares Point to Non-Existent Paths
- **Severity:** Critical
- **Impact:** SMB shares completely non-functional
- **Location:** `hosts/ser8/samba.nix:66-94`
- **Paths:** `/mnt/backups` (doesn't exist), `/mnt/media` (doesn't exist)
- **Risk:** Service fails or returns empty shares

### 4. 🟡 HIGH: firebat Missing ZFS Impermanence
- **Severity:** High
- **Impact:** Gateway/monitoring host lacks "Erase Your Darlings" pattern
- **Location:** `hosts/firebat/disko-config.nix` (ext4 only)
- **Status:** Documented as desired but not implemented
- **Risk:** Configuration drift, harder to maintain consistency

### 5. 🟡 HIGH: MergerFS Depends on Non-Existent Mounts
- **Severity:** High
- **Impact:** Unified media view is broken
- **Location:** `hosts/ser8/configuration.nix:106-119`
- **Dependencies:** `/mnt/disk1`, `/mnt/disk2` (don't exist)
- **Risk:** Service fails to start or mount

## What's Working Well

✅ **rpool (ser8):** ZFS impermanence pattern correctly implemented
✅ **Configuration Validation:** All NixOS configurations build successfully
✅ **Module Structure:** Clean separation of concerns
✅ **NordVPN Integration:** qBittorrent properly isolated in network namespace
✅ **Service Definitions:** Media stack, monitoring, and gateway services well-configured
✅ **Secrets Management:** SOPS properly configured for existing secrets
✅ **Automation:** Comprehensive Makefile and scripts for deployment

## Key Findings Summary

### Storage Architecture
- **Root Cause:** Disko configurations are declarative install-time specifications
- **Gap:** Post-installation, ZFS pools need explicit import configuration
- **Impact:** ~36TB of defined storage is completely unusable

### Impermanence Pattern
- **ser8:** ✅ Correctly implements "Erase Your Darlings"
- **firebat:** ❌ Still using traditional ext4 with minimal persistence
- **Gap:** Inconsistent infrastructure patterns across hosts

### Monitoring & Observability
- **Prometheus:** Running but has gaps (AdGuard, ZFS pools, VPN status)
- **Grafana:** Configured but dashboard directory appears empty
- **Exporters:** Present but underutilized

### Secrets & Security
- **SOPS:** Properly configured for core services
- **Missing:** API keys for Sonarr, Radarr, qBittorrent, Prowlarr
- **Concern:** Possible credential sharing between services

## Immediate Action Required

### Priority 1 (Today/This Week)
1. **Investigate ser8 storage state** - SSH in and run diagnostics
2. **Import or create backup ZFS pool** - Recover 12TB storage
3. **Format and mount media disks** - Recover 24TB storage
4. **Fix Samba and MergerFS** - Make shares functional

### Priority 2 (This Month)
1. **Plan firebat migration to ZFS** - Design migration strategy
2. **Add missing service secrets** - Complete SOPS configuration
3. **Create Grafana dashboards** - Utilize existing Prometheus metrics

### Priority 3 (Long-term)
1. **Implement backup automation** - ZFS snapshot replication
2. **Add VPN monitoring** - Ensure qBittorrent isolation is maintained
3. **Create VM test environment** - Safe testing before production changes

## Risk Assessment

**Configuration Drift Risk:** 🟡 Medium
- Documented architecture doesn't match reality
- Recent documentation update improved this

**Data Loss Risk:** 🔴 High
- If backup pool was created but isn't imported, data may be inaccessible
- If media disks have data but aren't mounted, same issue

**Service Availability Risk:** 🔴 High
- Samba shares are broken (pointing to non-existent paths)
- MergerFS can't provide unified media view

**Deployment Risk:** 🟢 Low
- `make check` validates successfully
- Configurations build without errors
- Issue is runtime state, not configuration validity

## Recommendations

### Technical Debt
1. Complete storage initialization across all defined disks
2. Standardize impermanence pattern (ZFS) across all hosts
3. Fill monitoring gaps (dashboards, missing exporters)
4. Complete secrets configuration for all services

### Process Improvements
1. Add automated verification of storage mounts after deployment
2. Create smoketests for all critical services (media, storage, monitoring)
3. Document manual initialization steps required post-install
4. Consider Infrastructure-as-Code testing (NixOS VM tests)

### Documentation
1. ✅ Already updated: CLAUDE.md, README.md, TODO.md reflect current state
2. 📝 Add: Storage initialization procedures
3. 📝 Add: Migration guides for impermanence implementation
4. 📝 Add: Troubleshooting runbook

## Success Metrics

After implementing fixes:
- [ ] All defined storage pools are mounted and accessible
- [ ] Samba shares serve correct paths with data
- [ ] MergerFS provides unified view of media storage
- [ ] firebat implements ZFS impermanence pattern
- [ ] All services have required secrets configured
- [ ] Grafana has dashboards for key metrics
- [ ] Smoketests pass for all critical services

## Next Steps

See detailed plans in this directory:
- `01-storage-architecture.md` - Detailed storage analysis and fixes
- `02-firebat-impermanence.md` - Migration plan for gateway host
- `03-monitoring-secrets.md` - Observability and security gaps
- `04-implementation-roadmap.md` - Prioritized action items with procedures
