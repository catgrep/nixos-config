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
    systemd.services.qbittorrent-nox = {
      description = "qBittorrent-nox torrent client";
      documentation = [ "man:qbittorrent-nox(1)" ];
      wants = [ "network-online.target" ];
      requires = [ "qbittorrent-config.service" ];
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

        # Sandboxing
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];

        # Filesystem access
        ReadWritePaths = [
          "/var/lib/qbittorrent"
          "/mnt/media/downloads"
        ];
      };
    };

    # Open qBittorrent ports when enabled
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port # Web UI
        6881 # Default torrent port
      ];
      allowedUDPPorts = [
        6881 # Default torrent port
      ];
    };

    # Note: Download directory tmpfiles are managed in impermanence.nix
  };
}
