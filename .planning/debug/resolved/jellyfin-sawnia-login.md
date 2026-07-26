---
status: resolved
trigger: "Sawnia cannot log in to Jellyfin; authentication throws `String can't be empty (Parameter 'hashString')`, and a declarative remote-access update was not reflected in Jellyfin."
created: 2026-07-25
updated: 2026-07-25T17:02:00-07:00
---

# Jellyfin Sawnia Login

## Symptoms

- Expected behavior: `sawnia` can authenticate with the SOPS-managed password and receives the remote-access policy declared in Nix.
- Actual behavior: authentication fails, and the changed remote-access setting is absent from Jellyfin.
- Error: `System.ArgumentException: String can't be empty (Parameter 'hashString')` from `PasswordHash.Parse` in `DefaultAuthenticationProvider.Authenticate`.
- Timeline: observed after adding or updating the declarative `sawnia` household user during Phase 08.
- Reproduction: submit `POST /Users/authenticatebyname` by attempting to log in as `sawnia`.

## Current Focus

- hypothesis: Resolved by immutable user reconciliation and service-readable Jellyfin credentials.
- test: Complete through focused evaluation, remote build, temporary activation, live database checks, and an invalid-password authentication request.
- expecting: Sawnia's stored hash matches the configured hash, remote access is enabled, and invalid credentials return HTTP 401 instead of HTTP 500.
- next_action: Make the tested generation persistent with `make switch-ser8` after user approval.

## Evidence

- timestamp: 2026-07-25T16:33:23-07:00
  observation: Jellyfin attempts to parse an empty persisted password hash while authenticating `sawnia`.
- timestamp: 2026-07-25
  observation: `hosts/ser8/media/jellyfin.nix` declares `sawnia.hashedPasswordFile` and a complete non-admin policy.
- timestamp: 2026-07-25T16:38:05-07:00
  observation: No `.planning/debug/knowledge-base.md` exists, so there is no known-pattern candidate to test.
- timestamp: 2026-07-25T16:38:05-07:00
  observation: The repository has no `.codex/skills/` or `.agents/skills/` directory, so no project-local skill rules apply.
- timestamp: 2026-07-25T16:39:47-07:00
  observation: `sb digest hosts/ser8/media` and `sb map hosts/ser8/media/jellyfin.nix` returned `# no files`; the structure-aware tool does not expose these Nix sources, so targeted text search is required.
- timestamp: 2026-07-25T16:40:46-07:00
  observation: Repository search found the `sawnia` declaration and password path in `hosts/ser8/media/jellyfin.nix`, while the reusable implementation is `modules/media/jellyfin.nix`; no test directly exercises Jellyfin authentication or initializer request behavior.
- timestamp: 2026-07-25T16:42:54-07:00
  observation: `modules/media/jellyfin.nix` only configures the service and network; `hosts/ser8/media/jellyfin.nix` declares `admin`, `jordan`, and `sawnia`, and the focused parity test confirms Sawnia mirrors Jordan except for the password path.
- timestamp: 2026-07-25T16:42:54-07:00
  observation: The parity test validates the evaluated Nix option values but does not exercise the external module's runtime API requests or a real Jellyfin login.
- timestamp: 2026-07-25T16:44:34-07:00
  observation: `flake.lock` pins `Sveske-Juice/declarative-jellyfin` at revision `3843ca5bf0bd1f7e81e85f95fe5ad8bf11d5a17c`, and `flake.nix` imports its default NixOS module for x86 hosts.
- timestamp: 2026-07-25T16:44:34-07:00
  observation: Evaluated `ser8` systemd services contain `jellyfin` and `jellyfin-exporter` only; there is no separately named declarative initializer service.
- timestamp: 2026-07-25T16:45:52-07:00
  observation: The pinned input resolves to `/nix/store/18aphsqnvbgqq338phzdxdjvfkqpa94w-source`, and the evaluated `jellyfin.service` exposes normal NixOS lifecycle fields including `preStart`, `postStart`, and `script` for targeted inspection.
