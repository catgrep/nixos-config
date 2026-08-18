# SPDX-License-Identifier: GPL-3.0-or-later

{ unstable, ... }:

{
  services.mealie = {
    enable = true;

    # Commit to the unstable 3.22.0 at first boot. Stable ships 3.16.0 and the
    # NixOS module is identical across both branches, so a package-only
    # override is safe. Alembic migrations are one-way, so this input only
    # moves on a deliberate, backed-up flake update.
    package = unstable.mealie;

    database.createLocally = true;

    settings = {
      # Every value MUST be a string. The module stringifies the whole attrset
      # with toString, and `toString false` is the empty string in Nix, which
      # would silently reopen registration.
      BASE_URL = "https://mealie.shad-bangus.ts.net";
      ALLOW_SIGNUP = "false";
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
}
