# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  upstream,
  ...
}:

let
  # Apply caddy-nix overlay for Caddy with plugins support.
  # Its build tools come from the same revision as the locked Caddy package.
  inherit ((builtins.fromJSON (builtins.readFile ../../multiverse.lock))) pins;
  caddyOverlay = upstream.caddy-nix.overlays.default;
  caddyPkgs = (config.multiverse.instance.at pins.caddy.rev).extend caddyOverlay;
  caddyWithPlugins = caddyPkgs.caddy.withPlugins {
    plugins = [
      # Tailscale plugin for automatic HTTPS certificate provisioning
      # Tailscale v1.102.2
      "github.com/tailscale/caddy-tailscale@v0.0.0-20260826180304-de41b249af4f"
    ];
    # Caddy v2.11.7
    hash = "sha256-I9A+/rwj97qu2yAP3rm+4+QBJjOKzngMM14nWZ3r6Q4=";
  };
  # nixpkgs builds Caddy against the system CA store only, by deleting the
  # embedded fallback root bundle, which never receives cacert updates. The
  # plugin build vendors Caddy, so that file sits under vendor/ instead.
  caddyWithTailscale = caddyWithPlugins.overrideAttrs {
    postConfigure = "rm vendor/github.com/caddyserver/caddy/v2/cmd/x509rootsfallback.go";
  };
in
{
  # Allow Caddy to use the shared Tailscale key when registering new tsnet nodes.
  sops.secrets.tailscale_authkey = {
    owner = "caddy";
    group = "caddy";
    mode = "0400";
    # The key is exported as TS_AUTHKEY in the ExecStart wrapper, so a
    # rotated key is invisible to the running process; new tsnet node
    # registrations would keep failing with the expired key.
    restartUnits = [ "caddy.service" ];
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
              exec ${caddyBin} run --config ${caddyConfig} --adapter caddyfile
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

  homelab.monitoring.systemd.units = lib.mkIf config.services.caddy.enable {
    "caddy.service".expectedRunning = true;
  };
}
