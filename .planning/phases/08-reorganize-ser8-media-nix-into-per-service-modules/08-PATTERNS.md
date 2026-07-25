# Phase 8: Reorganize ser8 media.nix into per-service modules - Pattern Map

**Mapped:** 2026-07-25
**Files analyzed:** 28 concrete or conditionally modified files
**Analogs found:** 26 / 28

## Scope Notes

The current `hosts/ser8/media.nix` is the exact behavioral source for secrets, templates, deployment order, orchestration units, and target wiring.
The new host modules should move those definitions intact before performing the separately approved cleanup.
The current worktree already adds `jellyfin_sawnia_password` at `hosts/ser8/media.nix:32`, so the baseline must include that declaration even though the evaluated household user does not yet exist.

The research proposes two Wave 0 validation artifacts but does not lock their paths.
They are classified below as `<parity projection>` and `<parity check>` so the planner can select lowercase kebab-case paths without inventing a permanent interface prematurely.

The D-22 audit covers every current `modules/media/*.nix` file.
Rows marked `audit-only` should be modified only when the audit finds commented-out or genuinely dead code.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `hosts/ser8/configuration.nix` | config | transform | `hosts/ser8/configuration.nix:11-15` | exact |
| `hosts/ser8/media.nix` (delete after extraction) | config | transform | self | exact source |
| `hosts/ser8/media/default.nix` | config | transform | `modules/automation/default.nix:3-10` | role-match |
| `hosts/ser8/media/sops.nix` | config | file-I/O | `hosts/ser8/media.nix:10-18` | exact source |
| `hosts/ser8/media/jellyfin.nix` | config | file-I/O + event-driven | `modules/media/jellyfin.nix:22-96` plus `hosts/ser8/media.nix:18-42,500-505` | exact composite source |
| `hosts/ser8/media/sonarr.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:44-49,72-76,150-172,566` | exact source, new composition |
| `hosts/ser8/media/radarr.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:51-56,78-82,174-196,567` | exact source, new composition |
| `hosts/ser8/media/prowlarr.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:84-95,198-220,568` | exact source, new composition |
| `hosts/ser8/media/qbittorrent.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:58-69,225-272,572-591` | exact source, new composition |
| `hosts/ser8/media/nzbget.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:426-492,569` | exact source, new composition |
| `hosts/ser8/media/sabnzbd.nix` | config | file-I/O + event-driven | `hosts/ser8/media.nix:110-145,274-424,496-498,570` | exact source, new composition |
| `hosts/ser8/media/orchestration.nix` | config | event-driven + request-response | `hosts/ser8/media.nix:539-738` | exact source |
| `hosts/ser8/media/deployment-helpers.sh` | utility | file-I/O | `hosts/ser8/systemd_helpers.sh:64-110` | exact source |
| `hosts/ser8/media/orchestration-helpers.sh` | utility | request-response | `hosts/ser8/systemd_helpers.sh:6-63,112-531` | exact source |
| `modules/media/default.nix` | config | transform | `modules/automation/default.nix:3-10` | exact role |
| `modules/media/jellyfin.nix` | config | transform | self, with host policy removed | exact source |
| `modules/media/jellyfin-exporter.nix` | provider | event-driven | option boundary in `modules/media/qbittorrent.nix:15-47` | role-match |
| `modules/media/exportarr.nix` (delete after extraction) | config | event-driven | self | exact source |
| `modules/media/alldebrid-proxy.nix` (delete) | config | event-driven | self | exact source |
| `modules/media/transmission.nix` (conditional delete) | config | event-driven | self | exact source |
| `modules/media/sonarr.nix` (audit-only) | provider | event-driven | self | exact source |
| `modules/media/radarr.nix` (audit-only) | provider | event-driven | self | exact source |
| `modules/media/prowlarr.nix` (audit-only) | provider | event-driven | self | exact source |
| `modules/media/qbittorrent.nix` (audit-only) | provider | event-driven | self | exact source |
| `modules/media/sabnzbd.nix` (audit-only) | provider | event-driven | self | exact source |
| `modules/media/nzbget.nix` (audit-only) | provider | event-driven | self | exact source |
| `<parity projection>.nix` | test | batch + transform | none | no analog |
| `<parity check>.sh` | test | batch | `scripts/smoketests/nordvpn/all.sh:1-13` | partial runner analog only |

