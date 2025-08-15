# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  ...
}:

{
  # SOPS configuration for media services
  sops = {
    defaultSopsFile = ../../secrets/beelink-homelab.yaml;
    defaultSopsFormat = "yaml";

    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Jellyfin authentication (pbkdf2-sha512 hash)
      "jellyfin_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "jellyfin_jordan_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Sonarr authentication
      "sonarr_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Radarr authentication
      "radarr_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # qBittorrent authentication
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

      # API keys for Sonarr and Radarr
      "sonarr_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "radarr_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };

    # Templates for config files
    templates = {
      "sonarr-config.xml" = {
        content = ''
          <Config>
            <LogLevel>info</LogLevel>
            <EnableSsl>False</EnableSsl>
            <Port>8989</Port>
            <SslPort>9898</SslPort>
            <UrlBase></UrlBase>
            <BindAddress>*</BindAddress>
            <LaunchBrowser>False</LaunchBrowser>
            <AuthenticationMethod>Forms</AuthenticationMethod>
            <AuthenticationRequired>Enabled</AuthenticationRequired>
            <Username>admin</Username>
            <Password>${config.sops.placeholder."sonarr_admin_password"}</Password>
            <ApiKey>${config.sops.placeholder."sonarr_api_key"}</ApiKey>
            <Branch>main</Branch>
            <InstanceName>Sonarr</InstanceName>
          </Config>
        '';
        owner = "sonarr";
        group = "sonarr";
        mode = "0600";
      };

      "radarr-config.xml" = {
        content = ''
          <Config>
            <LogLevel>info</LogLevel>
            <EnableSsl>False</EnableSsl>
            <Port>7878</Port>
            <SslPort>9898</SslPort>
            <UrlBase></UrlBase>
            <BindAddress>*</BindAddress>
            <LaunchBrowser>False</LaunchBrowser>
            <AuthenticationMethod>Forms</AuthenticationMethod>
            <AuthenticationRequired>Enabled</AuthenticationRequired>
            <Username>admin</Username>
            <Password>${config.sops.placeholder."radarr_admin_password"}</Password>
            <ApiKey>${config.sops.placeholder."radarr_api_key"}</ApiKey>
            <Branch>master</Branch>
            <InstanceName>Radarr</InstanceName>
          </Config>
        '';
        owner = "radarr";
        group = "radarr";
        mode = "0600";
      };

      "qbittorrent.conf" = {
        content = ''
          [LegalNotice]
          Accepted=true

          [Preferences]
          Connection\PortRangeMin=6881
          Connection\UPnP=false
          Downloads\SavePath=/mnt/media/downloads/complete/
          Downloads\TempPath=/mnt/media/downloads/incomplete/
          Downloads\TempPathEnabled=true
          Downloads\UseIncompleteExtension=true
          General\Locale=en
          Queueing\QueueingEnabled=true
          WebUI\Enabled=true
          WebUI\LocalHostAuth=false
          WebUI\Port=8080
          WebUI\Username=admin
          WebUI\Password_PBKDF2="@ByteArray(${config.sops.placeholder."qbittorrent_admin_password_hash"})"
          WebUI\CSRFProtection=false
          WebUI\HostHeaderValidation=false
          WebUI\UseUPnP=false
          BitTorrent\Session\DefaultSavePath=/mnt/media/downloads/complete/
          BitTorrent\Session\TempPath=/mnt/media/downloads/incomplete/
          BitTorrent\Session\TempPathEnabled=true
        '';
        owner = "qbittorrent";
        group = "qbittorrent";
        mode = "0600";
      };
    };
  };

  # SystemD services to use templated config files
  systemd.services = {
    sonarr-config = {
      description = "Deploy Sonarr configuration with secrets";
      before = [ "sonarr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Ensure config directory exists
        mkdir -p /var/lib/sonarr/.config/NzbDrone

        # Always copy templated config (simpler approach)
        cp ${config.sops.templates."sonarr-config.xml".path} /var/lib/sonarr/.config/NzbDrone/config.xml
        chown sonarr:sonarr /var/lib/sonarr/.config/NzbDrone/config.xml
        chmod 600 /var/lib/sonarr/.config/NzbDrone/config.xml
        echo "✓ Updated Sonarr configuration with secrets"
      '';
    };

    radarr-config = {
      description = "Deploy Radarr configuration with secrets";
      before = [ "radarr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Ensure config directory exists
        mkdir -p /var/lib/radarr/.config/Radarr

        # Always copy templated config (simpler approach)
        cp ${config.sops.templates."radarr-config.xml".path} /var/lib/radarr/.config/Radarr/config.xml
        chown radarr:radarr /var/lib/radarr/.config/Radarr/config.xml
        chmod 600 /var/lib/radarr/.config/Radarr/config.xml
        echo "✓ Updated Radarr configuration with secrets"
      '';
    };

    qbittorrent-config = {
      description = "Deploy qBittorrent configuration with secrets";
      before = [ "qbittorrent-nox.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        set -euo pipefail

        CONFIG_DIR="/var/lib/qbittorrent/qBittorrent/config"
        CONFIG_FILE="$CONFIG_DIR/qBittorrent.conf"
        TEMP_FILE="$CONFIG_DIR/qBittorrent.conf.tmp"

        echo "Deploying qBittorrent configuration..."

        # Ensure config directory exists with proper ownership
        mkdir -p "$CONFIG_DIR"
        chown qbittorrent:qbittorrent "$CONFIG_DIR"

        # Remove any existing config to avoid conflicts
        if [ -f "$CONFIG_FILE" ]; then
          echo "Removing existing config file"
          rm -f "$CONFIG_FILE"
        fi

        # Copy template to temp file first (atomic deployment)
        cp ${config.sops.templates."qbittorrent.conf".path} "$TEMP_FILE"
        chown qbittorrent:qbittorrent "$TEMP_FILE"
        chmod 600 "$TEMP_FILE"

        # Atomic move to final location
        mv "$TEMP_FILE" "$CONFIG_FILE"

        echo "✓ Successfully deployed qBittorrent configuration with secrets"
        echo "Config deployed to: $CONFIG_FILE"
        ls -la "$CONFIG_FILE"
      '';
    };

    sonarr-qbittorrent-setup = {
      description = "Configure Sonarr to use qBittorrent as download client";
      after = [
        "sonarr.service"
        "qbittorrent-nox.service"
      ];
      wants = [
        "sonarr.service"
        "qbittorrent-nox.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Wait for services to be ready
        sleep 30

        # Configure qBittorrent download client in Sonarr via API
        # This will add qBittorrent as a download client if it doesn't exist
        ${pkgs.curl}/bin/curl -X POST \
          -H "Content-Type: application/json" \
          -H "X-Api-Key: $(cat ${config.sops.secrets."sonarr_api_key".path})" \
          -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": false,
            "removeFailedDownloads": true,
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "implementationName": "qBittorrent",
            "settings": {
              "host": "127.0.0.1",
              "port": 8080,
              "username": "admin",
              "password": "$(cat ${config.sops.secrets."qbittorrent_admin_password".path})",
              "category": "tv",
              "postImportCategory": "",
              "recentMoviePriority": 0,
              "olderMoviePriority": 0,
              "initialState": 0
            },
            "configContract": "QBittorrentSettings"
          }' \
          "http://localhost:8989/api/v3/downloadclient" || echo "Failed to configure Sonarr download client"

        echo "✓ Configured Sonarr qBittorrent download client"
      '';
    };

    radarr-qbittorrent-setup = {
      description = "Configure Radarr to use qBittorrent as download client";
      after = [
        "radarr.service"
        "qbittorrent-nox.service"
      ];
      wants = [
        "radarr.service"
        "qbittorrent-nox.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Wait for services to be ready
        sleep 30

        # Configure qBittorrent download client in Radarr via API
        ${pkgs.curl}/bin/curl -X POST \
          -H "Content-Type: application/json" \
          -H "X-Api-Key: $(cat ${config.sops.secrets."radarr_api_key".path})" \
          -d '{
            "enable": true,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": false,
            "removeFailedDownloads": true,
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "implementationName": "qBittorrent",
            "settings": {
              "host": "127.0.0.1",
              "port": 8080,
              "username": "admin",
              "password": "$(cat ${config.sops.secrets."qbittorrent_admin_password".path})",
              "category": "movies",
              "postImportCategory": "",
              "recentMoviePriority": 0,
              "olderMoviePriority": 0,
              "initialState": 0
            },
            "configContract": "QBittorrentSettings"
          }' \
          "http://localhost:7878/api/v3/downloadclient" || echo "Failed to configure Radarr download client"

        echo "✓ Configured Radarr qBittorrent download client"
      '';
    };
  };
}
