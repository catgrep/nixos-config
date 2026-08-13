# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

{
  services.qbittorrent-nox = {
    enable = true;
    openFirewall = false;
    useVpnNamespace = true;
  };

  services.nginx = {
    enable = true;
    virtualHosts."qbittorrent" =
      let
        uiWebPort = config.services.qbittorrent-nox.port;
      in
      {
        listen = [
          {
            addr = "127.0.0.1";
            port = uiWebPort;
          }
          {
            addr = "0.0.0.0";
            port = uiWebPort;
          } # Also listen on all interfaces if needed
        ];
        # Forward UI port from wgnord network namespace to host
        locations."/" = {
          proxyPass = "http://${config.nordvpn.vethBridge.vpnIp}:${builtins.toString uiWebPort}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # qBittorrent specific headers
            proxy_set_header Connection "";

            # Disable buffering for the web UI
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };
  };

  sops = {
    secrets = {
      "qbittorrent_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "qbittorrent_admin_password_hash" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };

    # Have qbittorrent bind to all interfaces so it will automatically
    # use the VPN 'wgnord' private network namespace interface, instead
    # of the standard hardware ones (like en0).
    templates."qbittorrent.conf" = {
      content = ''
        [LegalNotice]
        Accepted=true

        [Preferences]
        Connection\PortRangeMin=6881
        Connection\UPnP=false
        Connection\GlobalDLLimit=0
        Connection\GlobalUPLimit=0
        Connection\Interface=wgnord
        Connection\InterfaceName=wgnord
        Downloads\SavePath=/mnt/media/downloads/complete/
        Downloads\TempPath=/mnt/media/downloads/incomplete/
        Downloads\TempPathEnabled=true
        Downloads\UseIncompleteExtension=true
        Downloads\PreAllocation=false
        General\Locale=en
        General\UseRandomPort=false
        Queueing\QueueingEnabled=true
        Queueing\MaxActiveDownloads=5
        Queueing\MaxActiveTorrents=10
        Queueing\MaxActiveUploads=5
        WebUI\Enabled=true
        WebUI\LocalHostAuth=false
        WebUI\Port=8080
        WebUI\Address=0.0.0.0
        WebUI\Username=admin
        WebUI\Password_PBKDF2="@ByteArray(${config.sops.placeholder."qbittorrent_admin_password_hash"})"
        WebUI\CSRFProtection=false
        WebUI\HostHeaderValidation=false
        WebUI\UseUPnP=false
        Bittorrent\DHT=true
        Bittorrent\LSD=true
        Bittorrent\PeX=true
        Bittorrent\uTP_rate_limited=false
        BitTorrent\Session\DefaultSavePath=/mnt/media/downloads/complete/
        BitTorrent\Session\TempPath=/mnt/media/downloads/incomplete/
        BitTorrent\Session\TempPathEnabled=true
        BitTorrent\Session\DisableAutoTMMByDefault=false
        BitTorrent\Session\DisableAutoTMMTriggers\CategoryChanged=false
        BitTorrent\Session\DisableAutoTMMTriggers\CategorySavePathChanged=false
        BitTorrent\Session\DisableAutoTMMTriggers\DefaultSavePathChanged=false
      '';
      owner = "qbittorrent";
      group = config.services.qbittorrent-nox.group;
      mode = "0600";
    };
  };

  systemd.services.media-config = {
    before = lib.mkOrder 450 [ "qbittorrent-nox.service" ];
    script = lib.mkOrder 700 ''
      # Deploy qBittorrent configuration
      echo "Configuring qBittorrent..."
      CONFIG_DIR="/var/lib/qbittorrent/qBittorrent/config"
      CONFIG_FILE="$CONFIG_DIR/qBittorrent.conf"
      TEMP_FILE="$CONFIG_DIR/qBittorrent.conf.tmp"

      mkdir -p "$CONFIG_DIR"
      chown qbittorrent:media "$CONFIG_DIR"

      # Remove existing config to avoid conflicts
      if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
      fi

      # Atomic deployment
      cp ${config.sops.templates."qbittorrent.conf".path} "$TEMP_FILE"
      chown qbittorrent:media "$TEMP_FILE"
      chmod 600 "$TEMP_FILE"
      mv "$TEMP_FILE" "$CONFIG_FILE"
      echo "✓ qBittorrent configuration deployed"
    '';
  };
}