## Pattern Assignments

### `hosts/ser8/media/default.nix` (config, transform)

**Analog:** `modules/automation/default.nix`

**Import-only pattern** (`modules/automation/default.nix:1-10`):

```nix
# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./home-assistant.nix
    ./frigate.nix
    ./frigate-exporter.nix
  ];
}
```

Copy the shape, replace the import list with `sops.nix`, all seven active service modules, and `orchestration.nix`, and add no options or configuration to this entry point.
List imports for discoverability, but do not rely on their order to compose `media-config.script`.

### `hosts/ser8/media/sops.nix` (config, file-I/O)

**Analog:** `hosts/ser8/media.nix`

**Shared SOPS defaults** (`hosts/ser8/media.nix:10-18`):

```nix
sops = {
  defaultSopsFile = ../../secrets/ser8.yaml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  secrets = {
```

Move only `defaultSopsFile`, `defaultSopsFormat`, and `age.sshKeyPaths` into the shared module.
Because the file moves one directory deeper, the secret path becomes `../../../secrets/ser8.yaml`.
Do not move individual secret declarations here because D-07 assigns those to service owners.

### Arr host modules: `sonarr.nix`, `radarr.nix`, and `prowlarr.nix`

**Primary analog:** The corresponding exact slices in `hosts/ser8/media.nix`.

**Module and secret pattern** (`hosts/ser8/media.nix:44-49,72-76`):

```nix
"sonarr_admin_password" = {
  owner = "root";
  group = "root";
  mode = "0600";
};

"sonarr_api_key" = {
  owner = "root";
  group = "root";
  mode = "0600";
};
```

**Template validation pattern** (`hosts/ser8/media.nix:150-172`):

```nix
"sonarr-config.xml" = {
  content = ''
    <Config>
      <AuthenticationMethod>Forms</AuthenticationMethod>
      <Password>${config.sops.placeholder."sonarr_admin_password"}</Password>
      <ApiKey>${config.sops.placeholder."sonarr_api_key"}</ApiKey>
    </Config>
  '';
  owner = "sonarr";
  group = "sonarr";
  mode = "0600";
};
```

Preserve the complete existing XML content rather than copying only this abbreviated excerpt.

**Host-owned exporter wiring** (`modules/media/exportarr.nix:14-22`):

```nix
services.prometheus.exporters.exportarr-sonarr = {
  enable = lib.mkDefault true;
  port = 9707;
  url = "http://localhost:8989";
  apiKeyFile = config.sops.secrets.sonarr_api_key.path;
  openFirewall = true;
};
```

Use the corresponding Radarr values from `modules/media/exportarr.nix:24-31` and Prowlarr values from `modules/media/exportarr.nix:33-40`.
Each file also moves its enablement and host settings from `hosts/ser8/configuration.nix:211-216`.

**Ordered contribution pattern:** No repository analog exists for multiple modules contributing ordered `types.lines` values.
Use the research-verified native merge technique:

```nix
systemd.services.media-config = {
  before = lib.mkOrder 200 [ "sonarr.service" ];
  script = lib.mkOrder 200 ''
    configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}
  '';
};
```

Use script orders 200 for Sonarr, 300 for Radarr, and 400 for Prowlarr.
Assign explicit ordering to every fragment and separately preserve the existing `before` dependency list.

### `hosts/ser8/media/qbittorrent.nix` (config, file-I/O + event-driven)

