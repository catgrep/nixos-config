# modules/media/qbittorrent.nix
# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.qbittorrent-nox;
in
{
  options.services.qbittorrent-nox = {
    enable = lib.mkEnableOption "qBittorrent headless BitTorrent client";

    user = lib.mkOption {
      type = lib.types.str;
      default = "qbittorrent";
      description = "User account under which qBittorrent runs";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "qbittorrent";
      description = "Group under which qBittorrent runs";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "qBittorrent web UI port";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open ports in the firewall for qBittorrent";
    };

    useVpnNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run qBittorrent in NordVPN network namespace for anonymization";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create dedicated qbittorrent system user
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = "/var/lib/qbittorrent";
      description = "qBittorrent";
      extraGroups = [ "media" ];
    };

    users.groups.${cfg.group} = { };

    # Add qbittorrent-nox package
    environment.systemPackages = [ pkgs.qbittorrent-nox ];

    # qBittorrent systemd service
    systemd.services.qbittorrent-nox = lib.mkMerge [
      {
        description = "qBittorrent-nox torrent client";
        documentation = [ "man:qbittorrent-nox(1)" ];
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "nss-lookup.target"
        ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "exec";
          User = cfg.user;
          Group = cfg.group;
          UMask = "0002";
          ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --profile=/var/lib/qbittorrent";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "1800";

          # Reduced sandboxing for namespace compatibility
          LockPersonality = true;
          NoNewPrivileges = true;
          # Remove these restrictions that can cause issues in namespaces:
          # PrivateDevices = true;  # Can interfere with namespace devices
          PrivateTmp = false; # Allow access to /tmp for downloads
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = false; # Allow hostname access in namespace
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = false; # Allow tunable access for networking
          ProtectProc = "default"; # Changed from "invisible"
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
            "AF_UNIX" # Add UNIX sockets
          ];
          RestrictNamespaces = false; # Allow namespace operations
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          # Remove SystemCallFilter to avoid blocking needed syscalls
          # SystemCallFilter = [ "@system-service" "~@privileged" ];

          # Filesystem access
          ReadWritePaths = [
            "/var/lib/qbittorrent"
            "/mnt/media/downloads"
            "/mnt/media/downloads/complete"
            "/mnt/media/downloads/incomplete"
            "/tmp" # Allow tmp access
          ];
        };
      }

      # NordVPN namespace configuration
      (lib.mkIf cfg.useVpnNamespace {
        after = [ "wgnord.service" ];
        bindsTo = [ "wgnord.service" ];
        serviceConfig = {
          # Join NordVPN network namespace
          NetworkNamespacePath = "/var/run/netns/wgnord";
          # Add capability for raw sockets in namespace
          AmbientCapabilities = [
            "CAP_NET_RAW"
            "CAP_NET_BIND_SERVICE"
          ];
        };
      })
    ];

    # Open qBittorrent ports when enabled (not needed when in namespace)
    networking.firewall = lib.mkIf (cfg.openFirewall && !cfg.useVpnNamespace) {
      allowedTCPPorts = [
        cfg.port # Web UI
        6881 # Default torrent port
      ];
      allowedUDPPorts = [
        6881 # Default torrent port
      ];
    };
  };
}
