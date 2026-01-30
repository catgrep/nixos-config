# SPDX-License-Identifier: GPL-3.0-or-later

# Shared Tailscale configuration for all servers
# Enables remote SSH access via Tailnet
{
  unstable,
  config,
  ...
}:

{
  services.tailscale = {
    enable = true;
    # Use unstable for security fixes (stable 25.05 has 1.82.5, need >= 1.92.5)
    package = unstable.tailscale;
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
