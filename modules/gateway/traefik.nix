{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.traefik = {
    enable = lib.mkDefault true;

    staticConfigOptions = {
      # Entry points
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entrypoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure = {
          address = ":443";
        };
      };

      # Certificate resolver (Let's Encrypt)
      certificatesResolvers.letsencrypt = {
        acme = {
          email = "bdhillon1994@gmail.com";
          storage = "/var/lib/traefik/acme.json";
          httpChallenge.entryPoint = "web";
        };
      };

      # API and dashboard
      api = {
        dashboard = true;
        insecure = true; # Only for internal network
      };

      # Providers
      providers = {
        file = {
          filename = "/etc/traefik/dynamic.yml";
          watch = true;
        };
      };
    };
  };

  # Traefik dynamic configuration
  environment.etc."traefik/dynamic.yml".text = lib.generators.toYAML { } {
    http = {
      routers = {
        # Route to Jellyfin on Beelink
        jellyfin = {
          rule = "Host(`jellyfin.firebat.local`)";
          service = "jellyfin";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
        };

        # Route to Pi-hole admin
        pihole = {
          rule = "Host(`pihole.firebat.local`)";
          service = "pihole";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
        };

        # Route to Grafana
        grafana = {
          rule = "Host(`grafana.firebat.local`)";
          service = "grafana";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
        };
      };

      services = {
        jellyfin = {
          loadBalancer.servers = [
            { url = "http://beelink.local:8096"; }
          ];
        };

        pihole = {
          loadBalancer.servers = [
            { url = "http://pi4.local:80"; }
          ];
        };

        grafana = {
          loadBalancer.servers = [
            { url = "http://localhost:3000"; }
          ];
        };
      };
    };
  };

  # Ensure traefik data directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/traefik 0755 traefik traefik -"
  ];

  # Open firewall ports for Traefik
  networking.firewall.allowedTCPPorts = [
    80
    443
    8080
  ];
}
