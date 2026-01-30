# SPDX-License-Identifier: GPL-3.0-or-later

# Gateway-specific Tailscale configuration
# Base Tailscale config comes from modules/servers/tailscale.nix
{ ... }:

{
  # Enable routing features for gateway role
  # Allows Caddy to route traffic to internal services
  services.tailscale.useRoutingFeatures = "server";
}
