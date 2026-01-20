# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  networking.search = [ "shad-bangus.ts.net" ];

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  # Note: Tailscale auto-configures DNS on the tailscale0 interface
  # via systemd-resolved when connected. No manual DNS config needed.
}