- timestamp: 2026-07-25T16:47:19-07:00
  observation: `sb digest` mapped the pinned input and identified `modules/config.nix`, `modules/options/users.nix`, and an upstream `tests/autorun/create_users.nix` NixOS test as the relevant implementation and closest safe E2E reproduction surface.
- timestamp: 2026-07-25T16:50:41-07:00
  observation: The external module defaults `users.*.mutable` to `true`; its documentation says Nix settings apply only at initial creation in that mode, while `mutable = false` overwrites them on each Jellyfin start.
- timestamp: 2026-07-25T16:50:41-07:00
  observation: In `genUser`, an existing mutable user fails the `-z $userExists` guard, and the entire SQL block is skipped, including the `Users.Password` assignment and every `Permissions` row such as `enableRemoteAccess`.
- timestamp: 2026-07-25T16:50:41-07:00
  observation: The upstream create-users E2E test checks only that a user exists after first startup; it does not authenticate any user, assert a non-empty password hash, restart with changed settings, or verify reconciliation for an existing mutable user.
- timestamp: 2026-07-25T16:52:28-07:00
  observation: The evaluated Sawnia option is directly confirmed as `mutable = true`, and `jellyfin.service` resolves `ExecStart` to `/nix/store/s4bl99125fy9ry06mkkmw701q3dy9iab-jellyfin-init/bin/jellyfin-init`.
- timestamp: 2026-07-25T16:52:54-07:00
  observation: The generated executable store path is not currently realized locally, so its Nix string context must be used to build the derivation before inspecting the concrete script.
- timestamp: 2026-07-25T16:56:16-07:00
  observation: Realizing the generated script failed because the configured macOS Native Linux Builder rejected its authentication token; the derivation metadata remains locally inspectable, so this environment issue does not block source-level verification.
- timestamp: 2026-07-25T16:59:47-07:00
  observation: The concrete generated Sawnia branch queries username existence and then wraps the password INSERT/UPDATE plus all permission REPLACEs in `if [ -z $userExists ]`; an existing Sawnia user therefore executes none of those writes.
- timestamp: 2026-07-25T16:59:47-07:00
  observation: The generated but skipped SQL would read `/run/secrets/jellyfin_sawnia_password` into `Users.Password` and set permission kind 4 (`enableRemoteAccess`) to 1, confirming the evaluated desired state is present but unreachable for an existing mutable user.
- timestamp: 2026-07-25T17:02:57-07:00
  observation: A read-only live query on `ser8` returned `user_exists=1`, `password_length=0`, and `enableRemoteAccess=1` for Sawnia; no password, hash, or user identifier was printed.
- timestamp: 2026-07-25T17:02:57-07:00
  observation: Safe boolean checks on the live SOPS file returned `secret_nonempty=1` and `secret_format_valid=1`, proving the current source hash is available and well-shaped while the persisted database value remains empty.
- timestamp: 2026-07-25T17:04:31-07:00
  observation: All 24 live Sawnia permission rows currently match the generated desired values, including permission kind 4 at 1; the current permission state does not reproduce the earlier reported drift, but the same mutable-user guard demonstrably prevents future Nix changes from reconciling an existing record.
- timestamp: 2026-07-25T17:04:31-07:00
  observation: The PATH `git` binary failed with a Rosetta runtime error, so repository history must be inspected with the native `/usr/bin/git` binary.
- timestamp: 2026-07-25T17:07:59-07:00
  observation: The host declaration sets every Jellyfin password secret to `owner = "root"`, `group = "root"`, and `mode = "0600"`, while the upstream module's SOPS example assigns the secret to `config.services.jellyfin.user` and group so its runtime `cat` can read it.
- timestamp: 2026-07-25T17:07:59-07:00
  observation: The native `/usr/bin/git` binary also fails under the environment's missing Rosetta runtime, so commit-history inspection is unavailable and unnecessary given direct evaluated and live evidence.
