{ ... }:

{
  imports = [
    ./traefik.nix
    ./prometheus.nix
    ./grafana.nix
    # Add other gateway services as needed
  ];
}
