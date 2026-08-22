# SPDX-License-Identifier: GPL-3.0-or-later

{ config, pkgs, ... }:

{
  services.donetick = {
    enable = true;

    # Same derivation flake.nix's subgenPackagesFor resolves for
    # `nix build .#donetick` -- single source of truth, see
    # packages/donetick/default.nix.
    package = pkgs.callPackage ../../../packages/donetick { };
  };

  # DT_JWT_SECRET is generated via `openssl rand -base64 32` (>=32 chars,
  # distinct from Donetick's own weak-secret denylist) and added by hand via
  # `make sops-edit-ser8` under the key donetick_jwt_secret -- see
  # 11-04-SUMMARY.md for the value's one-time terminal display. The
  # sandboxed executor cannot decrypt secrets/ser8.yaml, so this key exists
  # here as a reference only until the operator adds it.
  sops.secrets.donetick_jwt_secret = {
    owner = "donetick";
    group = "donetick";
    mode = "0400";
  };

  sops.templates."donetick.env" = {
    owner = "donetick";
    group = "donetick";
    mode = "0400";
    # Without this, a rendered-content-only change (e.g. this plan's
    # DT_IS_USER_CREATION_DISABLED flip) does not restart donetick.service --
    # sops-nix re-renders the file on disk, but nothing tells systemd the
    # already-running process's env is now stale, and no other host/module
    # option changed to trigger nixos-rebuild's own unit-diff restart.
    # Discovered live in this plan: signup was still open after a full
    # `make switch-ser8` because the unit predated the render.
    restartUnits = [ "donetick.service" ];
    content = ''
      DT_NAME=selfhosted
      DT_IS_USER_CREATION_DISABLED=true
      DT_DATABASE_TYPE=sqlite
      DT_SQLITE_PATH=/var/lib/donetick/donetick.db
      DT_JWT_SECRET=${config.sops.placeholder.donetick_jwt_secret}
      DT_SERVER_PORT=2021
      DT_SERVER_PUBLIC_HOST=https://donetick.shad-bangus.ts.net
      DT_SERVER_SERVE_FRONTEND=true
    '';
  };

  # The single-circle-instance restriction env var is deliberately never set
  # here at all (not even to "false"): leaving it fully unset keeps
  # /api/v1/circles/join and /api/v1/circles/members/requests/accept
  # registered, which plan 11-05's household bootstrap needs -- enabling it
  # removes those routes. scripts/validation/test-donetick-module.sh greps
  # this file for the literal variable name and fails the gate if it ever
  # appears, so its name is intentionally not spelled out in this comment.
}
