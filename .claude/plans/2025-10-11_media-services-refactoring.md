# Implementation Plan: Media Services Systemd Refactoring

**Date**: 2025-10-11
**Goal**: Refactor media services from 8 systemd services to 3 + add API key sanitization
**Related Analysis**: `.claude/analysis/2025-10-11_sabnzbd-systemd-failures.md`

---

## Overview

This plan refactors the media services systemd architecture to:
1. **Add sanitized logging** - Prevent API keys from appearing in logs
2. **Consolidate configuration** - Merge arr-config + qbittorrent-config → media-config
3. **Separate concerns** - Create servarrs-setup (Prowlarr connections) and download-clients-setup (download client connections)
4. **Simplify meta target** - Rename media-services-setup → media-setup

**Services reduction**: 8 services → 3 services + 1 meta target

---

## Phase 1: Add Sanitized Logging Infrastructure

### Step 1.1: Create API Key Sanitization Function

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (add after line 1, before existing functions)

**What to change:**
Add a new bash function `sanitize_api_key()` that:
- Takes a string as input (URL, command, or response text)
- Uses sed/regex to replace API key patterns with `***REDACTED***`
- Handles multiple formats: `apikey=VALUE`, `api_key=VALUE`, `X-Api-Key: VALUE`
- Supports both query parameters and headers
- Returns the sanitized string

**Why:**
Centralized sanitization ensures consistent API key redaction across all logging points. This prevents accidental exposure in systemd journal logs, error messages, and debug output.

**Dependencies:** None

---

### Step 1.2: Create Sanitized Curl Wrapper Function

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (add after sanitize_api_key function)

**What to change:**
Add a new bash function `curl_safe()` that:
- Accepts all the same arguments as curl
- Reconstructs the full curl command string
- Sanitizes the command before logging it with `echo "Executing: $(sanitize_api_key "$command")"`
- Executes the actual curl with original (unsanitized) arguments
- Captures both stdout and stderr
- Sanitizes the response before logging or returning it
- Preserves curl's exit code

**Why:**
Wrapping curl allows us to log the sanitized version of commands while still executing the real version with actual API keys. This prevents keys from appearing in systemd journal when services log their actions.

**Dependencies:** Step 1.1 (requires sanitize_api_key function)

---

### Step 1.3: Update wait_for_api to Use Sanitized Logging

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (lines 52-67, existing wait_for_api function)

**What to change:**
Modify the existing `wait_for_api` function to:
- Replace direct curl calls with `curl_safe` wrapper
- Sanitize the URL before logging "Waiting for $service at $url"
- Sanitize any error messages that include URLs
- Keep the retry logic and timeout behavior unchanged

**Why:**
The wait_for_api function is called for every service and logs URLs containing API keys. Sanitizing these logs prevents keys from appearing during service startup.

**Dependencies:** Step 1.2 (requires curl_safe function)

---

### Step 1.4: Update setup_qbittorrent_client to Use Sanitized Logging

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (lines 70-130, setup_qbittorrent_client function)

**What to change:**
Modify the existing `setup_qbittorrent_client` function to:
- Replace all curl invocations with `curl_safe`
- Sanitize URLs in echo statements before logging
- Sanitize the response body before logging in error conditions (lines 126-127)
- Keep all business logic (checks, API calls, response validation) unchanged

**Why:**
This function makes API calls with keys in headers and logs responses. Without sanitization, API keys appear in systemd journal during qBittorrent setup.

**Dependencies:** Step 1.2 (requires curl_safe function)

---

### Step 1.5: Update setup_sabnzbd_client to Use Sanitized Logging

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (lines 133-190, setup_sabnzbd_client function)

**What to change:**
Modify the existing `setup_sabnzbd_client` function to:
- Replace all curl invocations with `curl_safe`
- Sanitize URLs in echo statements (the API URLs contain apikey parameter)
- Sanitize the response body before logging in error conditions (lines 186-187)
- Keep all business logic unchanged

**Why:**
SABnzbd API URLs include the API key as a query parameter. Every log line that shows these URLs exposes the key. Sanitization prevents this.

