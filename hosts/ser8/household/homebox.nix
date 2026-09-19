# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
  # Homebox refuses to start without an API-key pepper of at least 32 bytes.
  # It must stay stable across restarts: rotating it invalidates every issued
  # API key. Generated via `openssl rand -base64 48` and added by hand via
  # `make sops-edit-ser8` under the key homebox_api_key_pepper.
  sops.secrets.homebox_api_key_pepper = {
    owner = "homebox";
    group = "homebox";
    mode = "0400";
  };

  # The homebox module renders `settings` into the unit's plain environment,
  # which is world-readable; the pepper is injected through an EnvironmentFile
  # instead so the secret never lands in the store or the unit file.
  sops.templates."homebox.env" = {
    owner = "homebox";
    group = "homebox";
    mode = "0400";
    restartUnits = [ "homebox.service" ];
    content = ''
      HBOX_AUTH_API_KEY_PEPPER=${config.sops.placeholder.homebox_api_key_pepper}
    '';
  };

  systemd.services.homebox.serviceConfig.EnvironmentFile = config.sops.templates."homebox.env".path;

  services.homebox = {
    enable = true;
    # Version pinned in the repo-root multiverse.lock; move it with
    # `mvs lock update homebox`.
    package = config.multiverse.locked.homebox;

    settings = {
      HBOX_WEB_PORT = "7745";
      HBOX_OPTIONS_ALLOW_ANALYTICS = "false";
      HBOX_OPTIONS_GITHUB_RELEASE_CHECK = "false";
      HBOX_OPTIONS_HOSTNAME = "homebox.shad-bangus.ts.net";
      HBOX_DEMO = "false";
      # Registration stays open: homebox is reachable only through Tailscale
      # (see modules/gateway/Caddyfile), so UI profile creation is trusted.
      HBOX_OPTIONS_ALLOW_REGISTRATION = "true";
    };
  };
}
