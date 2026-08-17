# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  caddyWithTailscale = pkgs.caddy.withPlugins {
    plugins = [
      # Tailscale plugin for automatic HTTPS certificate provisioning
      # Using latest from main branch for Caddy 2.11.x compatibility
      "github.com/tailscale/caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac"
    ];
    # Vendor-tree hash. Derived from the pinned plugin ref plus the channel's
    # caddy and go versions, so it moves whenever caddy does; 26.05 took caddy
    # 2.10.x -> 2.11.4. Not a trust anchor -- every input is locked.
    hash = "sha256-tP/ZQjZvfb+e3322dzd3I89Y9QwujcyqV1fbNWyw08g=";
  };
in
{
  # Allow Caddy to use the shared Tailscale key when registering new tsnet nodes.
  sops.secrets.tailscale_authkey = {
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

    # Configure Caddy to use the shared Tailscale auth key.
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
              export TS_AUTHKEY="$(cat ${config.sops.secrets.tailscale_authkey.path})"
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
    2019 # Caddy admin API (metrics)
  ];
}