**Dependencies:** Step 1.2 (requires curl_safe function)

---

### Step 1.6: Update add_arr_application and add_sabnzbd_to_prowlarr to Use Sanitized Logging

**Files to modify:**
- `hosts/ser8/systemd_helpers.sh` (lines 193-240 for add_arr_application, lines 243-290 for add_sabnzbd_to_prowlarr)

**What to change:**
Modify both functions to:
- Replace all curl invocations with `curl_safe`
- Sanitize any URLs or API responses before logging
- Sanitize the response body before logging in error conditions
- Keep all business logic unchanged

**Why:**
These functions connect services using API keys. Error messages and debug output can expose keys. Sanitization prevents this.

**Dependencies:** Step 1.2 (requires curl_safe function)

---

## Phase 2: Consolidate Configuration Services

### Step 2.1: Create Combined media-config Service Definition

**Files to modify:**
- `hosts/ser8/media.nix` (add new service around line 420, replacing arr-config)

**What to change:**
Create new systemd service `media-config.service` that:
- Sets description to "Deploy all media service configurations with secrets"
- Uses `Type = "oneshot"` with `RemainAfterExit = true`
- Sets `before = [ "sonarr.service" "radarr.service" "prowlarr.service" "qbittorrent-nox.service" "sabnzbd.service" ]`
- Sets `wantedBy = [ "multi-user.target" ]`
- Sources the systemd_helpers.sh script
- Uses `set -euo pipefail` for error handling

**Why:**
Configuration of all services should happen in a single atomic unit. This simplifies dependency management and ensures consistent ordering. Previously splitting arr-config and qbittorrent-config created unnecessary complexity.

**Dependencies:** Phase 1 complete (requires sanitized helper functions)

---

### Step 2.2: Port arr Service Configuration Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within media-config service script section from Step 2.1)

**What to change:**
Copy the configuration logic from existing `arr-config.service` (lines 436-444):
- Call `configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}`
- Call `configure_arr radarr ${config.sops.templates."radarr-config.xml".path}`
- Call `configure_arr prowlarr ${config.sops.templates."prowlarr-config.xml".path}`
- Call `configure_arr sabnzbd ${config.sops.templates."sabnzbd.ini".path}`
- All these use the configure_arr helper function from systemd_helpers.sh

**Why:**
This deploys the SOPS-templated configuration files to each service's expected location before the services start. The configure_arr function handles the file operations.

**Dependencies:** Step 2.1 (requires media-config service shell)

---

### Step 2.3: Port qBittorrent Configuration Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within media-config service script section, after arr configuration)

**What to change:**
Copy the qBittorrent configuration logic from existing `qbittorrent-config.service` (lines 460-481):
- Set CONFIG_DIR, CONFIG_FILE, TEMP_FILE variables
- Create the config directory with proper ownership
- Remove existing config file if present
- Atomically deploy the new config file from SOPS template
- Set proper ownership and permissions (600)
- Log success message

**Why:**
qBittorrent configuration must be deployed before the service starts. Consolidating here with arr services reduces the number of oneshot services and simplifies the startup sequence.

**Dependencies:** Step 2.2 (logical grouping, can be in same script)

---

### Step 2.4: Remove Old Configuration Service Definitions

**Files to modify:**
- `hosts/ser8/media.nix` (lines 420-445 for arr-config, lines 448-482 for qbittorrent-config)

**What to change:**
Delete the entire service definitions for:
- `arr-config.service` (lines 420-445)
- `qbittorrent-config.service` (lines 448-482)

Leave only the new `media-config.service` created in Steps 2.1-2.3.

**Why:**
These services are now redundant. All their logic has been moved to media-config. Keeping them would create conflicts and confusion.

**Dependencies:** Steps 2.1, 2.2, 2.3 complete (new service must contain all logic)

---

## Phase 3: Create Servarrs Setup Service

### Step 3.1: Create servarrs-setup Service Definition

**Files to modify:**
- `hosts/ser8/media.nix` (add new service after media-config, around line 520)

