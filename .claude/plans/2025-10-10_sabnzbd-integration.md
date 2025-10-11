# SABnzbd Integration: Implementation Plan

## Overview

This plan implements SABnzbd Usenet download client integration into the existing NixOS homelab media stack on the ser8 host. The implementation follows established patterns from radarr, sonarr, and qbittorrent modules with SOPS-based secrets management and systemd orchestration.

**Target Host:** ser8 (192.168.68.65)
**Total Estimated Time:** 6-8 hours
**Prerequisites:** Usenet provider credentials, working SOPS configuration

---

## Phase 1: Base Module Creation

**Objective:** Create the foundational SABnzbd NixOS module following established patterns

**Prerequisites:** None

**Implementation Steps:**

1. **Create module file** at `modules/media/sabnzbd.nix`
   - Follow pattern from `modules/media/radarr.nix:1-31` (basic structure)
   - Follow pattern from `modules/media/sonarr.nix:1-31` (alternative reference)
   - License header: Use GPL-3.0-or-later as in `modules/media/radarr.nix:1`

2. **Define user/group creation**
   - Pattern: `modules/media/radarr.nix:12-20`
   - Create `users.users.sabnzbd` with `isSystemUser = true`
   - Set `group = "sabnzbd"`
   - Add `extraGroups = [ "media" ]` for shared media access
   - Set `home = "/var/lib/sabnzbd"`
   - Create `users.groups.sabnzbd` empty group
   - Ensure `users.groups.media = { }` exists

3. **Configure base service**
   - Pattern: `modules/media/radarr.nix:22-26`
   - Enable `services.sabnzbd.enable = lib.mkDefault false`
   - Set `user = "sabnzbd"` and `group = "sabnzbd"`
   - Note: Check upstream nixpkgs module for available options

4. **Add firewall rule**
   - Pattern: `modules/media/radarr.nix:29`
   - Open TCP port 8080: `networking.firewall.allowedTCPPorts = lib.mkIf config.services.sabnzbd.enable [ 8080 ]`

5. **Register module in flake**
   - Add to `modules/media/default.nix` imports (if exists) OR
   - Verify `flake.nix` already imports `./modules/media` as directory

**Validation:**

```bash
# Check module syntax
make check

# Verify no evaluation errors
nix flake show

# Test module loads (won't activate yet)
make build-ser8
```

**Rollback:**
- Delete `modules/media/sabnzbd.nix`
- Run `make check` to verify clean state

**Time Estimate:** 30-60 minutes

---

## Phase 2: Storage Configuration

**Objective:** Configure persistent directory structure for SABnzbd downloads

**Prerequisites:** Phase 1 complete

**Implementation Steps:**

1. **Add directory structure to impermanence config**
   - File: `hosts/ser8/impermanence.nix`
   - Location: Add after line 122 (after AllDebrid section)
   - Pattern: `hosts/ser8/impermanence.nix:105-122` (media directory structure)

2. **Add SABnzbd tmpfiles rules** (insert after line 122):
   ```nix
   # SABnzbd Usenet downloads
   "d /mnt/media/downloads/usenet 0775 sabnzbd media -"
   "d /mnt/media/downloads/usenet/incomplete 0775 sabnzbd media -"
   "d /mnt/media/downloads/usenet/complete 0775 sabnzbd media -"
   "d /mnt/media/downloads/usenet/complete/tv 0775 sabnzbd media -"
   "d /mnt/media/downloads/usenet/complete/movies 0775 sabnzbd media -"
   "d /mnt/media/downloads/usenet/complete/default 0775 sabnzbd media -"
   ```

3. **Add SABnzbd state directory** (after line 56, in persistence directories):
   ```nix
   "/var/lib/sabnzbd"
   ```

4. **Add service permissions** (after line 134):
   ```nix
   "d /persist/var/lib/sabnzbd 0755 sabnzbd sabnzbd -"
   ```

**Validation:**

```bash
# Build configuration
make build-ser8

# After deployment, check directories exist
make ssh-ser8
ls -la /mnt/media/downloads/
ls -la /mnt/media/downloads/usenet/

# Verify ownership
ls -la /mnt/media/downloads/usenet/
# Should show: drwxrwxr-x sabnzbd media

# Check persistence
ls -la /persist/var/lib/sabnzbd
```