**Analog:** `hosts/ser8/media.nix` with the host nginx block from `hosts/ser8/configuration.nix`.

**Service and host policy** (`hosts/ser8/configuration.nix:217-220,232-269`):

```nix
services.qbittorrent-nox = {
  enable = true;
  openFirewall = false;
  useVpnNamespace = true;
};

services.nginx.virtualHosts."qbittorrent" =
  let
    uiWebPort = config.services.qbittorrent-nox.port;
  in
  {
    locations."/" = {
      proxyPass = "http://${config.nordvpn.vethBridge.vpnIp}:${builtins.toString uiWebPort}";
      proxyWebsockets = true;
    };
  };
```

Move the complete existing listen and proxy header block, the two qBittorrent secrets, and the full template.

**Atomic file deployment** (`hosts/ser8/media.nix:572-591`):

```bash
CONFIG_DIR="/var/lib/qbittorrent/qBittorrent/config"
CONFIG_FILE="$CONFIG_DIR/qBittorrent.conf"
TEMP_FILE="$CONFIG_DIR/qBittorrent.conf.tmp"
mkdir -p "$CONFIG_DIR"
chown qbittorrent:qbittorrent "$CONFIG_DIR"
cp ${config.sops.templates."qbittorrent.conf".path} "$TEMP_FILE"
chown qbittorrent:qbittorrent "$TEMP_FILE"
chmod 600 "$TEMP_FILE"
mv "$TEMP_FILE" "$CONFIG_FILE"
```

Keep this as the qBittorrent-owned ordered deployment fragment at order 700.

### `hosts/ser8/media/sabnzbd.nix` and `hosts/ser8/media/nzbget.nix`

**Analog:** Their exact secret, template, and deployment slices in `hosts/ser8/media.nix`.

SABnzbd owns declarations for `sabnzbd_api_key`, `sabnzbd_nzb_key`, `sabnzbd_admin_password`, and the three shared `sabnzbd_usenet_*` secrets at `hosts/ser8/media.nix:110-145`.
NZBGet references those existing paths and placeholders without redeclaring them.
This intentionally preserves the deferred shared credential names and shared administrator password.

**NZBGet shared-secret reference** (`hosts/ser8/media.nix:437-457`):

```nix
ControlUsername=admin
ControlPassword=${config.sops.placeholder."sabnzbd_admin_password"}
Server1.Username=${config.sops.placeholder."sabnzbd_usenet_username"}
Server1.Password=${config.sops.placeholder."sabnzbd_usenet_password"}
```

Move SABnzbd's `services.sabnzbd.configFile` from `hosts/ser8/media.nix:496-498` and both service enablements from `hosts/ser8/configuration.nix:222-223`.
Use deployment order 500 for NZBGet and 600 for SABnzbd to preserve the evaluated sequence.

### `hosts/ser8/media/jellyfin.nix` (config, file-I/O + event-driven)

**Analogs:** `modules/media/jellyfin.nix`, `hosts/ser8/media.nix`, and `modules/media/jellyfin-exporter.nix`.

**Host-owned identities** (`modules/media/jellyfin.nix:42-68`):

```nix
users = {
  admin = {
    permissions = {
      isAdministrator = true;
      enableRemoteAccess = true;
      enableMediaPlayback = true;
      enableContentDeletion = true;
      enableAllFolders = true;
      enableAllDevices = true;
    };
    hashedPasswordFile = config.sops.secrets.jellyfin_admin_password.path;
    enableLocalPassword = true;
  };
};
```

Move the complete `admin` and `jordan` records from `modules/media/jellyfin.nix:43-94` without shortening their permissions or preferences.
Add the required complete `sawnia` record only after resolving the permission checkpoint because no existing source defines it.

**API-key wiring** (`hosts/ser8/media.nix:500-505`):

```nix
services.declarative-jellyfin.apikeys.jellyfinarr = {
  keyPath = config.sops.secrets.jellyfin_api_key.path;
};
```

