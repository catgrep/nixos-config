# NixOS Homelab - Architectural Analysis & Implementation Plans

**Analysis Date:** 2025-10-05
**Repository:** nixos-config
**Analyst:** devops-infra-architect agent via Claude Code

## Overview

This directory contains comprehensive architectural analysis and implementation plans for the NixOS homelab configuration. The analysis identified gaps between desired features (documented in CLAUDE.md and TODO.md) and actual implementation, providing detailed remediation plans.

## Documents

### 00-executive-summary.md
**High-level overview of findings and recommendations**

- Architecture health score: 6/10
- Top 5 critical issues identified
- What's working well
- Immediate action items
- Risk assessment and success metrics

**Read this first** for a quick understanding of the overall state.

---

### 01-storage-architecture.md
**Detailed analysis of storage configuration on ser8**

**Key Issues:**
- Backup ZFS pool (4x6TB RAID-Z2) defined but not mounted
- Media disks (2x12TB ext4) configuration analysis
- MergerFS and Samba share dependencies

**Includes:**
- Root cause analysis (disko vs runtime config)
- Diagnostic procedures (step-by-step commands)
- Multiple solution paths (import existing vs create new)
- Testing checklist and rollback plans
- Long-term improvements (monitoring, snapshots, backups)

**Status:** Media disks confirmed mounted by user; focus is on backup pool.

---

### 02-firebat-impermanence.md
**Migration plan for implementing ZFS impermanence on firebat**

**Goal:** Apply "Erase Your Darlings" pattern to gateway host

**Current State:**
- Simple ext4 filesystem
- Minimal impermanence (only SSH keys)
- Missing critical service persistence

**Plan Includes:**
- New ZFS-based disko configuration
- Enhanced impermanence configuration
- Three migration options (clean reinstall, live migration, deferred)
- Pre-migration checklist
- Step-by-step procedures
- Rollback plans and timeline estimates

**Recommendation:** Clean reinstall during maintenance window (1-2 hours downtime)

---

### 03-monitoring-secrets.md
**Gaps in monitoring and secrets management**

**Monitoring Issues:**
- Missing Grafana dashboards (exporters exist but unused)
- AdGuard Home monitoring not configured
- qBittorrent, Sonarr, Radarr, Prowlarr metrics missing
- VPN connection status not monitored

**Secrets Issues:**
- Missing API keys for media services
- Potential credential sharing between services
- Incomplete SOPS configuration

**Solutions:**
- Add Prometheus exporters for all services
- Create/import Grafana dashboards
- Generate and add missing API keys to SOPS
- Implement alerting rules

**Estimated Time:** 4-6 hours total

---

### 04-implementation-roadmap.md
**Prioritized action plan with step-by-step procedures**

**Priority 1 (Critical - Immediate):**
1. Investigate ser8 storage state
2. Import/create backup ZFS pool
3. Verify media disk mounts
4. Test Samba shares

**Priority 2 (High - This Week):**
1. Add media service secrets
2. Enhance monitoring
3. Add Grafana dashboards
4. Improve firebat impermanence (incremental)

**Priority 3 (Important - This Month):**
1. Plan firebat ZFS migration
2. Implement Prometheus alerting
3. Consider media storage architecture

**Priority 4 (Long-term):**
1. Backup automation
2. Complete Home Assistant module
3. Complete Gerrit module
4. Create VM test environment
5. Investigate overlay patterns

**Each item includes:**
- Specific commands to run
- Files to modify
- Testing procedures
- Time estimates
- Risk levels
- Rollback plans

---

### 05-overlay-pattern-analysis.md
**Research on Nix overlays pattern and recommendations**

**User request:** "Another thing to consider would be using `overlays` nix pattern"

**Analysis:**
- What overlays are and when to use them
- Current state: No overlays in repo
- Potential applications in homelab:
  - Fix AllDebrid local path issue
  - Hardware optimizations (Intel QuickSync)
  - Package version management
  - Custom package definitions

