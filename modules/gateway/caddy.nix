# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  unstable,
  ...
}:

let
  # Build Caddy with Tailscale plugin using caddy-nix overlay on unstable
  # This gets us Caddy 2.10.2+ with latest caddy-tailscale plugin
  caddyWithTailscale = unstable.caddy.withPlugins {
    plugins = [
      # Tailscale plugin for automatic HTTPS certificate provisioning
      # Using latest from main branch for Caddy 2.10.x compatibility
      "github.com/tailscale/caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac"
    ];
    hash = "sha256-4vXIpEWx+rmcaPCU7Nw2T5vQpeHQptXH91ep92Lo4rY=";
  };
in
{
  # SOPS secret for Tailscale auth key (Caddy's copy with caddy ownership)
  # This references the same yaml key as tailscale.nix but with different permissions
  sops.secrets."tailscale_authkey_caddy" = {
    sopsFile = ../../secrets/shared.yaml;
    key = "tailscale_authkey"; # Reference same key in yaml
    owner = "caddy";
    group = "caddy";
    mode = "0400";
  };

  services.caddy = {
    enable = true;
    email = "catgrep@sudomail.com";

    # Custom Caddy build with Tailscale plugin
    package = caddyWithTailscale;

    # Reference the external Caddyfile
    configFile = ./Caddyfile;
  };

  # Caddy systemd configuration
  systemd.services.caddy = lib.mkMerge [
    # Ensure Caddy restarts when systemd-resolved restarts
    # This is needed because Caddy caches DNS lookups and won't pick up
    # new DNS config until restarted
    {
      after = [ "systemd-resolved.service" ];
      requires = [ "systemd-resolved.service" ];
      # PartOf makes Caddy restart when resolved restarts
      partOf = [ "systemd-resolved.service" ];
    }

    # Configure Caddy to use Tailscale auth key from shared SOPS secret
    # Uses tailscale_authkey_caddy which has caddy:caddy ownership
    {
      serviceConfig = {
        # Increase startup timeout - Caddy needs time to establish all Tailscale connections
        TimeoutStartSec = "5min";

        # Override ExecStart to inject TS_AUTHKEY from SOPS secret
        # Must use list with empty string first to clear the original ExecStart in systemd drop-in
        ExecStart = lib.mkForce [
          "" # Clear original ExecStart
          (
            let
              caddyBin = "${caddyWithTailscale}/bin/caddy";
              caddyConfig = config.services.caddy.configFile;
            in
            pkgs.writeShellScript "caddy-start" ''
              export TS_AUTHKEY="$(cat ${config.sops.secrets.tailscale_authkey_caddy.path})"
              exec ${caddyBin} run --environ --config ${caddyConfig} --adapter caddyfile
            ''
          )
        ];
      };
    }
  ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