**What to change:**
Create new systemd service `servarrs-setup.service` that:
- Sets description to "Configure Prowlarr connections to Sonarr and Radarr"
- Uses `Type = "oneshot"` with `RemainAfterExit = true`
- Sets `after = [ "media-config.service" "prowlarr.service" "sonarr.service" "radarr.service" ]`
- Sets `requires = [ "media-config.service" ]`
- Sets `wantedBy = [ "multi-user.target" ]`
- Sources systemd_helpers.sh
- Uses `set -euo pipefail`

**Why:**
Prowlarr ↔ Sonarr/Radarr connections require both Prowlarr and the arr services to be configured first. Separating this into its own service makes the dependency chain explicit and allows configuration (Phase 2) to complete before connections are established.

**Dependencies:** Phase 2 complete (requires media-config service)

---

### Step 3.2: Add API Readiness Checks

**Files to modify:**
- `hosts/ser8/media.nix` (within servarrs-setup service script section from Step 3.1)

**What to change:**
At the beginning of the script, add wait_for_api calls for:
- Prowlarr: `wait_for_api "Prowlarr" "http://localhost:9696/ping" 30`
- Sonarr: `wait_for_api "Sonarr" "http://localhost:8989/ping" 30`
- Radarr: `wait_for_api "Radarr" "http://localhost:7878/ping" 30`

**Why:**
Even though services are started, their APIs may not be immediately available. Explicit waiting ensures the APIs are responsive before attempting connections.

**Dependencies:** Step 3.1 (requires servarrs-setup service shell)

---

### Step 3.3: Port Prowlarr Application Connection Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within servarrs-setup service script section, after API checks)

**What to change:**
Copy the Prowlarr application connection logic from existing `arr-prowlarr-setup.service` (lines 717-722):
- Call `add_arr_application "Sonarr" "8989" "${config.sops.secrets."sonarr_api_key".path}" "[5000,5030,5040]" "${config.sops.secrets."prowlarr_api_key".path}"`
- Call `add_arr_application "Radarr" "7878" "${config.sops.secrets."radarr_api_key".path}" "[2000,2010,2020,2030,2040,2045,2050,2060]" "${config.sops.secrets."prowlarr_api_key".path}"`
- These use the add_arr_application helper function which handles idempotency

**Why:**
Prowlarr needs to be connected to Sonarr and Radarr so it can sync indexers to them. This is the core "servarrs" connectivity that forms the indexer management layer.

**Dependencies:** Step 3.2 (APIs must be ready before connections)

---

## Phase 4: Create Download Clients Setup Service

### Step 4.1: Create download-clients-setup Service Definition

**Files to modify:**
- `hosts/ser8/media.nix` (add new service after servarrs-setup, around line 570)

**What to change:**
Create new systemd service `download-clients-setup.service` that:
- Sets description to "Configure download clients (qBittorrent, SABnzbd) for all Servarr services"
- Uses `Type = "oneshot"` with `RemainAfterExit = true`
- Sets `after = [ "media-config.service" "qbittorrent-nox.service" "sabnzbd.service" "sonarr.service" "radarr.service" "prowlarr.service" ]`
- Sets `requires = [ "media-config.service" ]`
- Sets `wantedBy = [ "multi-user.target" ]`
- Sources systemd_helpers.sh
- Uses `set -euo pipefail`

**Why:**
Download client connections (qBittorrent/SABnzbd → arr services) require all services to be configured. This service consolidates all download client setup in one place. Note: Does NOT depend on servarrs-setup, so they can run in parallel.

**Dependencies:** Phase 2 complete (requires media-config service)

---

### Step 4.2: Add Download Client API Readiness Checks

**Files to modify:**
- `hosts/ser8/media.nix` (within download-clients-setup service script section from Step 4.1)