The host module also owns the four Jellyfin secrets and supplies the exporter key-file option described below.
It does not own the generic Jellyfin system account, network defaults, firewall port, exporter implementation, or hardening.

### `hosts/ser8/media/orchestration.nix` (config, event-driven + request-response)

**Analog:** `hosts/ser8/media.nix:539-738`.

**Stable unit envelope** (`hosts/ser8/media.nix:539-556`):

```nix
systemd.services.media-config = {
  description = "Deploy all media service configurations with secrets";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    User = "root";
  };
};
```

Contribute the deployment-helper source and opening log at order 100, and the completion log at order 800.
Keep `servarrs-setup`, `download-clients-setup`, and `media-setup.target` here because their API calls and dependency graphs span multiple service owners.

**Dependency pattern** (`hosts/ser8/media.nix:597-612`):

```nix
servarrs-setup = {
  after = [
    "media-config.service"
    "prowlarr.service"
    "sonarr.service"
    "radarr.service"
  ];
  requires = [ "media-config.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    User = "root";
  };
};
```

Preserve `after`, `before`, `requires`, `wants`, and `wantedBy` as distinct contracts.
Do not treat ordering fields as activation dependencies.

**Target pattern** (`hosts/ser8/media.nix:729-738`):

```nix
systemd.targets.media-setup = {
  description = "Complete media stack setup orchestration";
  wants = [
    "media-config.service"
    "servarrs-setup.service"
    "download-clients-setup.service"
  ];
  wantedBy = [ "multi-user.target" ];
};
```

### Shell helper split

#### `hosts/ser8/media/deployment-helpers.sh`

**Analog:** `hosts/ser8/systemd_helpers.sh:64-110`.

```bash
configure_arr() {
    local service_name="$1"
    local template_path="$2"

    case "$service_name" in
    "sonarr")
        mkdir -p /var/lib/sonarr/.config/NzbDrone
        cp "$template_path" /var/lib/sonarr/.config/NzbDrone/config.xml
        chown sonarr:sonarr /var/lib/sonarr/.config/NzbDrone/config.xml
        chmod 600 /var/lib/sonarr/.config/NzbDrone/config.xml
        ;;
    *)
        echo "Unknown service: $service_name"
        return 1
        ;;
    esac
}
```

Move the complete existing case statement, including every active service branch, without changing destinations, owners, or modes.
Start the new Bash file with the existing shebang and SPDX header followed by `set -euo pipefail`.

#### `hosts/ser8/media/orchestration-helpers.sh`

**Analog:** `hosts/ser8/systemd_helpers.sh:6-63,112-531`.

**Sanitized request and error pattern** (`hosts/ser8/systemd_helpers.sh:29-61`):

```bash
curl_safe() {
    local command="$CURL_BIN $*"
    local sanitized_command
    sanitized_command=$(sanitize_api_key "$command")
    echo "Executing: $sanitized_command" >&2

    local output
    local stderr_file
    local exit_code
    stderr_file=$(mktemp)

    if output=$("$CURL_BIN" -sS "$@" 2>"$stderr_file"); then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "curl failed with exit code $exit_code" >&2
        sanitize_api_key "$(cat "$stderr_file")" >&2
    fi

    rm -f "$stderr_file"
    sanitize_api_key "$output"
    return $exit_code
}
```

Keep `sanitize_api_key`, `curl_safe`, readiness checks, idempotent upserts, Arr application registration, and download-client registration together.
Preserve secret sanitization on command text, URLs, stderr, and response failures.
Add `set -euo pipefail`, format with shfmt, and add only narrow documented SC2016 ignores for single-quoted jq programs.

### `modules/media/jellyfin.nix` and `modules/media/jellyfin-exporter.nix`

