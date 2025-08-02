# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./users.nix
  ];

  # Disable systemd-resolved which conflicts with AdGuard
  services.resolved.enable = false;

  # Make sure systemd-resolved is really disabled
  systemd.services.systemd-resolved.enable = false;

  # Configure networking to use AdGuard once it's running
  networking = {
    nameservers = [ "127.0.0.1" ]; # Use local AdGuard

    # If using DHCP, don't let it override our DNS
    dhcpcd.extraConfig = ''
      nohook resolv.conf
    '';
  };

  # Create a proper resolv.conf with fallback
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
    nameserver 1.1.1.1
    options timeout:1 attempts:1
  '';

  services.adguardhome = {
    enable = lib.mkDefault true;
    mutableSettings = true; # Let AdGuard write its own config so we can update the password
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

        # bootstrap_dns is intended for encrypted upstream DNS
        # (DNS-over-HTTPS/TLS). I'm not using DoH/DoT here.
        #
        # If network DNS ever fails (e.g., AdGuard bootstrap lookup needs to
        # resolve its own upstream), this can create recursion issues.
        #
        # bootstrap_dns = [
        #   "1.1.1.1:53" # Cloudflare (1.1.1.1) for both bootstrap and upstream
        #   "1.0.0.1:53"
        # ];
        bootstrap_dns = [ ];

        # Enable query logging
        querylog_enabled = true;
        querylog_file_enabled = true;
        querylog_interval = "24h";
        querylog_size_memory = 1000;

        # Enable statistics
        statistics_interval = 1;

        # Cache settings
        cache_size = 4194304; # 4MB
        cache_ttl_min = 0; # No forced minimum TTL
        cache_ttl_max = 86400; # Cache up to 24h

        # Privacy settings
        anonymize_client_ip = false;

        # Local domain handling
        local_domain_name = "homelab";

        # Enable safe browsing
        safebrowsing_enabled = true;
        parental_enabled = true;
        safesearch_enabled = false;
      };

      # DHCP (disabled by default)
      dhcp = {
        enabled = false;
        interface_name = "eth0";
        local_domain_name = "homelab";
        dhcpv4 = {
          gateway_ip = "192.168.68.1";
          subnet_mask = "255.255.255.0";
          range_start = "192.168.68.100";
          range_end = "192.168.68.200";
          lease_duration = 86400; # 24 hours
        };
      };

      # Filtering
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
        blocked_response_ttl = 10;

        rewrites = [
          # Traefik managed services
          {
            domain = "*.homelab";
            answer = "192.168.68.88";
          }
          {
            domain = "jellyfin.homelab";
            answer = "192.168.68.88";
          }
          {
            domain = "adguard.homelab";
            answer = "192.168.68.88";
          }
          {
            domain = "grafana.homelab";
            answer = "192.168.68.88";
          }
          {
            domain = "prometheus.homelab";
            answer = "192.168.68.88";
          }
          {
            domain = "traefik.homelab";
            answer = "192.168.68.88";
          }

          # Direct host access
          {
            domain = "beelink.internal";
            answer = "192.168.68.89";
          }
          {
            domain = "firebat.internal";
            answer = "192.168.68.88";
          }
          {
            domain = "pi4.internal";
            answer = "192.168.68.96";
          }
          {
            domain = "pi5.internal";
            answer = "192.168.68.95";
          }
        ];
      };

      # Blocked services - this is now at the top level, not under filtering
      # And it needs to be an object with service names as keys and boolean values
      blocked_services = {
        # Example services you can block:
        # "youtube" = true;
        # "facebook" = true;
        # "tiktok" = true;
      };

      # Web interface users (initial setup)
      # You should generate a proper bcrypt hash or let AdGuard set it up on first run
      users = [
        {
          name = "admin";
          password = ""; # Will be set by the systemd service
        }
      ];

      # Enable web interface
      http = {
        address = "0.0.0.0:3000";
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
    };
  };

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
