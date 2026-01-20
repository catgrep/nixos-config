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

  networking = {
    firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    # MagicDNS configuration for Tailscale
    # 100.100.100.100 is Tailscale's MagicDNS resolver
    # Fallback DNS servers are required for Tailscale to bootstrap
    nameservers = lib.mkBefore [ "100.100.100.100" ];
    search = [ "shad-bangus.ts.net" ];
  };
}