**Recommendations:**
1. **Immediate:** Fix AllDebrid flake input with overlay
2. **Short-term:** Add hardware optimizations for Jellyfin
3. **Long-term:** Consider version pins for consistency

**Includes:**
- Overlay structure examples
- Integration with flake
- Comparison with alternatives
- Implementation plan

---

### 06-media-storage-architecture.md
**Analysis of ext4+MergerFS vs ZFS for media storage**

**User questions:**
- "The media drives are mounted. These won't be replicated / backed up."
- "But maybe they should still be ZFS pools, I'm not sure."

**Analysis:**
- Current setup: 2x12TB ext4 with MergerFS (24TB usable)
- Alternative 1: ZFS mirror (12TB usable, 1-disk redundancy)
- Alternative 2: ZFS stripe (24TB usable, no redundancy)
- Alternative 3: Hybrid approach

**Workload Analysis:**
- Media files are replaceable (can re-download)
- Large sequential I/O (streaming and downloads)
- Already compressed (little benefit from ZFS compression)
- Read-heavy with occasional writes

**Recommendation:** **KEEP CURRENT SETUP**

**Reasoning:**
- Already optimized for the workload
- Full capacity utilization
- Simple and stable
- Media is replaceable

**Enhancements:**
- Add SMART monitoring
- Implement selective backups to ZFS backup pool
- Add disk health dashboard
- Document replacement procedures

---

## Quick Reference

### Most Critical Issues

1. **Backup pool not mounted** → `01-storage-architecture.md`, section 1.2
2. **Monitoring gaps** → `03-monitoring-secrets.md`
3. **firebat lacks impermanence** → `02-firebat-impermanence.md`

### Quick Wins (Low Effort, High Value)

1. **Add missing secrets** → `04-implementation-roadmap.md`, Priority 2.1
2. **Import backup pool** (if exists) → `01-storage-architecture.md`, section 1.2A
3. **Enhance firebat persistence** (without ZFS) → `04-implementation-roadmap.md`, Priority 2.4

### First Steps

Start here:
1. Read `00-executive-summary.md`
2. Run diagnostics from `01-storage-architecture.md`, section 1.1
3. Follow `04-implementation-roadmap.md` Priority 1

## Implementation Status

Track progress by updating this checklist:

### Priority 1 (Critical)
- [ ] Investigate ser8 storage state
- [ ] Import/create backup pool
- [ ] Verify media mounts
- [ ] Test Samba shares

### Priority 2 (High)
- [ ] Add media service secrets
- [ ] Configure missing exporters
- [ ] Add Grafana dashboards
- [ ] Enhance firebat impermanence

### Priority 3 (Important)
- [ ] Plan firebat ZFS migration
- [ ] Implement alerting
- [ ] Add SMART monitoring for media disks

### Priority 4 (Long-term)
- [ ] Create overlay infrastructure
- [ ] Implement backup automation
- [ ] Complete Home Assistant module
- [ ] Complete Gerrit module

## Getting Help

If you need clarification on any plan:

1. **Storage issues:** See `01-storage-architecture.md`
2. **Migration questions:** See `02-firebat-impermanence.md`
3. **Monitoring setup:** See `03-monitoring-secrets.md`
4. **What to do next:** See `04-implementation-roadmap.md`
5. **Overlays:** See `05-overlay-pattern-analysis.md`
6. **Media storage decision:** See `06-media-storage-architecture.md`

## Document Maintenance

These plans should be updated:
- ✅ After implementing solutions
- ✅ When discovering new issues
- ✅ When architecture changes
- ✅ During quarterly reviews

## Related Documentation

- `../CLAUDE.md` - Repository overview and architecture (recently updated)
- `../TODO.md` - Project roadmap and tasks (recently updated)
- `../README.md` - Quick start guide (recently updated)
- `../deploy.yaml` - Host configuration metadata

## Change Log

**2025-10-05:**
- Initial analysis completed by devops-infra-architect agent
- All 6 planning documents created
- Identified critical storage and monitoring gaps
- Created prioritized implementation roadmap
