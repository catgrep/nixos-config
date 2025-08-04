# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.caddy = {
    enable = true;
    email = "catgrep@sudomail.com";

    # Reference the external Caddyfile
    configFile = ./Caddyfile;
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