**Rollback:**
- Remove added lines from `hosts/ser8/impermanence.nix`
- Run `make build-ser8` to regenerate without directories

**Time Estimate:** 30 minutes

---

## Phase 3: Secrets Management

**Objective:** Configure SOPS-encrypted secrets for SABnzbd authentication and Usenet provider

**Prerequisites:** Phase 2 complete, Usenet provider credentials obtained

**Implementation Steps:**

1. **Generate API keys locally**
   ```bash
   # Generate SABnzbd API key (32 character hex)
   openssl rand -hex 16

   # Generate NZB key (32 character hex)
   openssl rand -hex 16
   ```

2. **Edit encrypted secrets file**
   ```bash
   make sops-edit-ser8
   ```

   Add the following keys (pattern from `hosts/ser8/media.nix:18-103`):
   ```yaml
   sabnzbd_api_key: "<generated-api-key>"
   sabnzbd_nzb_key: "<generated-nzb-key>"
   sabnzbd_admin_password: "<strong-password>"
   sabnzbd_usenet_server: "news.yourprovider.com"
   sabnzbd_usenet_username: "<username>"
   sabnzbd_usenet_password: "<password>"
   sabnzbd_usenet_port: "563"
   sabnzbd_usenet_connections: "20"
   ```

3. **Add SOPS secret declarations** to `hosts/ser8/media.nix`
   - Location: After line 103 (after prowlarr secrets)
   - Pattern: `hosts/ser8/media.nix:38-90`

   Add secret declarations for all 8 SABnzbd secrets with `owner = "root"`, `group = "root"`, `mode = "0600"`

4. **Create SOPS template for sabnzbd.ini**
   - Location: After line 230 in `hosts/ser8/media.nix` (after qbittorrent template)
   - Pattern: `hosts/ser8/media.nix:182-229` (qbittorrent.conf template)
   - Include sections: `[misc]`, `[servers]`, `[categories]`
   - Set paths to `/mnt/media/downloads/usenet/complete/{tv,movies,default}`
   - Owner: `sabnzbd:sabnzbd`, mode: `0600`

**Validation:**

```bash
# Check secrets syntax
make check

# Build to test template rendering
make build-ser8

# After deployment, verify template rendered
make ssh-ser8
ls -la /run/secrets-rendered/sabnzbd.ini
# Should exist with 0600 sabnzbd:sabnzbd

# Verify secrets can be decrypted
cat /run/secrets/sabnzbd_api_key
```

**Rollback:**
- Remove secret declarations from `hosts/ser8/media.nix`
- Remove template from `sops.templates`
- Optionally remove secrets from `secrets/ser8.yaml` using `make sops-edit-ser8`

**Time Estimate:** 45-60 minutes

---

## Phase 4: Service Orchestration

**Objective:** Create systemd service to deploy SABnzbd configuration and verify readiness

**Prerequisites:** Phase 3 complete

**Implementation Steps:**

1. **Create SABnzbd config deployment service**
   - File: `hosts/ser8/media.nix`
   - Location: After line 304 (after qbittorrent-config service)
   - Pattern: `hosts/ser8/media.nix:269-304` (qbittorrent-config service)
   - Service name: `sabnzbd-config`
   - Deploy template to `/var/lib/sabnzbd/sabnzbd.ini`
   - Set ownership: `sabnzbd:sabnzbd`, mode: `600`

2. **Create SABnzbd setup verification service**
   - Location: After previous service (around line 347)
   - Pattern: `hosts/ser8/media.nix:306-347` (arr-qbittorrent-setup)
   - Service name: `arr-sabnzbd-setup`
   - Use `systemd_helpers.sh` for API polling
   - Verify API responds: `http://localhost:8080/sabnzbd/api?mode=version`
   - Verify categories exist: `http://localhost:8080/sabnzbd/api?mode=get_cats`

