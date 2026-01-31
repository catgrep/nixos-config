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

    # Configure Caddy to use Tailscale auth key from SOPS secret
    # Only enabled when the caddy_ts_authkey secret is configured
    (lib.mkIf (config.sops.secrets ? caddy_ts_authkey) {
      # Override ExecStart to inject TS_AUTHKEY from SOPS secret
      # Must use list with empty string first to clear the original ExecStart in systemd drop-in
      serviceConfig.ExecStart = lib.mkForce [
        "" # Clear original ExecStart
        (
          let
            caddyBin = "${caddyWithTailscale}/bin/caddy";
            caddyConfig = config.services.caddy.configFile;
          in
          pkgs.writeShellScript "caddy-start" ''
            export TS_AUTHKEY="$(cat ${config.sops.secrets.caddy_ts_authkey.path})"
            exec ${caddyBin} run --environ --config ${caddyConfig} --adapter caddyfile
          ''
        )
      ];
    })
  ];

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
