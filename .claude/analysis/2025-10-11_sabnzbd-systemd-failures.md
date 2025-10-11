# SABnzbd Implementation Failure Analysis

**Date**: 2025-10-11
**System**: ser8 media server
**Issue**: SABnzbd integration causing entire *arr media stack to fail

---

## Executive Summary

The SABnzbd implementation has **one critical root cause** with 8 critical issues and 4 secondary issues. The fundamental problem is that the SABnzbd service is not starting properly, which cascades into failures throughout the media services stack (Prowlarr, Sonarr, Radarr).

**Root Cause**: Race condition between config file deployment and SABnzbd service startup, combined with missing directory creation and insufficient wait times.

**Impact**: Complete media services stack failure - Prowlarr cannot add SABnzbd as download client, blocking all Usenet downloads.

---

## Root Cause: SABnzbd Service Not Starting

**Location**: `hosts/ser8/media.nix:484-519`

The NixOS SABnzbd service expects the configuration file to exist at startup, but:
- Configuration is deployed by separate oneshot service (`sabnzbd-config`)
- Service runs in parallel without proper dependency enforcement
- SABnzbd may start before config file is written
- Results in failed startup or API not binding to configured port

---

## Critical Issues

### Issue #1: Missing Service Dependency

**File**: `hosts/ser8/media.nix:484-519`

**Problem**:
- `sabnzbd-config` has `before = ["sabnzbd.service"]` (line 487)
- But `sabnzbd.service` doesn't have `after` dependency
- SystemD may start SABnzbd before config is written

**Impact**: SABnzbd fails to start or starts with wrong configuration

**Fix**: Add to configuration:
```nix
systemd.services.sabnzbd = {
  after = [ "sabnzbd-config.service" ];
  requires = [ "sabnzbd-config.service" ];
};
```

---

### Issue #2: Missing Subdirectory Creation

**File**: `hosts/ser8/media.nix:497-517`

**Problem**:
- SABnzbd config references subdirectories (lines 280-282):
  - `log_dir = logs`
  - `admin_dir = admin`
  - `nzb_backup_dir = backup`
- These are relative paths expecting `/var/lib/sabnzbd/{logs,admin,backup}`
- Directories are not created before SABnzbd starts

**Impact**: SABnzbd fails to start or has permission errors

**Fix**: Add to `sabnzbd-config` service script (after line 505):
```bash
mkdir -p "$CONFIG_DIR"/{logs,admin,backup}
chown -R sabnzbd:sabnzbd "$CONFIG_DIR"
```

---

### Issue #3: Configuration Uses Relative Paths

**File**: `hosts/ser8/media.nix:280-282`

**Problem**:
- Config uses relative paths that depend on working directory
- If SABnzbd doesn't start in `/var/lib/sabnzbd`, directories won't be found

**Impact**: Potential directory not found errors

**Fix**: Change to absolute paths in sabnzbd.ini template:
```ini
log_dir = /var/lib/sabnzbd/logs
admin_dir = /var/lib/sabnzbd/admin
nzb_backup_dir = /var/lib/sabnzbd/backup
```

---

### Issue #4: Wait Timeout Too Short

**File**: `hosts/ser8/media.nix:587-589`

**Problem**:
- `arr-sabnzbd-setup` waits only 30 iterations (line 589)
- With 2s sleep = 60 seconds total
- SABnzbd may need longer for initial setup, database migration

**Impact**: Setup service fails prematurely, marks everything as broken

**Log Evidence**:
```
Oct 11 11:29:23 ser8 arr-sabnzbd-setup-start[1969497]: ✗ SABnzbd API failed to become ready after 60 seconds
```

**Fix**: Increase timeout to 60 iterations (120 seconds):
```bash
wait_for_api "SABnzbd" "http://localhost:8085/api?mode=version&apikey=$(cat ${
  config.sops.secrets."sabnzbd_api_key".path
}))" 60
```

---

### Issue #5: SABnzbd Module Incomplete

**File**: `modules/media/sabnzbd.nix:16-18`

**Problem**:
- Module only sets `enable = lib.mkDefault false`
- No actual service configuration beyond user group membership
- Relies entirely on host-specific configuration