3. **Update media-services-setup target**
   - Location: `hosts/ser8/media.nix:403-416`
   - Add `arr-sabnzbd-setup.service` to both `wants` and `after` lists

**Validation:**

```bash
# Build and test
make build-ser8
make test-ser8

# After activation, check services
make ssh-ser8
systemctl status sabnzbd.service
systemctl status sabnzbd-config.service
systemctl status arr-sabnzbd-setup.service

# Check logs
journalctl -u sabnzbd.service -n 50
journalctl -u arr-sabnzbd-setup.service -n 50

# Test API access
curl "http://localhost:8080/sabnzbd/api?mode=version&apikey=<your-api-key>"
```

**Rollback:**
- Remove added services from `hosts/ser8/media.nix`
- Remove from media-services-setup target
- Run `systemctl stop sabnzbd.service` on ser8
- Run `make switch-ser8` to apply

**Time Estimate:** 1-1.5 hours

---

## Phase 5: Integration Services

**Objective:** Configure Sonarr, Radarr, and Prowlarr to use SABnzbd as download client

**Prerequisites:** Phase 4 complete, SABnzbd service running

**Implementation Steps:**

1. **Create Sonarr-SABnzbd integration service**
   - File: `hosts/ser8/media.nix`
   - Location: After arr-sabnzbd-setup service (around line 380)
   - Pattern: `hosts/ser8/media.nix:306-347` (arr-qbittorrent-setup)
   - Service name: `arr-sonarr-sabnzbd-setup`
   - Add SABnzbd download client via Sonarr API (`/api/v3/downloadclient`)
   - Set category: `tv`

2. **Create Radarr-SABnzbd integration service**
   - Location: After arr-sonarr-sabnzbd-setup
   - Nearly identical to Sonarr service
   - Service name: `arr-radarr-sabnzbd-setup`
   - Use Radarr API port: 7878
   - Set category: `movies`

3. **Update arr-prowlarr-setup service**
   - Location: `hosts/ser8/media.nix:349-399`
   - Modify existing service script
   - Add SABnzbd download client via Prowlarr API (`/api/v1/downloadclient`)
   - Insert after line 391 (after add_arr_application calls)

4. **Update service dependencies**
   - Modify arr-prowlarr-setup `after` list (line 351-356)
   - Add `arr-sabnzbd-setup.service` to dependencies

5. **Update media-services-setup target**
   - Location: `hosts/ser8/media.nix:403-416`
   - Add `arr-sonarr-sabnzbd-setup.service` and `arr-radarr-sabnzbd-setup.service`
   - Add to both `wants` and `after` lists

**Validation:**

```bash
# Build and test
make build-ser8
make test-ser8

# Check integration services
make ssh-ser8
systemctl status arr-sonarr-sabnzbd-setup.service
systemctl status arr-radarr-sabnzbd-setup.service
systemctl status arr-prowlarr-setup.service

# Verify in Web UIs
# Sonarr: http://sonarr.vofi → Settings → Download Clients → Should show SABnzbd
# Radarr: http://radarr.vofi → Settings → Download Clients → Should show SABnzbd
# Prowlarr: http://prowlarr.vofi → Settings → Download Clients → Should show SABnzbd

# Test connections in UI (click "Test" button for each)
```

**Rollback:**
- Remove arr-sonarr-sabnzbd-setup and arr-radarr-sabnzbd-setup services
- Revert changes to arr-prowlarr-setup
- Remove from media-services-setup target
- Manually delete SABnzbd clients from Sonarr/Radarr/Prowlarr UIs
- Run `make switch-ser8`

**Time Estimate:** 1.5-2 hours

---

## Phase 6: Reverse Proxy Configuration

**Objective:** Add SABnzbd to Caddy reverse proxy for external HTTPS access

**Prerequisites:** Phase 5 complete

**Implementation Steps:**

1. **Add SABnzbd route to Caddyfile**
   - File: `modules/gateway/Caddyfile`
   - Location: After line 28 (after prowlarr.vofi block)
   - Pattern: `modules/gateway/Caddyfile:14-28` (existing service blocks)

   Add:
   ```
   sabnzbd.vofi {
     reverse_proxy ser8.internal:8080
   }
   ```