**What to change:**
At the beginning of the script, add wait_for_api calls for:
- Sonarr: `wait_for_api "Sonarr" "http://localhost:8989/ping" 30`
- Radarr: `wait_for_api "Radarr" "http://localhost:7878/ping" 30`
- Prowlarr: `wait_for_api "Prowlarr" "http://localhost:9696/ping" 30`
- SABnzbd: `wait_for_api "SABnzbd" "http://localhost:8085/api?mode=version&apikey=$(cat ${config.sops.secrets."sabnzbd_api_key".path})" 60`
- qBittorrent: `wait_for_api "qBittorrent" "http://localhost:8080/api/v2/app/version" 30`

**Why:**
Replace the `sleep 30` from the old arr-qbittorrent-setup (line 550) with explicit API checks. This is more reliable and faster on average.

**Dependencies:** Step 4.1 (requires download-clients-setup service shell)

---

### Step 4.3: Port qBittorrent Connection Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within download-clients-setup service script section, after API checks)

**What to change:**
Copy the qBittorrent setup logic from existing `arr-qbittorrent-setup.service` (lines 552-559):
- Call `setup_qbittorrent_client "Sonarr" "8989" "${config.sops.secrets."sonarr_api_key".path}" "tvCategory" "tv" "${config.sops.secrets."qbittorrent_admin_password".path}"`
- Call `setup_qbittorrent_client "Radarr" "7878" "${config.sops.secrets."radarr_api_key".path}" "movieCategory" "movies" "${config.sops.secrets."qbittorrent_admin_password".path}"`
- These use the setup_qbittorrent_client helper which handles idempotency

**Why:**
qBittorrent needs to be configured as a download client in both Sonarr and Radarr with appropriate categories (tv/movies) for automatic sorting.

**Dependencies:** Step 4.2 (APIs must be ready)

---

### Step 4.4: Port SABnzbd Verification Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within download-clients-setup service script section, after qBittorrent setup)

**What to change:**
Copy the SABnzbd verification logic from existing `arr-sabnzbd-setup.service` (lines 592-602):
- Verify categories are configured
- Execute: `CATEGORIES=$($CURL_BIN -s "http://localhost:8085/api?mode=get_cats&apikey=$(cat ${config.sops.secrets."sabnzbd_api_key".path})")`
- Check if tv and movies categories exist
- Log warning if not configured correctly

**Why:**
SABnzbd categories must be configured before connecting it to arr services. This verification ensures the configuration deployed in media-config was successful.

**Dependencies:** Step 4.3 (logical grouping)

---

### Step 4.5: Port SABnzbd Connection Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within download-clients-setup service script section, after verification)

**What to change:**
Copy the SABnzbd setup logic from existing `arr-sonarr-sabnzbd-setup.service` (lines 635-637) and `arr-radarr-sabnzbd-setup.service` (lines 671-673):
- Call `setup_sabnzbd_client "Sonarr" "8989" "${config.sops.secrets."sonarr_api_key".path}" "tv" "${config.sops.secrets."sabnzbd_api_key".path}"`
- Call `setup_sabnzbd_client "Radarr" "7878" "${config.sops.secrets."radarr_api_key".path}" "movies" "${config.sops.secrets."sabnzbd_api_key".path}"`
- These use the setup_sabnzbd_client helper which handles idempotency

**Why:**
SABnzbd needs to be configured as a download client in both Sonarr and Radarr with appropriate categories (tv/movies) for Usenet downloads.

**Dependencies:** Step 4.4 (categories must be verified first)

---

### Step 4.6: Port SABnzbd to Prowlarr Connection Logic

**Files to modify:**
- `hosts/ser8/media.nix` (within download-clients-setup service script section, after SABnzbd arr connections)

**What to change:**
Copy the SABnzbd to Prowlarr logic from existing `arr-prowlarr-setup.service` (lines 725-727):
- Call `add_sabnzbd_to_prowlarr "${config.sops.secrets."sabnzbd_api_key".path}" "${config.sops.secrets."prowlarr_api_key".path}"`
- This uses the add_sabnzbd_to_prowlarr helper which handles idempotency

**Why:**
Prowlarr needs SABnzbd configured as a download client for testing indexers and potentially routing downloads.

**Dependencies:** Step 4.5 (SABnzbd should be connected to arr services first)

---

## Phase 5: Update Meta Target

