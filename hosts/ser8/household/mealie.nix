# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

{
  services.mealie = {
    enable = true;

    # Version pinned in the repo-root multiverse.lock; stable ships an older
    # mealie and the NixOS module is identical across branches, so a
    # package-only override is safe. Alembic migrations are one-way, so the
    # pin only moves through a deliberate, backed-up `mvs lock update mealie`.
    package = config.multiverse.locked.mealie;

    database.createLocally = true;

    settings = {
      # Every value MUST be a string. The module stringifies the whole attrset
      # with toString, and `toString false` is the empty string in Nix, which
      # would silently reopen registration.
      BASE_URL = "https://mealie.shad-bangus.ts.net";
      # Signup stays open: mealie is reachable only through Tailscale
      # (see modules/gateway/Caddyfile), so UI profile creation is trusted.
      ALLOW_SIGNUP = "true";
      TZ = "America/Los_Angeles";
    };

    # gunicorn trusts only 127.0.0.1 and ::1 for X-Forwarded-* headers by
    # default; the gateway proxies from its LAN address. An explicit address
    # rather than a wildcard, which would disable the front-end IP check.
    extraOptions = [
      "--forwarded-allow-ips"
      "192.168.68.63"
    ];
  };

  homelab.monitoring.systemd.units = lib.mkIf config.services.mealie.enable {
    "mealie.service".expectedRunning = true;
  };
}
