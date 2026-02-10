# Testing Patterns

**Analysis Date:** 2026-02-09

## Test Framework

**Runner:**
- Bash scripts for all testing
- Smoketests: Post-deployment integration tests
- No unit test framework (this is infrastructure, not application code)
- Location: `scripts/smoketests/` organized by module (gateway, dns, media, nordvpn)

**Assertion Library:**
- Custom bash library: `scripts/lib/logging.sh`
- Functions: `pass()` for success, `fail()` for failure, `warn()` for warnings
- Color-coded output with status labels: `[info]`, `[WARN]`, `[FAIL]`, `[done]`

**Run Commands:**
```bash
make smoketests-HOST                    # Run smoketests for a host
make apply-HOST                         # Full deploy: build + test + switch + reboot + smoketests
./scripts/smoketests/gateway/all.sh firebat    # Run gateway tests directly
./scripts/smoketests/media/all.sh ser8         # Run media tests directly
./scripts/smoketests/dns/all.sh pi4            # Run DNS tests directly
./scripts/smoketests/nordvpn/all.sh ser8       # Run NordVPN tests directly
```

## Test File Organization

**Location:**
- `scripts/smoketests/` contains module-specific test suites
- Structure: `scripts/smoketests/<module>/all.sh` aggregates test cases
- Individual test files: `scripts/smoketests/<module>/test-<feature>.sh`

**Naming:**
- `all.sh`: Aggregate runner for a module's tests
- `test-<feature>.sh`: Individual test case
- Example structure:
  - `scripts/smoketests/gateway/all.sh` → runs test-caddy.sh, test-tailscale.sh
  - `scripts/smoketests/dns/all.sh` → runs test-dns.sh, test-dhcp.sh
  - `scripts/smoketests/media/all.sh` → aggregates tests via helper function

**Configuration:**
- Test definitions in `deploy.yaml` under `hosts.<hostname>.smoketests`
- Maps host to test script path: `smoketests: "./scripts/smoketests/gateway/all.sh"`
- Triggered by `make apply-HOST` after successful `make switch-HOST`

## Test Structure

**Suite Organization:**
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh               # Source common libraries
set -euo pipefail                     # Strict error handling

title "$0"                            # Print test suite name

