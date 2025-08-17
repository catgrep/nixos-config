# modules/nordvpn/service.nix
# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.nordvpn.enable {
    # Create dedicated wgnord system user
    users.users.wgnord = {
      isSystemUser = true;
      group = "wgnord";
      home = "/var/lib/wgnord";
      description = "NordVPN WireGuard service";
    };

    users.groups.wgnord = { };

    # Ensure wgnord state directory exists with proper permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/wgnord 0750 wgnord wgnord -"
      "d /etc/netns 0755 root root -"
      "d /etc/netns/wgnord 0755 root root -"
    ];

    # Template for creating named network namespaces
    # Following: https://mth.st/blog/nixos-wireguard-netns/
    systemd.services."netns@" = {
      description = "%I network namespace";
      before = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add %I";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del %I";
      };
    };

    # Service 1: Generate NordVPN WireGuard configuration (host network)
    systemd.services.wgnord-setup = {
      description = "Generate NordVPN WireGuard configuration";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        SupplementaryGroups = [ "wgnord" ];

        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "wgnord-setup";
            runtimeInputs = [
              pkgs.wgnord
              pkgs.coreutils
              pkgs.gnused
            ];
            text = ''
              set -e

              # Create template.conf if it doesn't exist (required by wgnord)
              if [ ! -f /var/lib/wgnord/template.conf ]; then
                cp "${./template.conf}" /var/lib/wgnord/template.conf
                echo "Created template.conf"
              fi

              # Login to NordVPN (requires host network access)
              wgnord login "$(cat "${config.nordvpn.accessTokenFile}")"
              echo "Successfully logged into NordVPN account"

              # Generate config without connecting (-n flag)
              wgnord connect us -n -o /var/lib/wgnord/wgnord.conf

              # Remove DNS entries from generated config (we'll handle DNS separately)
              sed -i '/^DNS = /d' /var/lib/wgnord/wgnord.conf

              # Set proper permissions
              chown wgnord:wgnord /var/lib/wgnord/wgnord.conf
              chmod 640 /var/lib/wgnord/wgnord.conf
            '';
          }
        );

        # Restart policy
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Service 2: Simple WireGuard in namespace
    # Following: https://www.wireguard.com/netns/#the-new-namespace-solution
    systemd.services.wgnord = {
      description = "NordVPN WireGuard interface";
      bindsTo = [ "netns@wgnord.service" ];
      requires = [
        "network-online.target"
        "wgnord-setup.service"
      ];
      after = [
        "netns@wgnord.service"
        "network-online.target"
        "wgnord-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        SupplementaryGroups = [ "wgnord" ];

        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "wgnord-start";
            runtimeInputs = [
              pkgs.wireguard-tools
              pkgs.coreutils
              pkgs.iputils
              pkgs.iproute2
              pkgs.iptables
              pkgs.gnused
              pkgs.curl
              pkgs.procps
            ];
            text = ''
              set -e

              # Clean up any existing WireGuard interface
              ip link delete wgnord 2>/dev/null || true
              ip netns exec wgnord ip link delete wgnord 2>/dev/null || true

              # Set up namespace-specific DNS configuration
              echo "Setting up DNS for namespace..."
              ${lib.concatMapStringsSep "\n" (
                dns:
                if dns == lib.head config.nordvpn.dnsServers then
                  "echo \"nameserver ${dns}\" > /etc/netns/wgnord/resolv.conf"
                else
                  "echo \"nameserver ${dns}\" >> /etc/netns/wgnord/resolv.conf"
              ) config.nordvpn.dnsServers}

              # Parse the config file
              echo "Parsing WireGuard configuration..."
              PRIVATE_KEY=$(grep '^PrivateKey' /var/lib/wgnord/wgnord.conf | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              ADDRESS=$(grep '^Address' /var/lib/wgnord/wgnord.conf | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              PEER_PUBKEY=$(grep '^PublicKey' /var/lib/wgnord/wgnord.conf | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              ENDPOINT=$(grep '^Endpoint' /var/lib/wgnord/wgnord.conf | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

              # Create WireGuard interface in HOST namespace (so it can reach the internet)
              echo "Creating WireGuard interface..."
              ip link add wgnord type wireguard

              # Configure WireGuard
              printf '%s' "$PRIVATE_KEY" | wg set wgnord private-key /dev/stdin
              wg set wgnord peer "$PEER_PUBKEY" endpoint "$ENDPOINT" allowed-ips 0.0.0.0/0,::/0 persistent-keepalive 25

              # Move interface to VPN namespace (UDP socket stays in host namespace)
              echo "Moving WireGuard interface to VPN namespace..."
              ip link set wgnord netns wgnord

              # Configure interface in the namespace
              ip netns exec wgnord ip addr add "$ADDRESS" dev wgnord
              ip netns exec wgnord ip link set wgnord mtu 1350 up
              ip netns exec wgnord ip link set lo up

              # Set up routing in namespace
              ip netns exec wgnord ip route add default dev wgnord

              # Always set up veth bridge for local network access
              echo "Setting up veth bridge for namespace connectivity..."

              # Remove old veth interfaces if they exist
              ip link del veth-host 2>/dev/null || true
              ip netns exec wgnord ip link del veth-vpn 2>/dev/null || true

              # Create veth pair for namespace connectivity
              ip link add veth-host type veth peer name veth-vpn
              ip link set veth-host up
              ip addr flush dev veth-host # Setting IP twice causes errors, so use ip addr flush before reassigning
              ip addr add ${config.nordvpn.vethBridge.hostIp}/24 dev veth-host

              # Move veth-vpn to namespace
              ip link set veth-vpn netns wgnord
              ip netns exec wgnord ip link set veth-vpn up
              ip netns exec wgnord ip addr add ${config.nordvpn.vethBridge.vpnIp}/24 dev veth-vpn

              # Add route for local network access through veth
              ${lib.optionalString (config.nordvpn.localNetworkAccess != null) ''
                echo "Adding route for local network ${config.nordvpn.localNetworkAccess}..."
                ip netns exec wgnord ip route add ${config.nordvpn.localNetworkAccess} via ${config.nordvpn.vethBridge.hostIp} dev veth-vpn
              ''}

              # Enable forwarding for veth bridge
              sysctl -w net.ipv4.ip_forward=1

              # Set up masquerading for namespace to reach local network
              ${lib.optionalString (config.nordvpn.localNetworkAccess != null) ''
                iptables -t nat -C POSTROUTING -s ${config.nordvpn.vethBridge.subnet} -d ${config.nordvpn.localNetworkAccess} -j MASQUERADE 2>/dev/null ||
                iptables -t nat -A POSTROUTING -s ${config.nordvpn.vethBridge.subnet} -d ${config.nordvpn.localNetworkAccess} -j MASQUERADE
              ''}

              # Test connectivity
              echo "Testing VPN connection..."
              sleep 2

              if ip netns exec wgnord timeout 10 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                echo "✓ VPN connection verified"
                EXTERNAL_IP=$(ip netns exec wgnord timeout 10 curl -s ifconfig.me 2>/dev/null || echo "Could not determine")
                echo "External IP: $EXTERNAL_IP"
              else
                echo "⚠ Warning: Cannot verify VPN connection"
                # Show debug info
                echo "WireGuard status:"
                ip netns exec wgnord wg show
              fi
            '';
          }
        );

        ExecStop = lib.getExe (
          pkgs.writeShellApplication {
            name = "wgnord-stop";
            runtimeInputs = [
              pkgs.wireguard-tools
              pkgs.iproute2
              pkgs.iptables
            ];
            text = ''
              # Clean up masquerading
              ${lib.optionalString (config.nordvpn.localNetworkAccess != null) ''
                iptables -t nat -D POSTROUTING -s ${config.nordvpn.vethBridge.subnet} -d ${config.nordvpn.localNetworkAccess} -j MASQUERADE || true
              ''}

              # Clean up veth interfaces
              ip link delete veth-host || true

              # The namespace deletion will clean up the WireGuard interface
              true
            '';
          }
        );

        # Restart policy
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Health monitoring for VPN connection
    systemd.services.wgnord-monitor = {
      description = "Monitor NordVPN connection health";
      after = [ "wgnord.service" ];
      requires = [ "wgnord.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "60s";

        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "wgnord-monitor";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.iputils
              pkgs.systemd
              pkgs.iproute2
            ];
            text = ''
              while true; do
                if ! ip netns exec wgnord timeout 10 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                  echo "VPN connection lost, restarting..."
                  systemctl restart wgnord.service
                  sleep 30
                fi
                sleep 60
              done
            '';
          }
        );
      };
    };

    # Utility scripts
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "nordvpn-status";
        runtimeInputs = [
          pkgs.systemd
          pkgs.wgnord
          pkgs.curl
          pkgs.iproute2
        ];
        text = ''
          echo "=== NordVPN Status ==="
          echo -n "Service status: "
          systemctl is-active wgnord.service

          if systemctl is-active --quiet wgnord.service; then
            echo -n "External IP: "
            ip netns exec wgnord curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Cannot determine"
            echo ""
            echo "WireGuard info:"
            ip netns exec wgnord wg show wgnord
          fi
        '';
      })

      (pkgs.writeShellApplication {
        name = "nordvpn-exec";
        runtimeInputs = [ pkgs.iproute2 ];
        text = ''
          # Utility to run commands in the VPN namespace
          exec ip netns exec wgnord "$@"
        '';
      })
    ];
  };
}
