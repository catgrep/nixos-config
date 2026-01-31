{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

{
  options = {
    networking.internal = {
      # Define common interface names for different device types
      interface = mkOption {
        type = types.str;
        default = "eno1"; # Most common for x86 systems
        description = "Primary network interface name";
      };

      adguard = {
        enabled = mkOption {
          type = types.bool;
          default = true;
          description = "Use AdGuard DNS server for name resolution";
        };

        address = mkOption {
          type = types.str;
          default = "192.168.68.56";
          description = "IP address of the AdGuard DNS server";
        };

        mode = mkOption {
          type = types.enum [
            "strict"
            "failover"
          ];
          default = "failover";
          description = ''
            DNS fallback behavior:
            - strict: Only use AdGuard, no automatic fallback
            - failover: Use AdGuard first, fall back to router DNS if unavailable
          '';
        };
      };

      # staticIP = mkOption {
      #   type = types.nullOr (
      #     types.submodule {
      #       options = {
      #         address = mkOption {
      #           type = types.str;
      #           description = "Static IP address";
      #         };
      #         prefixLength = mkOption {
      #           type = types.int;
      #           default = 22; # matches router config
      #           description = "Network prefix length";
      #         };
      #       };
      #     }
      #   );
      #   default = null;
      #   description = "Static IP configuration. If null, uses DHCP.";
      # };

      # gateway = mkOption {
      #   type = types.str;
      #   default = "192.168.68.1";
      #   description = "Default gateway address";
      # };

      forwarding = mkOption {
        type = types.bool;
        default = false;
        description = "Enable NAT and IP forwarding for gateway functionality";
      };

      nat = {
        externalInterface = mkOption {
          type = types.str;
          default = config.networking.internal.interface;
          defaultText = "config.networking.internal.interface";
          description = "External interface for NAT";
        };

        internalInterfaces = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Internal interfaces for NAT";
        };
      };
    };
  };

  config =
    let
      cfg = config.networking.internal;
    in
    mkMerge [
      # Base networking configuration for all hosts
      {
        networking = {
          # Enable networkd for consistent networking across hosts
          useNetworkd = mkDefault true;

          # Global DHCP setting - will be overridden per interface if needed
          # Use mkOptionDefault (priority 1500) so hardware-configuration.nix can override
          useDHCP = mkOptionDefault false;

          # Default gateway - only set if we have a static IP
          # defaultGateway = mkIf (cfg.staticIP != null) (mkDefault {
          #   address = cfg.gateway;
          #   interface = cfg.interface;
          # });

          # Configure primary interface
          interfaces.${cfg.interface} = mkMerge [
            # Default: enable DHCP
            {
              useDHCP = mkDefault true;
            }
            # Static IP configuration (overrides DHCP)
            # (mkIf (cfg.staticIP != null) {
            #   useDHCP = false;
            #   ipv4.addresses = [
            #     {
            #       address = cfg.staticIP.address;
            #       prefixLength = cfg.staticIP.prefixLength;
            #     }
            #   ];
            # })
          ];

          # Firewall configuration
          firewall = {
            enable = true;
            allowedTCPPorts = [
              22 # SSH
              80 # HTTP
              443 # HTTPS
            ];
            allowedUDPPortRanges = [
              {
                # Mosh default port range
                from = 60000;
                to = 61000;
              }
            ];
            # Ensure ping works
            allowPing = mkDefault true;
          };
        };

        # DNS configuration for non-AdGuard hosts
        services.resolved = mkIf (!config.services.adguardhome.enable or false) {
          enable = true;
          domains = [ "~." ];
          dnssec = "allow-downgrade";
          # Only set fallbackDns for non-AdGuard or failover mode
          # Strict mode should have NO fallback to ensure all DNS goes through AdGuard
          fallbackDns =
            if cfg.adguard.enabled && cfg.adguard.mode == "strict" then
              [ ] # No fallback in strict mode
            else
              [
                "1.1.1.1"
                "8.8.8.8"
                "1.0.0.1"
                "8.8.4.4"
              ];
          extraConfig =
            let
              dnsServers =
                if cfg.adguard.enabled then
                  if cfg.adguard.mode == "strict" then
                    [ cfg.adguard.address ]
                  else
                    [
                      cfg.adguard.address
                      "192.168.68.1"
                    ] # failover mode
                else
                  [
                    "1.1.1.1"
                    "8.8.8.8"
                  ]; # default public DNS # default public DNS
            in
            ''
              [Resolve]
              DNS=${concatStringsSep " " dnsServers}
              DNSStubListener=yes
              Cache=yes
              DNSOverTLS=no
            '';
        };

        # Prevent DHCP from overwriting DNS settings when using AdGuard
        # dhcpcd config (for non-networkd systems)
        networking.dhcpcd.extraConfig =
          mkIf (cfg.adguard.enabled && (!config.services.adguardhome.enable or false))
            ''
              nohook resolv.conf
            '';

        # networkd config: ignore DNS from DHCP when AdGuard is enabled
        # This prevents the router/ISP from pushing their DNS servers
        systemd.network.networks."40-${cfg.interface}" = mkIf (cfg.adguard.enabled && config.networking.useNetworkd) {
          dhcpV4Config = {
            UseDNS = false;
          };
          dhcpV6Config = {
            UseDNS = false;
          };
          # Explicitly set DNS servers for this interface
          dns =
            if cfg.adguard.mode == "strict" then
              [ cfg.adguard.address ]
            else
              [ cfg.adguard.address "192.168.68.1" ];
        };

        # Ensure systemd-resolved restarts when DNS config changes
        # This is needed because resolved caches DNS settings and won't pick up
        # new config from networkd without a restart
        systemd.services.systemd-resolved = {
          restartTriggers = [
            config.environment.etc."systemd/resolved.conf".source
          ];
        };

        # Enable mDNS for .local domain resolution
        services.avahi = {
          enable = true;
          nssmdns4 = true;
          nssmdns6 = true;
          ipv4 = true;
          ipv6 = true;
          publish = {
            enable = true;
            addresses = true;
            domain = true;
            hinfo = true;
            userServices = true;
            workstation = true;
          };
        };

        # Ensure nsswitch.conf is configured correctly for mDNS
        system.nssModules = with pkgs; [ nssmdns ];

        # Ensure compatibility with systemd-resolved from dns.nix
        # Don't override DNS settings if systemd-resolved is managing them
        networking.nameservers = mkIf (!config.services.resolved.enable) (mkDefault [
          "1.1.1.1"
          "8.8.8.8"
        ]);
      }

      # NAT and forwarding configuration for gateways
      (mkIf cfg.forwarding {
        networking = {
          nat = {
            enable = true;
            externalInterface = cfg.nat.externalInterface;
            internalInterfaces = cfg.nat.internalInterfaces;
            # Enable connection tracking helpers
            enableIPv6 = true;
            forwardPorts = [ ]; # Can be extended by other modules
          };

          firewall = {
            # Enable masquerading on the external interface
            extraCommands = ''
              # Accept forwarded packets
              iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
              iptables -A FORWARD -i ${cfg.nat.externalInterface} -o ${cfg.nat.externalInterface} -j ACCEPT

              # IPv6 forwarding rules
              ${optionalString config.networking.enableIPv6 ''
                ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                ip6tables -A FORWARD -i ${cfg.nat.externalInterface} -o ${cfg.nat.externalInterface} -j ACCEPT
              ''}
            '';

            extraStopCommands = ''
              # Clean up our custom rules
              iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
              iptables -D FORWARD -i ${cfg.nat.externalInterface} -o ${cfg.nat.externalInterface} -j ACCEPT 2>/dev/null || true

              ${optionalString config.networking.enableIPv6 ''
                ip6tables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
                ip6tables -D FORWARD -i ${cfg.nat.externalInterface} -o ${cfg.nat.externalInterface} -j ACCEPT 2>/dev/null || true
              ''}
            '';
          };
        };

        # IP forwarding sysctls
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = mkDefault 1;
          "net.ipv6.conf.all.forwarding" = mkDefault (mkIf config.networking.enableIPv6 1);
          "net.ipv4.conf.all.send_redirects" = mkDefault 0;
          "net.ipv4.conf.default.send_redirects" = mkDefault 0;
        };
      })
    ];
}
