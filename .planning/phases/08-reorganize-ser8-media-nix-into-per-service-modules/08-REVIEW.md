---
phase: 08-reorganize-ser8-media-nix-into-per-service-modules
reviewed: 2026-07-25T23:02:56Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - hosts/ser8/configuration.nix
  - hosts/ser8/impermanence.nix
  - hosts/ser8/media/default.nix
  - hosts/ser8/media/deployment-helpers.sh
  - hosts/ser8/media/jellyfin.nix
  - hosts/ser8/media/nzbget.nix
  - hosts/ser8/media/orchestration-helpers.sh
  - hosts/ser8/media/orchestration.nix
  - hosts/ser8/media/prowlarr.nix
  - hosts/ser8/media/qbittorrent.nix
  - hosts/ser8/media/radarr.nix
  - hosts/ser8/media/sabnzbd.nix
  - hosts/ser8/media/sonarr.nix
  - hosts/ser8/media/sops.nix
  - modules/media/default.nix
  - modules/media/jellyfin-exporter.nix
  - modules/media/jellyfin.nix
  - modules/media/prowlarr.nix
  - modules/media/qbittorrent.nix
  - modules/media/radarr.nix
  - modules/media/sonarr.nix
  - scripts/nixos-rebuild.sh
  - scripts/validation/check-ser8-media-parity.sh
  - scripts/validation/ser8-media-projection.nix
findings:
  critical: 5
  warning: 5
  info: 0
  total: 10
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-07-25T23:02:56Z
**Depth:** standard
**Files Reviewed:** 24
**Status:** issues_found

## Summary

The per-service ownership split is structurally understandable, but the reviewed configuration contains five ship-blocking correctness or security defects and five reliability defects.
The most serious issues expose the qBittorrent UI without its request-origin defenses, place the Jellyfin API key in process arguments, bypass SSH host verification for reboot, risk truncating the checked-in hardware configuration, and declare Prowlarr form authentication without deploying its credentials.
Focused shell linting and formatting passed for the new media helpers and validation runner.
The exact compact-JSON cases used by Servarr APIs reproduced the two non-idempotent grep failures, and `run-clean` reproduced acceptance of unclassified stderr.
The full parity evaluation could not complete in this review environment because Nix was denied access to `/Users/bobby/.config`; this environmental failure does not account for the static and focused-runtime findings below.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 (BLOCKER): qBittorrent request-origin protections are disabled on a LAN-facing listener

**File:** `hosts/ser8/media/qbittorrent.nix:19-27,91-99`

**Issue:** Nginx listens on `0.0.0.0:8080`, while the generated qBittorrent configuration disables both CSRF protection and host-header validation.
`hosts/ser8/configuration.nix:25-31` also opens TCP port 8080 through the host firewall.
Any browser that can reach the LAN endpoint can therefore be induced to send authenticated state-changing requests, and DNS rebinding or a forged Host header is not rejected.
This defeats two independent WebUI security boundaries on an exposed administrative interface.

**Fix:** Enable `WebUI\CSRFProtection` and `WebUI\HostHeaderValidation`, configure qBittorrent's accepted server domains for the real hostname or address, and replace the wildcard Nginx listener with the specific trusted interface address.
If remote access is unnecessary, listen only on loopback and remove port 8080 from the firewall.

```nix
WebUI\CSRFProtection=true
WebUI\HostHeaderValidation=true
WebUI\ServerDomains=ser8;192.168.68.65
```

### CR-02 (BLOCKER): The Jellyfin API key is exposed through `/proc` command-line inspection

**File:** `modules/media/jellyfin-exporter.nix:36-43`

**Issue:** `LoadCredential` initially protects the API key in a credential file, but the wrapper reads the value and expands it into `--jellyfin.token="$API_KEY"` before `exec`.
That places the secret in the exporter process's argument vector.
No repository configuration enables a system-wide `hidepid` policy, so other local users can inspect the command line and recover the Jellyfin API key.
The comment claiming the key is exposed only through a systemd credential is therefore false after startup.

**Fix:** Patch or replace the exporter interface so it reads a token file or credential directly and never places the value in argv.
If the exporter cannot accept a token file, add a system-wide `/proc` `hidepid=2` policy as a defense-in-depth prerequisite before using the argument-based interface.
Also make the wrapper fail immediately when the credential cannot be read.

### CR-03 (BLOCKER): Reboot deliberately disables SSH host authentication

**File:** `scripts/nixos-rebuild.sh:147-153`

**Issue:** Both the reboot command and the reconnect probe use `StrictHostKeyChecking=no`.
This accepts an attacker-controlled host key and can send `sudo reboot` to a machine impersonating the configured host.
It also trains the operation to continue after an unexpected key change instead of failing closed.

**Fix:** Remove both `StrictHostKeyChecking=no` overrides and rely on a provisioned `known_hosts` entry.
If first-contact enrollment is required, make it a separate explicit step using `StrictHostKeyChecking=accept-new`; key changes must still fail.

```bash
ssh "${user}@${ip}" -- sudo reboot
ssh -o ConnectTimeout=3 "${user}@${ip}" "echo 'online'"
```

### CR-04 (BLOCKER): A failed hardware probe truncates the tracked hardware configuration

**File:** `scripts/nixos-rebuild.sh:134-135`

**Issue:** The shell opens `hosts/${host}/hardware-configuration.nix` for output before SSH starts.
An authentication failure, network error, remote command failure, or empty remote response therefore truncates the existing configuration even though `set -e` terminates afterward.
This is a direct data-loss path in a command whose help says it replaces the existing file.

