# SPDX-License-Identifier: GPL-3.0-or-later

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

    dynamicConfigOptions = {
      http = {
        routers = {
          # Jellyfin
          jellyfin = {
            rule = "Host(`jellyfin.homelab`)";
            service = "jellyfin";
            entryPoints = [ "web" ];
          };

          # AdGuard
          adguard = {
            rule = "Host(`adguard.homelab`)";
            service = "adguard";
            entryPoints = [ "web" ];
          };

          # Grafana
          grafana = {
            rule = "Host(`grafana.homelab`)";
            service = "grafana";
            entryPoints = [ "web" ];
          };

          # Prometheus
          prometheus = {
            rule = "Host(`prometheus.homelab`)";
            service = "prometheus";
            entryPoints = [ "web" ];
          };

          # Traefik Dashboard
          traefik = {
            rule = "Host(`traefik.homelab`)";
            service = "api@internal";
            entryPoints = [ "web" ];
          };
        };

        services = {
          jellyfin = {
            loadBalancer = {
              servers = [
                { url = "http://192.168.68.89:8096"; }
              ];
            };
          };

          adguard = {
            loadBalancer = {
              servers = [
                { url = "http://192.168.68.96:3000"; } # Local on pi4
              ];
            };
          };

          grafana = {
            loadBalancer = {
              servers = [
                { url = "http://192.168.68.88:3000"; } # Local on Firebat
              ];
            };
          };

          prometheus = {
            loadBalancer = {
              servers = [
                { url = "http://192.168.68.88:9090"; } # Local on Firebat
              ];
            };
          };
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