### Step 5.1: Rename and Simplify media-services-setup

**Files to modify:**
- `hosts/ser8/media.nix` (lines 755-768, existing systemd.targets.media-services-setup definition)

**What to change:**
- Change attribute name from `media-services-setup` to `media-setup`
- Update description to "Complete media stack setup orchestration"
- Remove the `after` list (not needed for pure target)
- Set `wants = [ "media-config.service" "servarrs-setup.service" "download-clients-setup.service" ]`
- Keep `wantedBy = [ "multi-user.target" ]`
- Ensure there's no `script` section (this is a pure target, not an executable service)

**Why:**
Shorter, clearer name. The target now just coordinates dependencies between the three actual services. It doesn't execute any logic itself.

**Dependencies:** Phases 2, 3, 4 complete (all new services must exist)

---

### Step 5.2: Update SABnzbd Service Dependencies

**Files to modify:**
- `hosts/ser8/media.nix` (lines 743-753, existing systemd.services.sabnzbd definition from previous fixes)

**What to change:**
The current configuration references `sabnzbd-config.service` which no longer exists. Update:
- Change `after = [ "sabnzbd-config.service" "systemd-tmpfiles-setup.service" ]` to `after = [ "media-config.service" "systemd-tmpfiles-setup.service" ]`
- Change `requires = [ "sabnzbd-config.service" ]` to `requires = [ "media-config.service" ]`
- Keep the restart policy unchanged

**Why:**
This fixes the bug identified in the analysis. sabnzbd-config.service was merged into media-config, so references must be updated.

**Dependencies:** Phase 2 complete (media-config must exist)

---

## Phase 6: Remove Old Services

### Step 6.1: Delete Old Setup Services

**Files to modify:**
- `hosts/ser8/media.nix` (multiple service definitions to remove)

**What to change:**
Delete the entire service definitions for:
- `arr-qbittorrent-setup.service` (lines 484-562)
- `arr-sabnzbd-setup.service` (lines 565-605)
- `arr-sonarr-sabnzbd-setup.service` (lines 608-641)
- `arr-radarr-sabnzbd-setup.service` (lines 644-677)
- `arr-prowlarr-setup.service` (lines 680-735)

**Why:**
All logic from these services has been moved to servarrs-setup and download-clients-setup. Keeping them would create conflicts and confusion.

**Dependencies:** Phases 3 and 4 complete (new services must contain all logic)

---

### Step 6.2: Update Comments and Documentation

**Files to modify:**
- `hosts/ser8/media.nix` (scan entire file for references)

**What to change:**
Search for comments or documentation mentioning:
- `arr-config.service` → update to `media-config.service`
- `qbittorrent-config.service` → update to `media-config.service`
- `arr-qbittorrent-setup`, `arr-sabnzbd-setup`, etc. → update to `download-clients-setup.service`
- `arr-prowlarr-setup` → update to `servarrs-setup.service`
- `media-services-setup` → update to `media-setup`

**Why:**
Stale references in comments create confusion for future maintainers. All documentation should reflect the new architecture.

**Dependencies:** Phases 2-5 complete (all new services exist and old ones removed)

---

## Phase 7: Fix Bugs and Improvements

### Step 7.1: Add Architecture Documentation Block

**Files to modify:**
- `hosts/ser8/media.nix` (add comment block at the top of systemd services section, around line 418)

**What to change:**
Add a multi-line comment block explaining:
- The 3-service architecture (media-config, servarrs-setup, download-clients-setup)
- What each service does and when it runs
- The dependency chain
- The meta target (media-setup)
- Note that servarrs-setup and download-clients-setup can run in parallel

Example structure:
```
# Media Stack SystemD Services Architecture:
# 1. media-config → configures all services
# 2. servarrs-setup → connects Prowlarr to Sonarr/Radarr
# 3. download-clients-setup → connects qBittorrent/SABnzbd to all services
# 4. media-setup → meta target coordinating all above
```

**Why:**
Clear architecture documentation helps future maintainers understand the service dependency graph and rationale.

**Dependencies:** All previous phases complete