**Impact**: Low - service is enabled in `configuration.nix:178`, but module is underdeveloped

**Fix**: Either add configuration options or document that configuration happens in hosts

---

### Issue #6: API Endpoint Test May Fail Early

**File**: `hosts/ser8/media.nix:587-589`

**Problem**:
- API test uses `mode=version` which may not be available immediately
- SABnzbd initialization sequence:
  1. Start process
  2. Initialize database
  3. Load configuration
  4. Start web server
  5. Activate API endpoints

**Impact**: Health check may fail even if service will be ready soon

**Fix**: Add port check before API check, or use simpler endpoint

---

### Issue #7: Missing tmpfiles Ordering

**File**: `hosts/ser8/impermanence.nix:126-131`

**Problem**:
- tmpfiles rules create directories but don't guarantee ordering
- No explicit dependency ensuring tmpfiles runs before SABnzbd

**Impact**: SABnzbd might start before download directories exist

**Fix**: Add explicit dependency:
```nix
systemd.services.sabnzbd = {
  after = [ "systemd-tmpfiles-setup.service" ];
};
```

---

### Issue #8: No Health Check Before Prowlarr Integration

**File**: `hosts/ser8/media.nix:724-727`

**Problem**:
- `arr-prowlarr-setup` depends on `arr-sabnzbd-setup` (line 684)
- But if `arr-sabnzbd-setup` failed, Prowlarr setup still runs
- Prowlarr tries to test SABnzbd connection and fails

**Log Evidence**:
```
Oct 11 11:55:11 ser8 arr-prowlarr-setup-start[3805]: ✗ Failed to add SABnzbd to Prowlarr. Response:
"errorMessage": "Test was aborted due to an error: Object reference not set to an instance of an object."
```

**Impact**: Prowlarr setup fails, blocking entire media stack

**Fix**: Add explicit readiness check in `arr-prowlarr-setup` before line 725:
```bash
wait_for_api "SABnzbd" "http://localhost:8085/api?mode=version&apikey=$(cat ${
  config.sops.secrets."sabnzbd_api_key".path
})" 30
```

---

## Secondary Issues (Non-Critical)

### Issue A: Port Mismatch Documentation

**Files**:
- `modules/media/sabnzbd.nix:21` - Opens port 8085
- Upstream NixOS module default - 8080

**Issue**: Custom module opens 8085 (correct), but could be confusing vs upstream default

**Recommendation**: Document this or explicitly override upstream firewall option

---

### Issue B: No Service Restart Policy

**File**: Upstream NixOS SABnzbd module

**Issue**: Service doesn't specify restart policies, won't auto-restart on crash

**Recommendation**: Add restart configuration:
```nix
systemd.services.sabnzbd = {
  serviceConfig = {
    Restart = "on-failure";
    RestartSec = "5s";
  };
};
```

---

### Issue C: Category Verification Not Robust

**File**: `hosts/ser8/media.nix:597-600`

**Issue**: Uses simple `grep` which could false-positive on partial matches

**Recommendation**: Use proper JSON parsing:
```bash
if echo "$CATEGORIES" | jq -e '.categories[] | select(.name == "tv")' >/dev/null; then
```

---

### Issue D: No Debug Logging

**File**: `hosts/ser8/media.nix:484-605`

**Issue**: Setup scripts don't log to files for debugging

**Recommendation**: Add logging:
```bash
exec > >(tee -a /var/log/sabnzbd-setup.log)
exec 2>&1
```

---

## Verification Steps

After implementing fixes, verify SABnzbd with these commands:

### 1. Check Service Status
```bash
ssh ser8 'systemctl status sabnzbd.service'
ssh ser8 'systemctl status sabnzbd-config.service'
ssh ser8 'systemctl status arr-sabnzbd-setup.service'
```

### 2. Verify Configuration File
```bash
ssh ser8 'ls -la /var/lib/sabnzbd/sabnzbd.ini'
ssh ser8 'test -r /var/lib/sabnzbd/sabnzbd.ini && echo "Config readable"'
ssh ser8 'cat /var/lib/sabnzbd/sabnzbd.ini | grep "^port ="'
```

