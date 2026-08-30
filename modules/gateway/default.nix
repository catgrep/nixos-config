# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./caddy.nix
    ./prometheus.nix
    ./alertmanager.nix
    ./grafana.nix
    ./tailscale.nix
    ./blackbox.nix
  ];
}