---

### Step 7.2: Add Service Startup Logging

**Files to modify:**
- `hosts/ser8/media.nix` (all new service scripts: media-config, servarrs-setup, download-clients-setup)

**What to change:**
At the beginning of each service script, after `set -euo pipefail`, add:
- `echo "Starting [SERVICE NAME]..."` with descriptive text
- At the end of each script: `echo "✓ Completed [SERVICE NAME]"`

Examples:
- media-config: "Starting media services configuration (Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd)..."
- servarrs-setup: "Starting Prowlarr connections to Sonarr and Radarr..."
- download-clients-setup: "Starting download client connections..."

**Why:**
Clear logging makes systemd journal easier to debug. Users can see exactly what stage of setup is happening and where failures occur.

**Dependencies:** Phases 2, 3, 4 complete (all services exist)

---

### Step 7.3: Verify Idempotency

**Files to modify:**
- Review (no changes needed if helpers are already idempotent)

**What to verify:**
Check that all helper functions have idempotency checks:
- `configure_arr` - Should skip if config exists and is identical
- `setup_qbittorrent_client` - Checks if download client exists before creating (line 86)
- `setup_sabnzbd_client` - Checks if download client exists before creating (line 148)
- `add_arr_application` - Checks if application exists before creating (line 208)
- `add_sabnzbd_to_prowlarr` - Checks if download client exists before creating (line 255)

All helpers already have these checks in hosts/ser8/systemd_helpers.sh.

**Why:**
Services may restart or be reconfigured. Idempotent operations can run multiple times without breaking or creating duplicates.

**Dependencies:** All phases complete (final verification)

---

### Step 7.4: Update CLAUDE.md

**Files to modify:**
- `CLAUDE.md` (lines around 15-30, under "Host Architecture" → "ser8" section)

**What to change:**
Update the ser8 description to reflect:
- New systemd service structure (media-config, servarrs-setup, download-clients-setup)
- Remove mentions of old services
- Add note about sanitized logging
- Keep all other ser8 information (ZFS, MergerFS, NordVPN, SABnzbd, etc.)

**Why:**
CLAUDE.md serves as the primary documentation for the repository. It should accurately reflect the current implementation.

**Dependencies:** All previous phases complete

---

## Sanitization Strategy Details

### Strategy 1: Sanitize Query Parameters
**Pattern to match:** `apikey=<VALUE>`, `api_key=<VALUE>`, `apiKey=<VALUE>`
**Replacement:** `apikey=***REDACTED***`
**Implementation:** Use sed with regex: `s/\(api[_-]\?key\)=[^&[:space:]]*/\1=***REDACTED***/gi`
**Applies to:** URLs in curl commands, error messages, log outputs

### Strategy 2: Sanitize HTTP Headers
**Pattern to match:** `X-Api-Key: <VALUE>`, `-H 'X-Api-Key: <VALUE>'`
**Replacement:** `X-Api-Key: ***REDACTED***`
**Implementation:** Use sed with regex: `s/\(X-Api-Key[[:space:]]*:[[:space:]]*\)[^'\"[:space:]]*/\1***REDACTED***/gi`
**Applies to:** curl -H arguments in logs

### Strategy 3: Sanitize JSON Response Bodies
**Pattern to match:** `"apiKey": "<VALUE>"`, `"api_key": "<VALUE>"`
**Replacement:** `"apiKey": "***REDACTED***"`
**Implementation:** Use sed with regex: `s/\("api[_-]\?[Kk]ey"[[:space:]]*:[[:space:]]*"\)[^"]*"/\1***REDACTED***"/g`
**Applies to:** API responses logged in error conditions

### Strategy 4: Sanitize Command-Line Arguments
**Pattern to match:** Full curl command strings containing API keys
**Replacement:** Apply all above strategies to the full command string
**Implementation:** Pass entire command through sanitize_api_key before echoing
**Applies to:** Debug output, error traces showing commands