### 3. Check Directory Permissions
```bash
ssh ser8 'ls -la /var/lib/sabnzbd/'
ssh ser8 'ls -la /mnt/media/downloads/usenet/'
```

### 4. Test API Directly
```bash
ssh ser8 'curl -f "http://localhost:8085/api?mode=version&apikey=$(cat /run/secrets/sabnzbd_api_key)"'
ssh ser8 'curl -s "http://localhost:8085/api?mode=queue&apikey=$(cat /run/secrets/sabnzbd_api_key)" | head -20'
ssh ser8 'curl -s "http://localhost:8085/api?mode=get_cats&apikey=$(cat /run/secrets/sabnzbd_api_key)"'
```

### 5. Check Service Logs
```bash
ssh ser8 'journalctl -u sabnzbd.service -n 50 --no-pager'
ssh ser8 'journalctl -u arr-sabnzbd-setup.service -n 50 --no-pager'
ssh ser8 'journalctl -u arr-prowlarr-setup.service -n 50 --no-pager'
```

### 6. Verify Process and Port
```bash
ssh ser8 'ps aux | grep sabnzbd'
ssh ser8 'ss -tlnp | grep 8085'
```

### 7. Test Prowlarr Connection
```bash
ssh ser8 'curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $(cat /run/secrets/prowlarr_api_key)" \
  -d "{\"implementation\":\"Sabnzbd\",\"fields\":[{\"name\":\"host\",\"value\":\"127.0.0.1\"},{\"name\":\"port\",\"value\":8085},{\"name\":\"apiKey\",\"value\":\"$(cat /run/secrets/sabnzbd_api_key)\"}]}" \
  http://localhost:9696/api/v1/downloadclient/test'
```

---

## Code Pointers Summary

### Root Cause Locations
- `hosts/ser8/media.nix:484-519` - sabnzbd-config service missing dependencies
- `hosts/ser8/media.nix:564-605` - arr-sabnzbd-setup insufficient wait time
- `hosts/ser8/media.nix:679-735` - arr-prowlarr-setup no health check

### Critical Fix Locations
1. **Service dependencies**: `hosts/ser8/media.nix:484`
2. **Subdirectory creation**: `hosts/ser8/media.nix:497-517`
3. **Relative paths**: `hosts/ser8/media.nix:280-282`
4. **Wait timeout**: `hosts/ser8/media.nix:589`
5. **Health check**: `hosts/ser8/media.nix:724`

### Supporting Files
- `hosts/ser8/systemd_helpers.sh:44-60` - wait_for_api function
- `hosts/ser8/systemd_helpers.sh:125-183` - setup_sabnzbd_client function
- `hosts/ser8/systemd_helpers.sh:236-283` - add_sabnzbd_to_prowlarr function
- `hosts/ser8/impermanence.nix:126-131` - Directory tmpfiles
- `modules/media/sabnzbd.nix:16-22` - Module definition

---

## Priority Recommendations

### Must Fix Immediately (Blocking)
1. **Issue #1** - Add service dependency on sabnzbd-config
2. **Issue #2** - Create subdirectories in sabnzbd-config
3. **Issue #4** - Increase wait timeout to 60 iterations
4. **Issue #8** - Add health check before Prowlarr integration

### Should Fix Soon (Reliability)
1. **Issue #3** - Use absolute paths in config
2. **Issue #7** - Add tmpfiles ordering dependency
3. **Issue B** - Add restart policy for resilience

### Nice to Have (Improvements)
1. **Issue #5** - Enhance module configuration options
2. **Issue #6** - Improve API endpoint testing
3. **Issue A** - Document port configuration
4. **Issue C** - Use robust JSON parsing
5. **Issue D** - Add debug logging

---

## Conclusion

The SABnzbd implementation failure is caused by a combination of race conditions, missing dependencies, and insufficient wait times. The issues are well-understood and fixable with targeted changes to service dependencies, directory creation, and health checks.

**Estimated Fix Time**: 30-45 minutes
**Risk Level**: Low - fixes are isolated to configuration, no code changes required
**Testing Required**: Full deployment cycle with verification steps above
