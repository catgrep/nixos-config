# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Build Caddy with Tailscale plugin using caddy-nix overlay
  # The overlay provides pkgs.caddy.withPlugins with better build handling
  caddyWithTailscale = pkgs.caddy.withPlugins {
    plugins = [
      # Tailscale plugin for automatic HTTPS certificate provisioning
      # Pinned to Sept 2025 version compatible with Caddy 2.10.0
      # (commit bd3189d bumped to 2.10.2 in Oct 2025)
      "github.com/tailscale/caddy-tailscale@v0.0.0-20250915161136-32b202f0a953"
    ];
    hash = "sha256-EfA2TmBJ3Z/1nG4UPhNeJ4qGgKzbS6z/4wgUkg/GYcY=";
  };
in
{
  services.caddy = {
    enable = true;
    email = "catgrep@sudomail.com";

    # Custom Caddy build with Tailscale plugin
    package = caddyWithTailscale;

    # Reference the external Caddyfile
    configFile = ./Caddyfile;
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
