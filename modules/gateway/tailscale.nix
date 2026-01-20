# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  unstable,
  ...
}:

{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    # Use unstable for latest security fixes (stable 25.05 has 1.82.5, need >= 1.92.5)
    package = unstable.tailscale;
  };

  networking.search = [ "shad-bangus.ts.net" ];

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Note: Tailscale auto-configures DNS on the tailscale0 interface
  # via systemd-resolved when connected. No manual DNS config needed.
}