2. **Deploy Caddy configuration**
   ```bash
   # Build firebat configuration
   make build-firebat

   # Test configuration
   make test-firebat

   # Apply configuration
   make switch-firebat
   ```

**Validation:**

```bash
# Check Caddy is running on firebat
make ssh-firebat
systemctl status caddy.service

# Check Caddy logs for errors
journalctl -u caddy.service -n 50

# Test internal access from firebat
curl -k https://sabnzbd.vofi

# Test from workstation
curl -k https://sabnzbd.vofi

# Access web UI
open https://sabnzbd.vofi
# Should show SABnzbd web interface
```

**Rollback:**
- Remove sabnzbd.vofi block from Caddyfile
- Run `make switch-firebat` to reload Caddy

**Time Estimate:** 30 minutes

---

## Phase 7: Testing and Validation

**Objective:** Comprehensive end-to-end testing and smoketest creation

**Prerequisites:** Phases 1-6 complete

**Implementation Steps:**

1. **Create smoketest script**
   - File: `scripts/smoketests/sabnzbd-test.sh`
   - Make executable: `chmod +x scripts/smoketests/sabnzbd-test.sh`
   - Include tests for:
     - SABnzbd service running
     - API accessible
     - Categories configured
     - Directories exist with correct permissions
     - Sonarr/Radarr integration services completed
     - Reverse proxy access

2. **Manual NZB download test**
   - Access SABnzbd web UI: `https://sabnzbd.vofi`
   - Upload test NZB file
   - Monitor queue and completion
   - Verify file in `/mnt/media/downloads/usenet/complete/default/`

3. **Sonarr end-to-end test**
   - Access Sonarr: `https://sonarr.vofi`
   - Trigger automatic search for missing episode
   - Verify NZB sent to SABnzbd with "tv" category
   - Wait for completion and import
   - Verify episode in `/mnt/media/tv/`

4. **Radarr end-to-end test**
   - Access Radarr: `https://radarr.vofi`
   - Trigger automatic search for missing movie
   - Verify NZB sent to SABnzbd with "movies" category
   - Wait for completion and import
   - Verify movie in `/mnt/media/movies/`

5. **Permission validation**
   ```bash
   make ssh-ser8

   # Check directory ownership
   ls -la /mnt/media/downloads/usenet/
   # Should show: drwxrwxr-x sabnzbd media

   # Verify media group membership
   groups sonarr  # Should include "media"
   groups radarr  # Should include "media"
   groups sabnzbd # Should include "media"
   ```

6. **Run automated smoketests**
   ```bash
   ./scripts/smoketests/sabnzbd-test.sh
   # Should show all tests passing
   ```

7. **Documentation updates**
   - Update `CLAUDE.md`:
     - Add SABnzbd to module system section (line 11-12)
     - Add sabnzbd.vofi to service access section (line 61-69)
     - Document Usenet provider configuration requirements

**Validation:**

```bash
# Full deployment test
make apply-ser8

# Verify all services healthy
make status

# Run smoketests
./scripts/smoketests/sabnzbd-test.sh

# Check for errors in logs
make ssh-ser8
journalctl -u sabnzbd.service --since "1 hour ago"
journalctl -u arr-sabnzbd-setup.service --since "1 hour ago"
journalctl -u arr-sonarr-sabnzbd-setup.service --since "1 hour ago"
journalctl -u arr-radarr-sabnzbd-setup.service --since "1 hour ago"
```

**Rollback:**
- Full rollback: `make rollback-ser8`
- Remove smoketest script
- Revert documentation changes

**Time Estimate:** 2-3 hours

---

## Post-Implementation Checklist

After completing all 7 phases, verify:

- [ ] SABnzbd service starts automatically on boot
- [ ] Configuration persists across reboots
- [ ] Secrets are properly encrypted and decrypted
- [ ] All integration services complete successfully
- [ ] Download categories work correctly (tv, movies, default)
- [ ] File permissions allow Sonarr/Radarr to read completed downloads
- [ ] Post-processing works (unrar, par2 verification)
- [ ] Reverse proxy provides HTTPS access
- [ ] Smoketests pass consistently
- [ ] No errors in systemd logs
- [ ] Documentation updated in CLAUDE.md

