# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
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
