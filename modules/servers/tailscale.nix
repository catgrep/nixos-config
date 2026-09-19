# SPDX-License-Identifier: GPL-3.0-or-later

# Shared Tailscale configuration for all servers
# Enables remote SSH access via Tailnet with auto-authentication
{ config, ... }:

{
  # SOPS secret for Tailscale auth key (from shared secrets)
  sops.secrets."tailscale_authkey" = {
    sopsFile = ../../secrets/shared.yaml;
  };

  services.tailscale = {
    enable = true;
    # Version pinned in the repo-root multiverse.lock; move it with
    # `mvs lock update tailscale`.
    package = config.multiverse.locked.tailscale;
    # Auto-authenticate on startup using shared auth key
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
  };

  # Add Tailscale domain to DNS search path
  networking.search = [ "shad-bangus.ts.net" ];

  networking.firewall = {
    # Trust traffic from Tailscale interface
    trustedInterfaces = [ "tailscale0" ];
    # Allow Tailscale UDP port for WireGuard
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
