{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.adguardhome = {
    enable = lib.mkDefault true;
    mutableSettings = false;
    settings = {
      # Bind to all interfaces
      host = "0.0.0.0";
      port = 3000;

      # DNS settings
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;

        # Upstream DNS servers
        upstream_dns = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
          "8.8.4.4"
        ];

        # Bootstrap DNS
        bootstrap_dns = [
          "1.1.1.1:53"
          "1.0.0.1:53"
        ];

        # Enable query logging
        querylog_enabled = true;
        querylog_file_enabled = true;
        querylog_interval = "24h";
        querylog_size_memory = 1000;

        # Enable statistics
        statistics_interval = 1;

        # Cache settings
        cache_size = 4194304; # 4MB
        cache_ttl_min = 0;
        cache_ttl_max = 0;

        # Privacy settings
        anonymize_client_ip = false;

        # Local domain handling
        local_domain_name = "homelab.local";

        # Enable safe browsing
        safebrowsing_enabled = true;
        parental_enabled = true;
        safesearch_enabled = false;
      };

      # DHCP (disabled by default)
      dhcp = {
        enabled = false;
        interface_name = "eth0";
        local_domain_name = "homelab.local";
        dhcpv4 = {
          gateway_ip = "192.168.1.1";
          subnet_mask = "255.255.255.0";
          range_start = "192.168.1.100";
          range_end = "192.168.1.200";
          lease_duration = 86400; # 24 hours
        };
      };

      # Filtering
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        blocked_response_ttl = 10;

        # Blocked services (you can add more)
        blocked_services = [
          # Add services you want to block, e.g.:
          # "youtube"
          # "facebook"
        ];
      };

      # Web interface users (initial setup)
      users = [
        {
          name = "admin";
          password = "$2a$10$your_bcrypt_hash_here"; # Generate with bcrypt
        }
      ];

      # Enable web interface
      http = {
        address = "0.0.0.0:80";
        session_ttl = "720h";
      };

      # Filters (blocklists)
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = true;
          url = "https://adaway.org/hosts.txt";
          name = "AdAway Default Blocklist";
          id = 2;
        }
      ];

      # Custom DNS rewrites for local services
      dns_rewrites = [
        {
          domain = "jellyfin.homelab.local";
          answer = "192.168.1.20"; # Beelink IP
        }
        {
          domain = "traefik.homelab.local";
          answer = "192.168.1.21"; # Firebat IP
        }
        {
          domain = "grafana.homelab.local";
          answer = "192.168.1.21"; # Firebat IP
        }
        {
          domain = "prometheus.homelab.local";
          answer = "192.168.1.21"; # Firebat IP
        }
        {
          domain = "pihole.homelab.local";
          answer = "192.168.1.10"; # Pi4 IP
        }
        {
          domain = "beelink.homelab.local";
          answer = "192.168.1.20";
        }
        {
          domain = "firebat.homelab.local";
          answer = "192.168.1.21";
        }
        {
          domain = "pi4.homelab.local";
          answer = "192.168.1.10";
        }
      ];
    };
  };

  # Ensure AdGuard Home data directory has correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/AdGuardHome 0755 adguardhome adguardhome -"
  ];

  # Open firewall ports for DNS and web interface
  networking.firewall = {
    allowedTCPPorts = [
      53
      80
      3000
    ];
    allowedUDPPorts = [ 53 ];
  };

  # Note: AdGuard Home has built-in Prometheus metrics at /control/stats
  # You can scrape these directly in Prometheus configuration
  # The metrics are available at http://pi4.local/control/stats when AdGuard is running

  # Pi-specific temperature monitoring service
  systemd.services.pi-temp-monitor = lib.mkIf (config.networking.hostName == "pi4") {
    description = "Raspberry Pi Temperature Monitor";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "pi-temp-check" ''
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$((temp / 1000))

        if [ $temp_c -gt 70 ]; then
          echo "Warning: Pi temperature is $temp_c°C" | ${pkgs.systemd}/bin/systemd-cat -t pi-temp
        fi
      ''}";
    };
  };

  systemd.timers.pi-temp-monitor = lib.mkIf (config.networking.hostName == "pi4") {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