---

## Complete Rollback Procedure

To completely remove SABnzbd integration:

```bash
# 1. Stop services on ser8
make ssh-ser8
systemctl stop sabnzbd.service
systemctl disable sabnzbd.service

# 2. Roll back to previous configuration
make rollback-ser8

# 3. Remove module file
rm modules/media/sabnzbd.nix

# 4. Revert all file changes
git checkout hosts/ser8/media.nix
git checkout hosts/ser8/impermanence.nix
git checkout modules/gateway/Caddyfile

# 5. Remove smoketest
rm scripts/smoketests/sabnzbd-test.sh

# 6. Rebuild clean configuration
make switch-ser8

# 7. Optionally remove secrets
make sops-edit-ser8
# (manually remove sabnzbd_* keys)
```

---

## Troubleshooting Guide

### SABnzbd service fails to start

**Diagnosis:**
```bash
systemctl status sabnzbd.service
journalctl -u sabnzbd.service -n 100
```

**Common Causes:**
- Config file syntax errors → Check `/var/lib/sabnzbd/sabnzbd.ini`
- Permission issues → Verify `chown sabnzbd:sabnzbd /var/lib/sabnzbd`
- Port conflict → Check: `ss -tlnp | grep 8080`

**Resolution:**
- Fix config template in `hosts/ser8/media.nix`
- Rebuild: `make switch-ser8`

### Integration services fail

**Diagnosis:**
```bash
journalctl -u arr-sonarr-sabnzbd-setup.service -n 50
journalctl -u arr-radarr-sabnzbd-setup.service -n 50
```

**Common Causes:**
- SABnzbd not ready → Increase sleep time in scripts
- API key mismatch → Verify secrets match
- Network issues → Test: `curl http://localhost:8080/sabnzbd/api?mode=version`

**Resolution:**
- Manually restart: `systemctl restart arr-sonarr-sabnzbd-setup.service`
- Verify API keys: `cat /run/secrets/sabnzbd_api_key`

### Downloads fail or incomplete

**Diagnosis:**
- Check SABnzbd web UI → History tab
- Test Usenet server: Config → Servers → Test Server
- Check logs: `journalctl -u sabnzbd.service | grep -i error`

**Common Causes:**
- Invalid Usenet credentials → Update in Phase 3
- Incomplete NZB files
- SSL certificate issues

**Resolution:**
- Update credentials: `make sops-edit-ser8`
- Try different Usenet provider

### Permission denied in Sonarr/Radarr

**Diagnosis:**
```bash
ls -la /mnt/media/downloads/usenet/complete/tv/
groups sonarr
groups radarr
```

**Common Causes:**
- Incorrect directory permissions (should be `0775 sabnzbd media`)
- Users not in media group

**Resolution:**
- Fix permissions: `chown -R sabnzbd:media /mnt/media/downloads/usenet/`
- Rebuild: `make switch-ser8`

---

## Success Criteria

Implementation complete when:

1. **Services Running:** All services start without errors
2. **API Accessible:** SABnzbd API responds to health checks
3. **Integration Working:** Sonarr and Radarr send downloads to SABnzbd
4. **Downloads Complete:** Test NZB downloads successfully
5. **Permissions Correct:** Downloaded files readable by media group
6. **Reverse Proxy Works:** HTTPS access via sabnzbd.vofi
7. **Smoketests Pass:** Automated tests complete without failures
8. **Persistence Works:** Configuration survives reboots
9. **No Log Errors:** No recurring errors in systemd logs
10. **Documentation Updated:** CLAUDE.md reflects new service

---

## Time Summary

- Phase 1: 30-60 minutes
- Phase 2: 30 minutes
- Phase 3: 45-60 minutes
- Phase 4: 1-1.5 hours
- Phase 5: 1.5-2 hours
- Phase 6: 30 minutes
- Phase 7: 2-3 hours

**Total:** 6-8 hours

**Recommended:** Complete phases sequentially with full validation between phases.