# Parameter validation
if [ $# -lt 1 ]; then
    info "Usage: $0 <host>"
    exit 1
fi

# Extract host metadata
host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Define test functions
test_feature() {
    local param1="$1"
    info "testing feature: $param1"
    # ... test logic
    if condition; then
        pass "feature test passed"
    else
        fail "feature test failed"
        exit 1
    fi
}

# Run tests
test_feature "param"

# Final status
echo
pass "all tests passed"
```

**Example from `scripts/smoketests/dns/test-dns.sh`:**
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

. ./scripts/lib/all.sh
set -euo pipefail

title "$0"

if [ $# -lt 1 ]; then
    info "Usage: $0 <host>"
    exit 1
fi

host="$1"
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Define test function
resolves() {
    local domain="$1"
    local ipaddr="$2"

    info "check that '$(fmt_bold "$domain")' resolves"
    if nslookup "$domain" "$ipaddr"; then
        pass "resolved '$(fmt_bold "$domain")'"
    else
        fail "failed to resolve '$(fmt_bold "$domain")'"
    fi
}

# Run tests
if ! resolves google.com "$ipaddr"; then
    exit 1
fi

echo
pass "all tests passed"
```

**Patterns:**
- Setup: Extract host metadata (`ipaddr`, `user`) from `deploy.yaml` helpers
- Teardown: None explicitly (tests are read-only, no state changes)
- Assertion: Call `pass()` on success, `fail()` on failure, call `exit 1` if critical

## Mocking

**Framework:**
- No mocking framework; tests are end-to-end integration tests
- SSH used to verify remote behavior: `ssh "$user@$ipaddr" 'command'`
- Services tested via HTTP: `curl` with DNS resolution and Host headers
- No unit-level mocking; tests verify actual system state

**Patterns:**
- Fallback on DNS failure: Try DNS resolution, then use Host header, then use IP directly
- Retry logic: Curl with timeout flags for slow services
- Example from `scripts/smoketests/lib/services.sh`:
  ```bash
  # Try HTTPS first
  if error_output=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$domain:443:$ipaddr" "https://$domain" --connect-timeout 5 --max-time 10 2>&1); then
      response="$error_output"
      if [[ "$response" =~ ^[0-9]{3}$ ]]; then
          if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
              pass "HTTPS redirect for '$domain' responded with HTTP $response"
              return 0
          fi
      fi
  fi

  # Fallback to HTTP
  if error_output=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$domain:80:$ipaddr" "http://$domain" --connect-timeout 5 --max-time 10 2>&1); then
      ...
  fi
  ```

**What to Mock:**
- Remote verification: Use SSH to check service status
- DNS resolution: Test both DNS-based and Host header methods
- HTTP endpoints: Curl with flexible DNS strategies

**What NOT to Mock:**
- Service startup/shutdown (let real systemd handle it)
- Configuration loading (read real config files)
- Database/state changes (tests are read-only queries)

## Fixtures and Factories

**Test Data:**
- No fixtures; tests use real infrastructure (DNS, services, network)
- Service endpoints defined in test script arrays: `MEDIA_SERVICES`, `TESTS`, etc.
- Example from `scripts/smoketests/media/all.sh`:
  ```bash
  # format: "service_name:domain:port:systemd_service"
  MEDIA_SERVICES=(
      "Jellyfin:jellyfin.vofi:8096:jellyfin"
      "Sonarr:sonarr.vofi:8989:sonarr"
      "Radarr:radarr.vofi:7878:radarr"
      "qBittorrent:torrent.vofi:8080:qbittorrent"
      "Prowlarr:prowlarr.vofi:9696:prowlarr"
      "SABnzbd:sabnzbd.vofi:8085:sabnzbd"
  )
  ```

**Location:**
- Test service definitions inline in `all.sh` files
- Shared helper functions in `scripts/smoketests/lib/services.sh`
- Host metadata in `deploy.yaml`
- No separate fixture files

## Coverage

**Requirements:**
- No coverage targets enforced
- Manual testing via `make apply-HOST`
- Smoketests are gate-keepers for deployment

**View Coverage:**
```bash
# Coverage is implicit - run all tests for a host
make smoketests-HOST

# Or run a specific test suite
./scripts/smoketests/gateway/all.sh firebat -v
```

## Test Types

**Unit Tests:**
- Not used; this is infrastructure configuration
- Nix code validated by `nix flake check` which type-checks modules

**Integration Tests (Smoketests):**
- **Scope:** Verify that deployed services respond to network requests
- **Approach:** SSH into host, check systemd service status, curl HTTP endpoints
- **What they test:**
  - DNS resolution: `nslookup domain server`
  - HTTP connectivity: `curl` with DNS resolution and Host headers
  - Service routing: Verify Caddy routes reach correct upstream
  - Systemd status: `systemctl is-active --quiet service`
  - Backend health: Direct curl to localhost:port on host

**Examples:**
- `scripts/smoketests/gateway/test-caddy.sh`: Verifies Caddy routes via reverse proxy
- `scripts/smoketests/gateway/test-tailscale.sh`: Verifies Tailscale connectivity
- `scripts/smoketests/dns/test-dns.sh`: Verifies AdGuard DNS resolution
- `scripts/smoketests/media/all.sh`: Verifies all media services respond to HTTP
- `scripts/smoketests/nordvpn/test-qbittorrent.sh`: Verifies qBittorrent in VPN namespace

**E2E Tests:**
- Not explicitly defined
- `make apply-HOST` serves as full E2E pipeline: build → test → switch → reboot → smoketests
- Smoketests verify the entire deployment end-to-end

## Common Patterns

**Host Resolution:**
```bash
# Get IP from deploy.yaml
ipaddr=$(get_ip "$host")
user=$(get_user "$host")

# Resolve host: tries local IP, falls back to Tailscale
ssh "$user@$ipaddr" 'command'
```

**DNS Testing:**
```bash
# Test resolution via AdGuard DNS
dns_ipaddr=$(get_ip "pi4")
if ! nslookup "$domain" "$dns_ipaddr" >/dev/null 2>&1; then
    warn "DNS resolution failed, trying with Host header fallback"
fi
```

**HTTP Testing:**
```bash
# Try with DNS resolution
response=$(curl -k -s -o /dev/null -w "%{http_code}" --resolve "$domain:443:$ipaddr" "https://$domain" --connect-timeout 5 --max-time 10 2>&1)

# Try with Host header fallback
response=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "https://$ipaddr" --connect-timeout 5 --max-time 10 2>&1)

# Validate response code
if [[ "$response" =~ ^(200|301|302|404)$ ]]; then
    pass "HTTP response: $response"
fi
```

**Service Status Checking:**
```bash
# Check if systemd service is running
if ssh "$user@$ipaddr" 'systemctl is-active --quiet caddy'; then
    pass "caddy service is running"
else
    fail "caddy service is not running"
    exit 1
fi
```

**Error Diagnostic:**
```bash
# Determine if failure is due to gateway or backend
if test_service "$domain" "$service_name" "$port"; then
    pass "$service_name connectivity test passed"
else
    # Check if backend is reachable
    if ssh "$user@$ipaddr" "curl -s --connect-timeout 3 http://localhost:$port" >/dev/null 2>&1; then
        fail "upstream is reachable locally, issue with gateway routing"
    else
        fail "backend service is not running on $host"
    fi
    return 1
fi
```

**Array Iteration:**
```bash
# Define service list as colon-delimited strings
MEDIA_SERVICES=(
    "Jellyfin:jellyfin.vofi:8096:jellyfin"
    "Sonarr:sonarr.vofi:8989:sonarr"
)

# Parse and iterate
for service_config in "${MEDIA_SERVICES[@]}"; do
    IFS=':' read -r service_name domain port systemd_service <<<"$service_config"
    if test_media_service "$service_name" "$domain" "$port" "$systemd_service" "$host" "$ipaddr" "$user"; then
        pass "$service_name passed"
    else
        fail "$service_name failed"
        exit 1
    fi
done
```

## Nix Configuration Testing

**Validation:**
```bash
make check                    # Runs 'nix flake check' for all hosts
```

**What it validates:**
- Nix syntax correctness
- Module attribute type checking (via lib.mkOption declarations)
- No undefined references
- All imports resolve

**Building without deployment:**
```bash
make build-HOST               # Build config locally, don't deploy
make test-HOST                # Build and test activation (reverts on reboot)
make switch-HOST              # Build and make default boot config
```

## Library Functions

**Source in `scripts/lib/`:**

**logging.sh:**
- `info()` - Blue `[info]` label with yellow text
- `warn()` - Pink `[WARN]` label (to stderr)
- `pass()` - Green `[done]` label
- `fail()` - Red `[FAIL]` label (to stderr)
- `title()` - Blue header line
- `fmt_bold()`, `fmt_yellow()`, `fmt_red()` - Format individual strings

**all.sh:**
- Aggregates: `./scripts/lib/logging.sh`, `./scripts/lib/cleanup.sh`, `./scripts/lib/yq.sh`, `./scripts/lib/ssh.sh`, `./scripts/lib/prompt.sh`

**ssh.sh:**
- `resolve_ssh_host <hostname>` - Returns local IP or Tailscale hostname
- Tries local IP first (2s timeout), falls back to Tailscale if unreachable
- Caches preference in `.use_tailscale` file to avoid repeated timeouts

**services.sh (in smoketests/lib/):**
- `test_service <domain> <service_name> <port>` - Test HTTP connectivity with DNS fallback
- `test_media_service <name> <domain> <port> <systemd> <host> <ipaddr> <user>` - Full media service test with backend fallback

## Pre-commit and CI

**Flake validation:**
```bash
make check                    # Validates all Nix code
make fmt                      # Format all Nix files
```

**No automated CI:**
- Tests are manual via Makefile targets
- `make apply-HOST` is the full CI/CD pipeline for a single host

**Deployment order:**
1. `make build-HOST` - Type-check and build
2. `make test-HOST` - Activate and test (reverts on reboot)
3. `make switch-HOST` - Make boot default
4. `make reboot-HOST` - Reboot with new config
5. `make smoketests-HOST` - Verify services

---

*Testing analysis: 2026-02-09*
