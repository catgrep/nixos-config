# SABnzbd Integration: Architectural Analysis

## Executive Summary

This analysis examines the integration of SABnzbd, a Usenet download client, into an existing NixOS homelab media stack. The current system uses a modular architecture with qBittorrent (VPN-protected torrents), Prowlarr (indexer aggregator), Sonarr (TV), and Radarr (movies). SABnzbd will complement qBittorrent by providing Usenet download capabilities without VPN requirements, following established patterns for user management, secrets handling, and systemd orchestration.

**Key Findings:**
- Existing media modules follow consistent patterns for user/group creation, service configuration, and secrets management
- qBittorrent provides a reference architecture for download clients with VPN namespace support (SABnzbd won't need this)
- SOPS templates and systemd orchestration in hosts/ser8/media.nix show sophisticated configuration deployment
- SABnzbd integration requires category setup, API configuration, and Prowlarr/Sonarr/Radarr coordination

**Recommendation:** Implement SABnzbd as a new module following the established radarr.nix/sonarr.nix pattern, with configuration orchestration similar to qBittorrent but without VPN requirements.

---

## Current State Analysis

### User/Group Creation Patterns

**Pattern Location:** `modules/media/prowlarr.nix:21-35`, `modules/media/sonarr.nix:21-31`, `modules/media/radarr.nix:21-31`

All media services follow this pattern:
```nix
users.users.${cfg.user} = {
  isSystemUser = true;
  group = cfg.group;
  extraGroups = [ "media" ];
};

users.groups.${cfg.group} = { };
users.groups.media = { };
```

**Key Observations:**
- Each service has dedicated user/group (default: service name)
- All services join the shared "media" group for file permissions
- System users (not login users)
- Configurable via `cfg.user` and `cfg.group` options

### VPN Namespace Integration Pattern

**Pattern Location:** `modules/media/qbittorrent.nix:12-23`, `modules/media/prowlarr.nix:12-22`

Services that need VPN access use optional namespace binding:
```nix
options.services.qbittorrent.useVpnNamespace = mkOption {
  type = types.bool;
  default = false;
};

config = mkIf cfg.enable {
  systemd.services.qbittorrent = mkIf cfg.useVpnNamespace {
    bindsTo = [ "netns@nordvpn.service" ];
    after = [ "netns@nordvpn.service" ];
    serviceConfig.NetworkNamespacePath = "/var/run/netns/nordvpn";
  };
};
```

**Key Observation:** SABnzbd does NOT need VPN (Usenet traffic is already encrypted via SSL), so this pattern is not required.

### Secrets Management Pattern

**Pattern Location:** `hosts/ser8/media.nix:1-45`

Secrets are managed via SOPS with age encryption:
- Host keys: `secrets/keys/hosts/ser8/age.key`
- SOPS file: `secrets/ser8.yaml` (encrypted)
- Template rendering: `sops.templates` for config files with secrets

Example from qBittorrent configuration:
```nix
sops.secrets.qbittorrent_webui_password = {
  sopsFile = ../../secrets/ser8.yaml;
  owner = "qbittorrent";
  group = "qbittorrent";
  mode = "0440";
};

sops.templates."qBittorrent.conf" = {
  owner = "qbittorrent";
  group = "qbittorrent";
  mode = "0440";
  content = ''
    [Preferences]
    WebUI\Password_PBKDF2="${config.sops.placeholder.qbittorrent_webui_password}"
  '';
};
```

**Required Secrets for SABnzbd:**
1. Admin password (web UI authentication)
2. API key (for Sonarr/Radarr integration)
3. Usenet provider credentials (server, username, password, port, SSL)
4. NZB key (if using NZB indexers directly)

### SystemD Orchestration Pattern

**Pattern Location:** `hosts/ser8/media.nix:121-350`

Complex multi-service orchestration using custom systemd services:
- `arr-config.service`: Template-based configuration deployment
- `arr-qbittorrent-setup.service`: qBittorrent API configuration
- `arr-prowlarr-setup.service`: Prowlarr indexer sync

**Key Pattern Components:**
1. **Helper Library:** `systemd_helpers.sh` provides API interaction functions
2. **Service Dependencies:** `after`, `bindsTo`, `requisite` for startup ordering
3. **Retry Logic:** API polling with timeout/retry for service readiness
4. **Idempotency:** Check existing config before creating/updating

Example orchestration from `hosts/ser8/media.nix:202-263`:
```nix
systemd.services.arr-qbittorrent-setup = {
  description = "Configure qBittorrent for Sonarr/Radarr";
  after = [ "qbittorrent.service" ];
  requisite = [ "qbittorrent.service" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = ''
    # Wait for API, configure categories, set paths
  '';
};
```

### Download Path Conventions

**Pattern Location:** `hosts/ser8/configuration.nix:106` (MergerFS mount), `hosts/ser8/impermanence.nix:105-122` (directory structure)

Current path structure:
```
/mnt/media/             # MergerFS pool (two 12 TiB drives)
├── downloads/
│   ├── complete/      # qBittorrent complete downloads
│   ├── incomplete/    # qBittorrent incomplete downloads
│   ├── alldebrid/     # AllDebrid downloads
│   ├── tv/            # TV downloads staging
│   └── movies/        # Movie downloads staging
├── movies/            # Final movie storage
├── tv/                # Final TV storage
├── music/
└── books/
```

**Proposed SABnzbd Paths:**
```
/mnt/media/downloads/usenet/
├── incomplete/         # In-progress Usenet downloads
└── complete/           # Finished Usenet downloads
    ├── tv/            # Category: tv
    ├── movies/        # Category: movies
    └── default/       # Category: default/other
```

---

## SABnzbd Technical Requirements

### NixOS Service Configuration

**Module Location:** `nixpkgs/nixos/modules/services/networking/sabnzbd.nix` (upstream)

**Key Options:**
```nix
services.sabnzbd = {
  enable = true;
  user = "sabnzbd";
  group = "sabnzbd";
  configFile = "/path/to/sabnzbd.ini";  # Generated via SOPS template

  # Note: Upstream module may have limited options,
  # likely needs config file override approach
};
```

**Configuration File Format:** INI-style `sabnzbd.ini`

Critical sections:
- `[misc]`: host, port, api_key, web_username, web_password (hashed)
- `[servers]`: Usenet provider configuration (multiple servers supported)
- `[categories]`: Download categories (tv, movies, default)
- `[paths]`: download_dir, complete_dir, nzb_backup_dir

### API Authentication Requirements

**API Endpoints:**
- Base URL: `http://localhost:8080/sabnzbd/api`
- Authentication: API key in query parameter or header
- Key endpoints for integration:
  - `/api?mode=get_config` - Retrieve configuration
  - `/api?mode=get_cats` - List categories
  - `/api?mode=addfile` - Add NZB file
  - `/api?mode=queue` - Queue status

**Integration Flow:**
1. SABnzbd generates API key on first run (or set in config)
2. Prowlarr connects to SABnzbd API for download client testing
3. Sonarr/Radarr use API key to:
   - Send NZB files for download
   - Query download status
   - Manage queue

### Port Requirements

**Default Ports:**
- HTTP: 8080
- HTTPS: 9090 (optional, using reverse proxy instead)

**Firewall Rules:** Only localhost access needed (reverse proxy via Caddy on firebat handles external access)

### Usenet Provider Integration

**Required Provider Information:**
- Server hostname (e.g., `news.provider.com`)
- Port (typically 563 for SSL, 119 for plain)
- SSL enabled (strongly recommended)
- Username and password
- Connection count (typically 8-30 per provider)
- Priority (for multiple providers)

**Common Providers:** Newshosting, UsenetServer, Easynews, Frugal Usenet, etc.

---

## Proposed Architecture

### Module Structure

**File:** `modules/media/sabnzbd.nix`

**Pattern:** Follow `modules/media/radarr.nix` structure (simpler than qBittorrent, no VPN needed)

**Key Components:**
1. **Options:** `services.sabnzbd.enable`, `user`, `group`, `dataDir`
2. **User/Group Creation:** Standard pattern with `media` group membership
3. **Service Configuration:** SystemD service pointing to SOPS-generated config
4. **Firewall:** Open port 8080 for localhost-only access

**Reference Implementation Pattern:** `modules/media/radarr.nix:1-48`

### User/Group Configuration

**Pattern:** Identical to Sonarr/Radarr

```nix
users.users.sabnzbd = {
  isSystemUser = true;
  group = "sabnzbd";
  extraGroups = [ "media" ];
};

users.groups.sabnzbd = { };
users.groups.media = { };  # Shared with all media services
```

**Permissions Strategy:**
- SABnzbd runs as `sabnzbd:sabnzbd`
- Downloads written to `/mnt/media/downloads/usenet/` with `sabnzbd:media` ownership
- Sonarr/Radarr (in `media` group) can read completed downloads
- Post-processing moves files to `/mnt/media/` (tv/, movies/) with `media:media` ownership

### Download Path Organization

**Storage Location:** Use existing MergerFS mount at `/mnt/media`

The `/mnt/media` filesystem is a MergerFS pool backed by two 12 TiB drives dedicated to media storage. No new ZFS dataset creation is needed.

**Directory Structure:** Add to `hosts/ser8/impermanence.nix:105-122`

```nix
# SABnzbd Usenet downloads
"d /mnt/media/downloads/usenet 0775 sabnzbd media -"
"d /mnt/media/downloads/usenet/incomplete 0775 sabnzbd media -"
"d /mnt/media/downloads/usenet/complete 0775 sabnzbd media -"
"d /mnt/media/downloads/usenet/complete/tv 0775 sabnzbd media -"
"d /mnt/media/downloads/usenet/complete/movies 0775 sabnzbd media -"
"d /mnt/media/downloads/usenet/complete/default 0775 sabnzbd media -"
```

**Complete Path Structure:**
```
/mnt/media/downloads/usenet/
├── incomplete/         # Active downloads (sabnzbd writes here)
└── complete/           # Finished downloads
    ├── tv/            # Category: tv
    ├── movies/        # Category: movies
    └── default/       # Category: default/other
```

**Ownership:** All directories `sabnzbd:media` with `0775` permissions

### Secrets Configuration

**SOPS Secrets:** Add to `secrets/ser8.yaml`

Required secrets:
```yaml
sabnzbd_admin_password: "<bcrypt-hash-or-plaintext>"
sabnzbd_api_key: "<random-32-char-hex>"
sabnzbd_nzb_key: "<random-32-char-hex>"
sabnzbd_usenet_server: "news.provider.com"
sabnzbd_usenet_username: "<username>"
sabnzbd_usenet_password: "<password>"
sabnzbd_usenet_port: "563"
sabnzbd_usenet_connections: "20"
```

**SOPS Template:** `hosts/ser8/media.nix:46-80` pattern

```nix
sops.templates."sabnzbd.ini" = {
  owner = "sabnzbd";
  group = "sabnzbd";
  mode = "0440";
  content = ''
    [misc]
    host = 0.0.0.0
    port = 8080
    api_key = ${config.sops.placeholder.sabnzbd_api_key}
    nzb_key = ${config.sops.placeholder.sabnzbd_nzb_key}

    [servers]
    [[${config.sops.placeholder.sabnzbd_usenet_server}]]
    host = ${config.sops.placeholder.sabnzbd_usenet_server}
    port = ${config.sops.placeholder.sabnzbd_usenet_port}
    username = ${config.sops.placeholder.sabnzbd_usenet_username}
    password = ${config.sops.placeholder.sabnzbd_usenet_password}
    connections = ${config.sops.placeholder.sabnzbd_usenet_connections}
    ssl = 1
    ssl_verify = 2
    enable = 1

    [categories]
    [[tv]]
    name = tv
    dir = tv
    [[movies]]
    name = movies
    dir = movies
  '';
};
```

### SystemD Service Orchestration

**New Service:** `arr-sabnzbd-setup.service`

**Pattern:** Similar to `arr-qbittorrent-setup.service` (`hosts/ser8/media.nix:202-263`)

**Responsibilities:**
1. Wait for SABnzbd API readiness
2. Verify category configuration (tv, movies)
3. Export API key to standardized location for other services
4. Validate Usenet server connectivity

**Dependencies:**
- `after = [ "sabnzbd.service" ]`
- `requisite = [ "sabnzbd.service" ]`
- `wantedBy = [ "multi-user.target" ]`

**Script Structure:**
```bash
#!/usr/bin/env bash
source ${systemd_helpers_script}

wait_for_api "http://localhost:8080/sabnzbd/api?mode=version&apikey=$API_KEY" 300

# Verify categories exist
check_category "tv"
check_category "movies"

# Test Usenet server connection
verify_server_connectivity
```

---

## Integration Points

### Prowlarr Integration

**Existing Pattern:** `hosts/ser8/media.nix:265-350` (Prowlarr setup service)

**Download Client Configuration:**
Prowlarr needs SABnzbd added as a download client for Usenet indexers:
- Name: "SABnzbd"
- Host: `localhost`
- Port: `8080`
- API Key: From SOPS secret
- Category: Map by indexer type (TV → tv, Movies → movies)

**Implementation Approach:**
Extend `arr-prowlarr-setup.service` to add SABnzbd download client via Prowlarr API:
```bash
# Check if SABnzbd download client exists
EXISTING_CLIENT=$(curl -s "http://localhost:9696/api/v1/downloadclient" \
  -H "X-Api-Key: $PROWLARR_API_KEY" | jq '.[] | select(.name == "SABnzbd")')

if [ -z "$EXISTING_CLIENT" ]; then
  # Add SABnzbd download client
  curl -X POST "http://localhost:9696/api/v1/downloadclient" \
    -H "X-Api-Key: $PROWLARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "SABnzbd",
      "implementation": "Sabnzbd",
      "configContract": "SabnzbdSettings",
      "fields": [
        {"name": "host", "value": "localhost"},
        {"name": "port", "value": 8080},
        {"name": "apiKey", "value": "'$SABNZBD_API_KEY'"}
      ]
    }'
fi
```

### Sonarr/Radarr Integration

**Existing Pattern:** Sonarr/Radarr manually configured via Web UI or need automation

**Download Client Addition:**
Both Sonarr and Radarr need SABnzbd configured:
- Settings → Download Clients → Add → SABnzbd
- Host: `localhost`
- Port: `8080`
- API Key: From SOPS
- Category: `tv` (Sonarr), `movies` (Radarr)
- Remove completed downloads: Yes (let *arr apps manage import)

**Automated Configuration:**
Create new services `arr-sonarr-sabnzbd-setup.service` and `arr-radarr-sabnzbd-setup.service`:

Reference pattern: `hosts/ser8/media.nix:202-263`

```bash
# Sonarr API endpoint: /api/v3/downloadclient
# Radarr API endpoint: /api/v3/downloadclient

# Check if SABnzbd download client exists
EXISTING=$(curl -s "http://localhost:8989/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_API_KEY" | jq '.[] | select(.name == "SABnzbd")')

if [ -z "$EXISTING" ]; then
  curl -X POST "http://localhost:8989/api/v3/downloadclient" \
    -H "X-Api-Key: $SONARR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "enable": true,
      "name": "SABnzbd",
      "implementation": "Sabnzbd",
      "configContract": "SabnzbdSettings",
      "fields": [
        {"name": "host", "value": "localhost"},
        {"name": "port", "value": 8080},
        {"name": "apiKey", "value": "'$SABNZBD_API_KEY'"},
        {"name": "tvCategory", "value": "tv"}
      ],
      "priority": 1
    }'
fi
```

### Category Setup

**Categories Required:**
1. **tv**: For Sonarr (TV show downloads)
2. **movies**: For Radarr (movie downloads)
3. **default**: For manual/uncategorized downloads

**Path Mapping:**
- Category `tv` → `/mnt/media/downloads/usenet/complete/tv/`
- Category `movies` → `/mnt/media/downloads/usenet/complete/movies/`
- Category `default` → `/mnt/media/downloads/usenet/complete/default/`

**Post-Processing:**
SABnzbd configured to:
- Verify downloaded files (par2 check)
- Unpack archives (unrar)
- Delete obfuscated files (.nfo, .txt cleanup)
- Set permissions: `0664` (files), `0775` (dirs)
- Notify *arr apps via API callback when complete

### Service Startup Ordering

**Dependency Chain:**
```
1. sabnzbd.service (base service)
2. arr-sabnzbd-setup.service (verify SABnzbd ready, export secrets)
3. arr-sonarr-sabnzbd-setup.service (configure Sonarr)
4. arr-radarr-sabnzbd-setup.service (configure Radarr)
5. arr-prowlarr-setup.service (updated to include SABnzbd)
```

**SystemD Configuration:**
```nix
systemd.services.arr-sonarr-sabnzbd-setup = {
  after = [ "sonarr.service" "arr-sabnzbd-setup.service" ];
  requisite = [ "sonarr.service" "sabnzbd.service" ];
  wants = [ "arr-sabnzbd-setup.service" ];
};
```

---

## Implementation Steps

### Phase 1: Base Module Creation
1. Create `modules/media/sabnzbd.nix` following radarr.nix pattern
2. Define options: `enable`, `user`, `group`, `dataDir`, `port`
3. Configure user/group creation with `media` group membership
4. Set up systemd service with basic configuration
5. Add firewall rules for localhost access

**Reference Files:**
- Pattern: `modules/media/radarr.nix:1-48`
- User creation: `modules/media/sonarr.nix:21-31`

### Phase 2: Storage Configuration
1. Add SABnzbd directory structure to `hosts/ser8/impermanence.nix:105-122`
2. Create directories under `/mnt/media/downloads/usenet/`
3. Set up proper ownership and permissions (sabnzbd:media, 0775)
4. Verify directories are created on boot via systemd-tmpfiles

**Reference Files:**
- Impermanence directory structure: `hosts/ser8/impermanence.nix:105-122`
- Existing download paths: `hosts/ser8/media.nix:194-195, 422`

### Phase 3: Secrets Management
1. Add SABnzbd secrets to `secrets/ser8.yaml`:
   - `sabnzbd_api_key`
   - `sabnzbd_nzb_key`
   - `sabnzbd_admin_password`
   - Usenet provider credentials (server, username, password, port)
2. Create SOPS template for `sabnzbd.ini` in `hosts/ser8/media.nix`
3. Configure template ownership and permissions
4. Test secret decryption and file generation

**Reference Files:**
- SOPS secrets: `hosts/ser8/media.nix:1-45`
- Template pattern: `hosts/ser8/media.nix:46-80`

### Phase 4: Service Orchestration
1. Create `arr-sabnzbd-setup.service` for initialization
2. Implement API readiness check using helper functions
3. Verify category configuration
4. Export API key for consumption by other services
5. Add service to startup dependencies

**Reference Files:**
- Orchestration pattern: `hosts/ser8/media.nix:202-263`
- Helper functions: Referenced in `hosts/ser8/media.nix:121` (systemd_helpers.sh)

### Phase 5: Integration Services
1. Create `arr-sonarr-sabnzbd-setup.service`
   - Configure SABnzbd as Sonarr download client
   - Set category to "tv"
   - Enable and test connection
2. Create `arr-radarr-sabnzbd-setup.service`
   - Configure SABnzbd as Radarr download client
   - Set category to "movies"
   - Enable and test connection
3. Update `arr-prowlarr-setup.service`
   - Add SABnzbd as download client in Prowlarr
   - Configure category mapping by indexer type

**Reference Files:**
- Service pattern: `hosts/ser8/media.nix:265-350`
- API interaction: systemd_helpers.sh (referenced in media.nix)

### Phase 6: Reverse Proxy Configuration
1. Update Caddy configuration on firebat to add SABnzbd route
2. Add `sabnzbd.vofi` domain pointing to ser8:8080
3. Configure SSL certificate via Caddy's local CA
4. Test external access through reverse proxy

**Reference Files:**
- Caddy config: `modules/gateway/caddy.nix` or `hosts/firebat/configuration.nix`
- Existing service routes: Check Caddy config for jellyfin, sonarr, radarr patterns

### Phase 7: Testing and Validation
1. Create smoketests in `scripts/smoketests/sabnzbd-test.sh`
2. Test API accessibility
3. Verify category configuration
4. Test NZB download workflow (manual upload)
5. Verify Sonarr/Radarr integration (trigger search, download)
6. Validate file permissions and ownership
7. Check post-processing (unrar, cleanup)

**Reference Files:**
- Smoketest pattern: `scripts/smoketests/` directory
- Test framework: Existing media service tests

---

## Security Considerations

### VPN Requirements

**Key Decision:** SABnzbd does NOT require VPN protection

**Rationale:**
- Usenet traffic is already encrypted via SSL/TLS (port 563)
- No peer-to-peer exposure like BitTorrent
- Legal risk profile significantly lower than torrents
- ISP cannot see content, only that you're connecting to Usenet server

**Implementation:** Do NOT add `useVpnNamespace` option (unlike qBittorrent pattern in `modules/media/qbittorrent.nix:12-23`)

### Secrets Protection

**Threat Model:**
- API key exposure allows full control of SABnzbd
- Usenet credentials give access to paid Usenet account
- Admin password protects web UI access

**Mitigations:**
1. SOPS encryption for all secrets (age-based)
2. File permissions: 0440 for config files (owner:group read-only)
3. User isolation: sabnzbd system user, no login shell
4. Localhost-only binding for API (reverse proxy for external access)
5. Strong random API keys (32+ character hex strings)

**Reference:** `hosts/ser8/media.nix:1-45` (SOPS pattern)

### Network Isolation

**Current Setup:**
- SABnzbd binds to `0.0.0.0:8080` (all interfaces)
- Firewall should restrict to localhost only
- External access via Caddy reverse proxy on firebat

**Best Practice:**
Consider binding to `127.0.0.1:8080` instead of `0.0.0.0:8080` for defense-in-depth

### File System Permissions

**Permission Strategy:**
- `/mnt/media/downloads/usenet/`: `sabnzbd:media` with `0775`
- Downloaded files: `0664` (read/write for owner/group)
- Downloaded directories: `0775` (traverse for group)
- Config files: `0440` (read-only for sabnzbd user)

**Validation:**
All media service users (sonarr, radarr) in `media` group can read completed downloads but cannot interfere with active downloads (only sabnzbd user writes)

### API Security

**Considerations:**
1. API key required for all operations (no anonymous access)
2. NZB key separate from API key (for RSS feeds)
3. No default credentials (all set via SOPS)
4. Rate limiting: Consider Caddy rate limiting on reverse proxy
5. Authentication logs: Enable SABnzbd access logging

---

## Testing Strategy

### Unit Testing

**Module Validation:**
1. Run `make check` to validate Nix syntax and module evaluation
2. Verify user/group creation: `id sabnzbd`
3. Check file permissions: `ls -la /mnt/media/downloads/usenet/`
4. Validate SOPS template generation: `cat /run/secrets-rendered/sabnzbd.ini`

**Reference:** `Makefile` targets for validation

### Integration Testing

**Service Startup:**
1. Verify service starts: `systemctl status sabnzbd.service`
2. Check API accessibility: `curl http://localhost:8080/sabnzbd/api?mode=version&apikey=<key>`
3. Validate categories: `curl http://localhost:8080/sabnzbd/api?mode=get_cats&apikey=<key>`
4. Test Usenet server connection via SABnzbd web UI

**Orchestration:**
1. Verify setup service completes: `systemctl status arr-sabnzbd-setup.service`
2. Check Sonarr integration: `systemctl status arr-sonarr-sabnzbd-setup.service`
3. Check Radarr integration: `systemctl status arr-radarr-sabnzbd-setup.service`
4. Validate Prowlarr download client: Web UI → Download Clients

### End-to-End Testing

**Download Workflow:**
1. **Manual Test:** Upload test NZB file via SABnzbd web UI
   - Verify download starts
   - Check incomplete directory has files
   - Wait for completion
   - Verify files moved to complete/default/
   - Check file permissions (0664, sabnzbd:media)

2. **Sonarr Test:** Search for TV episode in Sonarr
   - Trigger automatic search
   - Verify Prowlarr returns Usenet indexers
   - Confirm Sonarr sends NZB to SABnzbd
   - Monitor SABnzbd queue
   - Wait for completion
   - Verify Sonarr imports episode to /mnt/media/tv/

3. **Radarr Test:** Search for movie in Radarr
   - Same workflow as Sonarr but for movies
   - Verify import to /mnt/media/movies/

**Validation Points:**
- API calls succeed (200 responses)
- Categories correctly applied
- File permissions preserved through pipeline
- Post-processing successful (unrar, cleanup)
- *arr apps successfully import files
- No permission errors in logs

### Smoketest Implementation

**Script Location:** `scripts/smoketests/sabnzbd-test.sh`

**Test Cases:**
```bash
#!/usr/bin/env bash
# Test SABnzbd availability
test_sabnzbd_api() {
  curl -f http://ser8.local:8080/sabnzbd/api?mode=version || return 1
}

# Test category configuration
test_sabnzbd_categories() {
  CATS=$(curl -s http://localhost:8080/sabnzbd/api?mode=get_cats&apikey=$API_KEY)
  echo "$CATS" | grep -q "tv" || return 1
  echo "$CATS" | grep -q "movies" || return 1
}

# Test Sonarr integration
test_sonarr_sabnzbd_client() {
  CLIENTS=$(curl -s http://localhost:8989/api/v3/downloadclient -H "X-Api-Key: $SONARR_KEY")
  echo "$CLIENTS" | grep -q "SABnzbd" || return 1
}

# Run all tests
run_tests test_sabnzbd_api test_sabnzbd_categories test_sonarr_sabnzbd_client
```

**Reference:** `scripts/smoketests/` directory for existing patterns

### Regression Testing

**Scenarios:**
1. **Rebuild Test:** `make build-ser8` should succeed without errors
2. **Config Change:** Modify secret, redeploy, verify no service disruption
3. **Rollback Test:** `make rollback-ser8` should restore previous state
4. **Upgrade Test:** Update nixpkgs, rebuild, verify SABnzbd still works

---

## Risks and Mitigations

### Risk 1: SABnzbd Configuration Drift

**Description:** Manual changes to SABnzbd config via web UI not reflected in Nix configuration

**Impact:** Configuration lost on service restart or system rebuild

**Likelihood:** Medium (users may tweak settings via UI)

**Mitigation:**
1. Use SOPS template for all critical config values
2. Document that manual changes are ephemeral
3. Set SABnzbd config file to read-only after generation (via systemd ExecStartPre)
4. Consider warning banner in web UI (if possible)

### Risk 2: API Key Exposure

**Description:** API keys logged or exposed in process listings

**Impact:** Unauthorized access to SABnzbd, potential account abuse

**Likelihood:** Low (proper SOPS usage prevents this)

**Mitigation:**
1. Never pass API keys as command-line arguments (use environment variables or config files)
2. Ensure SOPS templates have correct permissions (0440)
3. Review systemd service logs for accidental key logging
4. Use secret scanning tools (e.g., `git-secrets`, `trufflehog`)

### Risk 3: Download Path Conflicts

**Description:** SABnzbd and qBittorrent writing to same paths causing file corruption

**Impact:** Failed downloads, data loss, permission issues

**Likelihood:** Low (separate paths proposed)

**Mitigation:**
1. Use completely separate directory trees (`/mnt/media/downloads/usenet/` vs `/mnt/media/downloads/complete/` and `/mnt/media/downloads/incomplete/`)
2. Enforce via configuration (hardcoded in SOPS template)
3. Document path conventions clearly
4. Add validation in setup service to check paths are distinct

### Risk 4: Incomplete Usenet Provider Configuration

**Description:** Missing or incorrect Usenet server credentials prevent downloads

**Impact:** SABnzbd appears to work but downloads fail silently

**Likelihood:** Medium (manual secret entry required)

**Mitigation:**
1. Add validation in `arr-sabnzbd-setup.service` to test server connectivity
2. Check for common misconfigurations (wrong port, SSL mismatch)
3. Provide clear error messages in logs
4. Document Usenet provider setup in README or comments
5. Test with multiple providers if available (failover)

### Risk 5: Post-Processing Failures

**Description:** SABnzbd fails to unpack/verify downloads due to missing tools

**Impact:** Downloads complete but remain packed, *arr apps cannot import

**Likelihood:** Low (NixOS packages should include dependencies)

**Mitigation:**
1. Verify SABnzbd package includes `unrar`, `par2cmdline`, `p7zip`
2. Test post-processing with sample NZB containing archives
3. Enable detailed logging for post-processing
4. Add smoketest to validate unrar functionality

### Risk 6: Service Startup Race Conditions

**Description:** Integration services run before SABnzbd API is fully ready

**Impact:** Setup services fail, requiring manual configuration or retry

**Likelihood:** Medium (common with complex startup dependencies)

**Mitigation:**
1. Use robust API polling with timeout/retry in helper functions
2. Add explicit `after` and `requisite` systemd dependencies
3. Set reasonable timeouts (300 seconds per service)
4. Log detailed startup sequence for debugging
5. Consider `RestartSec` and `Restart=on-failure` for transient failures

**Reference:** `hosts/ser8/media.nix:202-263` (existing retry logic in qBittorrent setup)

### Risk 7: Secrets Not Properly Rotated

**Description:** API keys or Usenet passwords become stale or compromised

**Impact:** Service outage or security breach

**Likelihood:** Low (secrets management is manual)

**Mitigation:**
1. Document secret rotation procedure in README
2. Use SOPS age key encryption tied to host keys (automatic on rebuild)
3. Implement monitoring for failed authentication (Prometheus/Grafana)
4. Set calendar reminder for periodic secret rotation (e.g., every 6 months)
5. Test secret update procedure during initial deployment

---

## Implementation Checklist

### Pre-Implementation
- [ ] Review existing media service configurations (prowlarr, sonarr, radarr, qbittorrent)
- [ ] Obtain Usenet provider credentials (server, port, username, password)
- [ ] Generate random API key and NZB key (32+ character hex strings)
- [ ] Verify SABnzbd package exists in nixpkgs and check available options

### Module Development
- [ ] Create `modules/media/sabnzbd.nix` with basic structure
- [ ] Define module options (enable, user, group, dataDir, port)
- [ ] Implement user/group creation with `media` group membership
- [ ] Configure systemd service with dependencies
- [ ] Add localhost firewall rules

### Storage Setup
- [ ] Add SABnzbd directory structure to `hosts/ser8/impermanence.nix`
- [ ] Create `/mnt/media/downloads/usenet/` directory tree with subdirectories
- [ ] Set ownership to `sabnzbd:media` with proper permissions (0775)
- [ ] Verify systemd-tmpfiles creates directories on boot

### Secrets Configuration
- [ ] Add all SABnzbd secrets to `secrets/ser8.yaml`
- [ ] Encrypt with SOPS age encryption
- [ ] Create SOPS template for `sabnzbd.ini` in `hosts/ser8/media.nix`
- [ ] Test secret decryption and template rendering
- [ ] Verify file permissions on generated config

### Service Orchestration
- [ ] Create `arr-sabnzbd-setup.service` for initialization
- [ ] Implement API readiness check with timeout/retry
- [ ] Verify category configuration (tv, movies, default)
- [ ] Test Usenet server connectivity
- [ ] Add service to dependency chain

### Integration Development
- [ ] Create `arr-sonarr-sabnzbd-setup.service`
- [ ] Create `arr-radarr-sabnzbd-setup.service`
- [ ] Update `arr-prowlarr-setup.service` to include SABnzbd
- [ ] Test API interactions with each service
- [ ] Verify idempotency (repeated runs don't cause errors)

### Reverse Proxy Configuration
- [ ] Add SABnzbd route to Caddy configuration on firebat
- [ ] Configure `sabnzbd.vofi` domain with SSL certificate
- [ ] Test external access through reverse proxy
- [ ] Verify authentication works through proxy

### Testing
- [ ] Create smoketest script `scripts/smoketests/sabnzbd-test.sh`
- [ ] Test manual NZB upload and download
- [ ] Test Sonarr automatic search and download
- [ ] Test Radarr automatic search and download
- [ ] Verify file permissions throughout pipeline
- [ ] Check logs for errors or warnings
- [ ] Run `make check` and `make build-ser8`

### Documentation
- [ ] Update `CLAUDE.md` with SABnzbd details
- [ ] Document Usenet provider configuration
- [ ] Add SABnzbd to service access section
- [ ] Document secret rotation procedure
- [ ] Add smoketest to `deploy.yaml` (if applicable)

### Deployment
- [ ] Deploy to ser8 with `make switch-ser8`
- [ ] Monitor service startup and logs
- [ ] Run smoketests
- [ ] Perform end-to-end workflow test
- [ ] Document any issues or deviations

---

## Conclusion

SABnzbd integration follows established patterns in the codebase with minimal deviation. The primary additions are:

1. **New module:** `modules/media/sabnzbd.nix` (follows radarr/sonarr pattern)
2. **Storage layer:** `/mnt/media/downloads/usenet/` directories on existing MergerFS pool
3. **Secrets:** SOPS-encrypted configuration template
4. **Orchestration:** Three new systemd setup services for integration
5. **Reverse proxy:** Caddy route for external access

The architecture maintains consistency with existing media services while properly isolating Usenet downloads from torrent downloads within the shared `/mnt/media` MergerFS pool. No VPN integration is required due to Usenet's inherent SSL encryption, simplifying the design compared to qBittorrent.

**Key Success Factors:**
- Follow existing patterns exactly (don't reinvent)
- Robust API polling with timeouts
- Comprehensive testing at each layer
- Clear documentation of secret management
- Idempotent configuration scripts

**Next Steps:**
1. Start with Phase 1 (base module creation)
2. Incrementally test each phase before proceeding
3. Use existing services as reference implementations
4. Document deviations or issues encountered

This analysis provides the architectural foundation for a full implementation plan. The actual implementation should proceed phase-by-phase with validation at each step.