`modules/media/jellyfin.nix` keeps the generic service account, service enablement, network defaults, and firewall behavior from `modules/media/jellyfin.nix:11-40,98-100`.
Remove the household `users` block rather than leaving aliases or compatibility definitions.

The exporter currently hard-codes a host secret at `modules/media/jellyfin-exporter.nix:65`:

```nix
LoadCredential = "jellyfin-api-key:${config.sops.secrets.jellyfin_api_key.path}";
```

Replace that host dependency with a minimal generic option modeled on `modules/media/qbittorrent.nix:15-47`:

```nix
options.services.jellyfin-exporter = {
  enable = lib.mkEnableOption "Jellyfin Prometheus exporter";
  apiKeyFile = lib.mkOption {
    type = lib.types.path;
    description = "Path to the Jellyfin API key file";
  };
};
```

Guard the implementation with `lib.mkIf cfg.enable`, use `cfg.apiKeyFile` in `LoadCredential`, and configure both values from `hosts/ser8/media/jellyfin.nix`.
Do not retain any `sops`, `ser8`, or household-user reference in the reusable exporter.

### `modules/media/default.nix` and deletion targets

Use the import-only pattern shown above.
Remove `./exportarr.nix` and the commented `./alldebrid-proxy.nix` import from `modules/media/default.nix:15-16` after their responsibilities have moved or been removed.

Delete `modules/media/exportarr.nix` only after all three exporter instance definitions are present in their owning host modules.
Delete `modules/media/alldebrid-proxy.nix` under D-21.
Treat `modules/media/transmission.nix` as a planner checkpoint because research identifies it as unimported replacement code, but D-22 does not name it as explicitly as D-21 names AllDebrid.
Do not delete encrypted SOPS keys, `hosts/ser8/impermanence.nix` state, or out-of-directory `flake.nix` remnants without resolving the separate scope question.

### `modules/media/*.nix` audit-only files

Use each file as its own behavior analog.
The audit is removal-oriented: preserve active options, users, packages, network namespaces, service hardening, firewall rules, and overlays.
Do not rewrite clean modules or convert comments that explain active behavior into new abstractions.
Known candidates include unused `pkgs` arguments in the small Arr modules and commented-out restrictions in `modules/media/qbittorrent.nix:89-90,110-111`; validate each candidate with evaluation before removal.

### `<parity projection>.nix` and `<parity check>.sh`

No existing repository test serializes and compares an evaluated NixOS behavior projection.
Use the full projection shape from `08-RESEARCH.md` rather than a source-text diff.
Include service settings, non-secret SOPS metadata, template content and ownership, household users, exporter settings, nginx wiring, all relevant unit dependency fields, generated scripts, and `media-setup.target`.

Never serialize secret contents.
Normalize only the approved helper store-path differences and encode expected deltas for Sawnia and removed AllDebrid declarations explicitly.

**Fail-fast shell runner analog** (`scripts/nixos-rebuild.sh:166-177`):

```bash
pkg_info=$(nix eval ".#packageInfo.${host}" --json 2>/dev/null) || {
    fail "Unable to evaluate packageInfo for host '$host'"
    return 1
}
```

**Small test aggregator analog** (`scripts/smoketests/nordvpn/all.sh:1-13`):

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

TESTS=(
    ./scripts/smoketests/nordvpn/test-veth-interfaces.sh
    ./scripts/smoketests/nordvpn/test-forwarding.sh
)

for test in "${TESTS[@]}"; do
    "${test}" "$@"