- timestamp: 2026-07-25T17:09:38-07:00
  observation: Both evaluated and live `jellyfin.service` identities are `jellyfin:jellyfin`; the live secret is `root:root 0600`, and `sudo -u jellyfin test -r` returns false.
- timestamp: 2026-07-25T17:09:38-07:00
  observation: The external initializer uses `set -euo pipefail` and reads `hashedPasswordFile` with `cat` inside its user SQL path, so any create or immutable-user update that reaches the root-only secret cannot complete as the Jellyfin service user.
- timestamp: 2026-07-25T17:02:00-07:00
  observation: The tested configuration makes all household users immutable and makes the three password hashes plus the Jellyfin API key readable only by `jellyfin:jellyfin` with mode `0400`.
- timestamp: 2026-07-25T17:02:00-07:00
  observation: The remote ser8 build and temporary activation completed successfully, and the initializer log was reduced to mode `0600` before initialization and truncated after initialization.
- timestamp: 2026-07-25T17:02:00-07:00
  observation: Live checks confirmed all three household database hashes match their configured hashes, Sawnia remote access equals 1, the initializer log is empty, and the service is active.
- timestamp: 2026-07-25T17:02:00-07:00
  observation: One empty `jellyfinarr` API-key row created by the earlier unreadable-key run was removed; one non-empty row remains and a Jellyfin backup exists.
- timestamp: 2026-07-25T17:02:00-07:00
  observation: A deliberately invalid Sawnia password returned HTTP 401 with no `hashString` exception, reproducing the original request path without exposing the plaintext password.

## Eliminated

- hypothesis: The current SOPS file is empty or not a PBKDF2-SHA512 hash.
  evidence: Live boolean checks show the file is non-empty and begins with the expected PBKDF2-SHA512 marker, while `Users.Password` length is zero.
  timestamp: 2026-07-25T17:02:57-07:00
- hypothesis: The Sawnia password and remote-access values are missing from the evaluated Nix configuration or generated initializer.
  evidence: Evaluation resolves the intended user, password file path, and permissions; the generated SQL contains both the password assignment and permission kind 4 set to 1, but encloses them in the existing mutable-user guard.
  timestamp: 2026-07-25T16:59:47-07:00
- hypothesis: The current live remote-access permission remains different from the declaration.
  evidence: The live permission table currently matches all 24 generated permission values, including kind 4 at 1. The earlier update failure is still explained by the skip guard, but present policy drift is not reproducible now.
  timestamp: 2026-07-25T17:04:31-07:00

## Resolution

- root_cause: Sawnia inherits the upstream default `mutable = true` because `householdUser` never overrides it. The pinned `declarative-jellyfin` initializer checks whether the username already exists and, for a mutable user, executes no `Users` UPDATE and no `Permissions` REPLACE when it does. The persistent Sawnia row exists with `length(Password) = 0`, so the current valid SOPS hash and later policy declarations are never reconciled; Jellyfin passes that empty stored value to `PasswordHash.Parse`, producing `String can't be empty (Parameter 'hashString')`. Independently, the declared password secret is `root:root 0600` while `jellyfin.service` runs as `jellyfin:jellyfin`, so the service cannot read the hash file on a fresh create or forced update path.
- fix: Set household users to `mutable = false`; assign Jellyfin passwords and the API key to `jellyfin:jellyfin` with mode `0400`; secure and clear the upstream SQL initializer log; strengthen the parity assertions; remove the one stale empty API-key row.
- verification: Focused formatting, static analysis, parity, remote build, temporary activation, live database equality checks, remote-access verification, log cleanup verification, and invalid-password HTTP 401 all passed.
- files_changed: `hosts/ser8/media/jellyfin.nix`, `scripts/validation/check-ser8-media-parity.sh`, `.planning/debug/resolved/jellyfin-sawnia-login.md`
