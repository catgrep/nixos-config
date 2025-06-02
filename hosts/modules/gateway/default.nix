{ ... }:

{
  imports = [
    ./traefik.nix
    ./prometheus.nix
    ./grafana.nix
  ];
}