done
```

The parity check should add `set -euo pipefail`, actionable mismatch output, structural file/import assertions, and a check that fixtures contain no secret values.
The existing `scripts/smoketests/media/all.sh` should remain unchanged unless deployed behavior changes because Phase 8 requires no live activation.

### `hosts/ser8/configuration.nix` and old aggregate removal

Change only the import at `hosts/ser8/configuration.nix:14` from `./media.nix` to `./media` and move service-specific host policy at lines 207-269 into the relevant service files.
Keep unrelated host networking, storage, automation, and packages in place.
Delete `hosts/ser8/media.nix` only after the directory import evaluates and the parity projection passes.

## Shared Patterns

### Module headers and arguments

**Source:** `modules/automation/default.nix:1-10`, `modules/media/sonarr.nix:1-10`

Every new Nix file starts with `# SPDX-License-Identifier: GPL-3.0-or-later`.
Use a minimal module argument set and remove arguments that become unused after cleanup.
Run nixfmt rather than hand-aligning Nix expressions.

### Host policy versus reusable implementation

**Source:** `hosts/ser8/configuration.nix:207-269`, `modules/media/qbittorrent.nix:15-150`

Host files set concrete enablement, endpoints, secrets, templates, proxy wiring, exporter instances, and deployment contributions.
Reusable modules define generic options, accounts, packages, service implementation, networking, firewall behavior, and hardening.

### Authentication and secret handling

**Source:** `modules/dns/adguard-exporter.nix:45-76`, `hosts/ser8/media.nix:18-492`

```nix
sops.secrets.adguard_password = {
  owner = "root";
  group = "root";
  mode = "0400";
};

systemd.services.adguard-exporter.serviceConfig.LoadCredential =
  "adguard-password:${config.sops.secrets.adguard_password.path}";
```

Use SOPS placeholders in rendered templates and runtime file paths or systemd credentials in services.
Never interpolate a plaintext secret into a Nix store artifact or parity fixture.

### Error handling and logging

**Source:** `hosts/ser8/systemd_helpers.sh:15-61,119-202`

Shell helpers return nonzero with operation and service context.
All API failure output passes through `sanitize_api_key` before logging.
New scripts use strict mode, retain quoting, and do not swallow failed `curl`, `jq`, copy, ownership, or permission operations.

### Systemd composition

**Source:** `hosts/ser8/media.nix:539-738`, with merge ordering from the research-verified NixOS module pattern

The orchestration module owns unit envelopes and cross-service dependencies.
Service modules contribute exactly one explicit ordered deployment fragment and their own `before` dependency.
The stable public names remain `media-config.service`, `servarrs-setup.service`, `download-clients-setup.service`, and `media-setup.target`.

### Validation

**Source:** `.planning/phases/08-reorganize-ser8-media-nix-into-per-service-modules/08-VALIDATION.md:16-57`

Run the non-secret parity projection and narrow formatter or shell checks after each extraction.
Run the full normalized comparison and `make build-ser8` after each wave.
The final gate is `make check && make build-ser8`, with warnings treated as failures and no live activation.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `<parity projection>.nix` | test | batch + transform | No repository code selects and serializes a NixOS behavior contract for comparison. |
| Distributed `media-config.script` definitions across the seven host modules | config | event-driven | The current code defines one monolithic script; use the research-verified `lib.mkOrder` pattern. |

## Planner Checkpoints

1. Confirm Sawnia's exact Jellyfin permissions and preferences before creating the required complete user record.
2. Decide whether D-22 authorizes deleting unimported `modules/media/transmission.nix`.
3. Decide separately whether active AllDebrid persistence in `hosts/ser8/impermanence.nix` and stale `flake.nix` comments are in scope.
4. Do not edit encrypted `secrets/ser8.yaml` unless the user explicitly authorizes the repository SOPS workflow.
5. Choose paths for the Wave 0 projection and parity runner, then keep those paths consistent in plans and validation commands.

## Metadata

**Analog search scope:** `hosts/ser8/`, `hosts/pi4/`, `modules/media/`, `modules/automation/`, `modules/dns/`, `scripts/`, and existing Phase 8 validation artifacts

**Files scanned:** 34 source and planning files, stopping after the current aggregate, import-only module, host-SOPS/exporter module, generic option module, and shell runner formed five strong analog families

**Pattern extraction date:** 2026-07-25
