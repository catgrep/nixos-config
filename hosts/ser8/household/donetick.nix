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
  # `make sops-edit-ser8` under the key donetick_jwt_secret.
  sops.secrets.donetick_jwt_secret = {
    owner = "donetick";
    group = "donetick";
    mode = "0400";
  };

  sops.templates."donetick.env" = {
    owner = "donetick";
    group = "donetick";
    mode = "0400";
    restartUnits = [ "donetick.service" ];
    content = ''
      DT_NAME=selfhosted
      # Signup stays open: donetick is reachable only through Tailscale
      # (see modules/gateway/Caddyfile), so UI profile creation is trusted.
      DT_IS_USER_CREATION_DISABLED=false
      DT_DATABASE_TYPE=sqlite
      DT_SQLITE_PATH=/var/lib/donetick/donetick.db
      DT_JWT_SECRET=${config.sops.placeholder.donetick_jwt_secret}
      DT_SERVER_PORT=2021
      DT_SERVER_PUBLIC_HOST=https://donetick.shad-bangus.ts.net
      DT_SERVER_SERVE_FRONTEND=true
    '';
  };
}