### Strategy 5: Sanitize Process Listings
**Pattern to match:** Keys appearing in ps/top output (if services log their own commands)
**Replacement:** Not directly applicable (process listings controlled by OS)
**Mitigation:** Never pass API keys as command-line arguments; use stdin, env vars, or files instead
**Applies to:** Service execution strategy

### Strategy 6: Test Sanitization
**Location:** `systemd_helpers.sh` after all sanitization functions
**What to add:** Comment block with test examples showing input → output
**Examples:**
- Input: `curl "http://localhost:8989/api/v3/system/status?apikey=abc123"` → Output: `curl "http://localhost:8989/api/v3/system/status?apikey=***REDACTED***"`
- Input: `{"apiKey":"secret123"}` → Output: `{"apiKey":"***REDACTED***"}`

**Why:** Documents expected behavior and allows manual verification

---

## Dependency Graph

```
Phase 1: Sanitized Logging Infrastructure
    ↓
Phase 2: Consolidate Configuration Services
    ↓
    ├─→ Phase 3: Servarrs Setup Service ──┐
    │                                      ├─→ Phase 5: Update Meta Target
    └─→ Phase 4: Download Clients Setup ──┘       ↓
                                            Phase 6: Remove Old Services
                                                   ↓
                                            Phase 7: Improvements & Documentation
```

**Critical Path:** Phase 1 → Phase 2 → Phase 5 → Phase 6 → Phase 7
**Parallel Paths:** Phase 3 and Phase 4 can be developed in parallel after Phase 2

---

## Verification Steps (Post-Implementation)

### 1. Check service files exist
```bash
systemctl cat media-config.service
systemctl cat servarrs-setup.service
systemctl cat download-clients-setup.service
systemctl cat media-setup.service
```

### 2. Check old services are gone
```bash
systemctl cat arr-config.service  # should fail
systemctl cat qbittorrent-config.service  # should fail
systemctl cat arr-qbittorrent-setup.service  # should fail
systemctl cat arr-sabnzbd-setup.service  # should fail
systemctl cat arr-sonarr-sabnzbd-setup.service  # should fail
systemctl cat arr-radarr-sabnzbd-setup.service  # should fail
systemctl cat arr-prowlarr-setup.service  # should fail
systemctl cat media-services-setup.service  # should fail
```

### 3. Verify dependency chain
```bash
systemctl list-dependencies media-setup.service
# Should show: media-config, servarrs-setup, download-clients-setup
```

### 4. Check logs for API keys
```bash
journalctl -u media-config.service | grep -i apikey
# Should show only ***REDACTED***

journalctl -u servarrs-setup.service | grep -i apikey
# Should show only ***REDACTED***

journalctl -u download-clients-setup.service | grep -i apikey
# Should show only ***REDACTED***
```

### 5. Verify services start successfully
```bash
systemctl status media-config.service
systemctl status servarrs-setup.service
systemctl status download-clients-setup.service
systemctl status media-setup.service
```

### 6. Run smoketests
```bash
make smoketests  # or equivalent
# Verify all media services are reachable and configured
```

---

## Risk Assessment

### High Risk Areas
1. **Phase 2**: Merging logic from multiple services - must ensure no configuration is lost
2. **Phase 5**: Dependency rewiring - incorrect dependencies could prevent services from starting
3. **Phase 6**: Removing old services - must ensure all logic is moved first

### Mitigation
- Test each phase independently before moving to next
- Use `make check` to verify configuration builds before deploying
- Keep git history clean with one commit per phase for easy rollback
- Verify service startup with `systemctl status` after each deployment

### Rollback Plan
- Each phase should be a separate commit
- If a phase fails, `git revert` the specific commit
- Use `make rollback-ser8` to return to previous NixOS generation

---

## Summary

**Total Steps**: 39 steps across 7 phases
**Estimated Time**: 3-4 hours for full implementation
**Services Reduction**: 8 → 3 + 1 meta target
**New Capability**: API key sanitization in all logs

**Key Benefits**:
1. No API keys in systemd journal logs
2. Simpler service architecture (3 services vs 8)
3. Clearer dependency chain
4. Better error handling and logging
5. Maintained idempotency throughout