**Fix:** Write to a temporary file in the destination directory, verify that SSH succeeded and the result is non-empty valid Nix, then atomically rename it over the destination.
Install a trap that removes the temporary file on every failure.

```bash
local destination="./hosts/${host}/hardware-configuration.nix"
local temporary
temporary=$(mktemp "${destination}.XXXXXX")
trap 'rm -f "$temporary"' RETURN
ssh "${user}@${ip}" "nixos-generate-config --show-hardware-config" >"$temporary"
[ -s "$temporary" ] || fail "Generated hardware configuration is empty"
nix-instantiate --parse "$temporary" >/dev/null
mv "$temporary" "$destination"
```

### CR-05 (BLOCKER): Prowlarr form authentication never receives the declared credentials

**File:** `hosts/ser8/media/prowlarr.nix:22-25,37-42`

**Issue:** The template requires form authentication, and the module declares `prowlarr_admin_password`, but neither a username nor the password placeholder is written to `prowlarr-config.xml`.
The secret is otherwise unused.
On a fresh or overwritten state directory, the deployed authentication policy therefore cannot reproduce a known administrator login and may leave the interface inaccessible or dependent on application-generated state.

**Fix:** Deploy the same explicit username and password fields used by Sonarr and Radarr, and add a focused evaluation assertion that the rendered template references the Prowlarr password placeholder.

```nix
<Username>admin</Username>
<Password>${config.sops.placeholder."prowlarr_admin_password"}</Password>
```

## Warnings

### WR-01 (WARNING): Servarr setup is not idempotent for qBittorrent clients or Prowlarr applications

**File:** `hosts/ser8/media/orchestration-helpers.sh:170-179,328-337`

**Issue:** Both existence checks grep for JSON containing a literal space after the colon, such as `"name": "qBittorrent"`.
Servarr APIs commonly return compact JSON such as `{"name":"qBittorrent"}`, which the checks miss.
The focused reproduction in this review confirmed that both compact forms fail to match.
Each subsequent boot or manual rerun can POST a duplicate, fail on a uniqueness constraint, or leave multiple registrations despite the module's idempotence claim.

**Fix:** Parse the response with the existing `JQ_BIN` path and use the existing upsert pattern for both resources.
For example, obtain the matching ID with `jq -r --arg name "$client_name" 'first(.[] | select(.name == $name) | .id) // empty'`, then PUT when it exists and POST otherwise.

### WR-02 (WARNING): qBittorrent credentials are interpolated into JSON without escaping

**File:** `hosts/ser8/media/orchestration-helpers.sh:181-210`

**Issue:** The qBittorrent payload is assembled as a double-quoted shell string and inserts the password file contents directly inside a JSON string.
A valid password containing a quote, backslash, newline, or other JSON-significant character produces malformed JSON or changes the submitted payload structure.
The SABnzbd and NZBGet paths already avoid this defect by constructing payloads with `jq -n` and `--arg`.

**Fix:** Build the qBittorrent payload with `"$JQ_BIN" -n` and pass every dynamic string, especially the password, through `--arg`.
Then send the resulting payload through the same ID-based upsert helper used by the other clients.

### WR-03 (WARNING): The parity projection checks the wrong qBittorrent module

**File:** `scripts/validation/ser8-media-projection.nix:155-165`

**Issue:** The active host enables the repository's `services.qbittorrent-nox` module, but the projection selects `config.services.qbittorrent`.
The captured baseline proves the mismatch: its projected `services.qbittorrent.enable` is `false` while `qbittorrent-nox.service` is active.
Changes to `qbittorrent-nox.enable`, `port`, `openFirewall`, or `useVpnNamespace` can therefore pass the claimed service-settings parity check.

**Fix:** Project `config.services.qbittorrent-nox` and its actual contract fields: `enable`, `user`, `group`, `port`, `openFirewall`, and `useVpnNamespace`.
Regenerate the baseline from the pre-refactor commit or add a narrowly reviewed expected-delta migration so the corrected assertion cannot silently bless the current value.

### WR-04 (WARNING): The structural gate accepts an incomplete or legacy media entry point

**File:** `scripts/validation/check-ser8-media-parity.sh:144-155`

**Issue:** The first `rg` succeeds if `default.nix` imports the legacy `../media.nix`, and the fallback succeeds if any one of the nine expected modules is present.
It does not require every active service, SOPS support, and orchestration module.
Deleting eight imports can still satisfy `structure`, so the gate does not enforce D-08 or detect a silently disabled service.

**Fix:** Reject every legacy `media.nix` import, then loop over the exact required filenames and require one import for each.
Also verify that `default.nix` contains no configuration attributes beyond `imports` if import-only ownership is part of the contract.

### WR-05 (WARNING): `run-clean` silently accepts arbitrary new stderr

**File:** `scripts/validation/check-ser8-media-parity.sh:93-113`

**Issue:** `validate_stderr` only classifies lines containing `warning`, `error:`, `fatal:`, or `trace:` plus a special Home Manager block.
Any new repository diagnostic that does not contain those words is ignored instead of being matched against the exact warning baseline.
The focused command `run-clean bash -c 'echo repository-diagnostic >&2'` returned success during this review.
This contradicts the runner's fail-closed purpose and can hide evaluator, linter, or wrapper diagnostics.

**Fix:** Compare every non-empty stderr line against the exact baseline, with explicit stateful handling only for known multi-line notices.
Fail on any line or multiplicity not present in the baseline, regardless of keyword.

---

_Reviewed: 2026-07-25T23:02:56Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
