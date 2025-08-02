# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./traefik.nix
    ./prometheus.nix
    ./grafana.nix
  ];
}
