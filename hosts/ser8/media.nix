# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  ...
}:

{
  # SOPS configuration for media services
  sops = {
    defaultSopsFile = ../../secrets/ser8.yaml;
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

      "jellyfin_api_key" = {
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

      # API keys for Sonarr, Radarr, and Prowlarr
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

      "prowlarr_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Prowlarr authentication
      "prowlarr_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # AllDebrid-Proxy
      "alldebrid_api_key" = {
        owner = "alldebrid-proxy";
        group = "alldebrid-proxy";
        mode = "0400";
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

      "prowlarr-config.xml" = {
        content = ''
          <Config>
            <LogLevel>info</LogLevel>
            <EnableSsl>False</EnableSsl>
            <Port>9696</Port>
            <SslPort>9898</SslPort>
            <UrlBase></UrlBase>
            <BindAddress>*</BindAddress>
            <LaunchBrowser>False</LaunchBrowser>
            <AuthenticationMethod>Forms</AuthenticationMethod>
            <AuthenticationRequired>Enabled</AuthenticationRequired>
            <ApiKey>${config.sops.placeholder."prowlarr_api_key"}</ApiKey>
            <Branch>master</Branch>
            <InstanceName>Prowlarr</InstanceName>
            <SslCertPath></SslCertPath>
            <SslCertPassword></SslCertPassword>
          </Config>
        '';
        owner = "prowlarr";
        group = "prowlarr";
        mode = "0600";
      };

      # Have qbittorrent bind to all interfaces so it will automatically
      # use the VPN 'wgnord' private network namespace interface, instead
      # of the standard hardware ones (like en0).
      "qbittorrent.conf" = {
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
        group = "qbittorrent";
        mode = "0600";
      };
    };
  };

  # Jellyfin API key configuration
  services.declarative-jellyfin.apikeys = {
    jellyfinarr = {
      keyPath = config.sops.secrets.jellyfin_api_key.path;
    };
  };

  # Consolidated SystemD services for media configuration
  systemd.services = {
    arr-config = {
      description = "Deploy all media service configurations with secrets";
      before = [
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        export CURL_BIN="${pkgs.curl}/bin/curl"
        source ${./systemd_helpers.sh}
        set -euo pipefail
        echo "🔧 Deploying all media service configurations..."

        configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}
        configure_arr radarr ${config.sops.templates."radarr-config.xml".path}
        configure_arr prowlarr ${config.sops.templates."prowlarr-config.xml".path}
      '';
    };

    qbittorrent-config = {
      description = "Deploy qBittorrent configuration with secrets";
      before = [
        "qbittorrent-nox.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        # Deploy qBittorrent configuration
        echo "Configuring qBittorrent..."
        CONFIG_DIR="/var/lib/qbittorrent/qBittorrent/config"
        CONFIG_FILE="$CONFIG_DIR/qBittorrent.conf"
        TEMP_FILE="$CONFIG_DIR/qBittorrent.conf.tmp"

        mkdir -p "$CONFIG_DIR"
        chown qbittorrent:qbittorrent "$CONFIG_DIR"

        # Remove existing config to avoid conflicts
        if [ -f "$CONFIG_FILE" ]; then
          rm -f "$CONFIG_FILE"
        fi

        # Atomic deployment
        cp ${config.sops.templates."qbittorrent.conf".path} "$TEMP_FILE"
        chown qbittorrent:qbittorrent "$TEMP_FILE"
        chmod 600 "$TEMP_FILE"
        mv "$TEMP_FILE" "$CONFIG_FILE"
        echo "✓ qBittorrent configuration deployed"
      '';
    };

    arr-qbittorrent-setup = {
      description = "Configure qBittorrent as download client for all arr services";
      after = [
        "sonarr.service"
        "radarr.service"
        "qbittorrent-nox.service"
      ];
      wants = [
        "sonarr.service"
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
        export CURL_BIN="${pkgs.curl}/bin/curl"
        source ${./systemd_helpers.sh}
        set -euo pipefail
        echo "🌊 Configuring qBittorrent for all arr services..."

        # Wait for services to be ready
        echo "Waiting for Sonarr, Radarr, and qBittorrent services to be ready..."
        sleep 30

        # Configure qBittorrent for each service
        setup_qbittorrent_client "Sonarr" "8989" "${
          config.sops.secrets."sonarr_api_key".path
        }" "tvCategory" "tv" "${config.sops.secrets."qbittorrent_admin_password".path}"

        setup_qbittorrent_client "Radarr" "7878" "${
          config.sops.secrets."radarr_api_key".path
        }" "movieCategory" "movies" "${config.sops.secrets."qbittorrent_admin_password".path}"

        echo "🎉 qBittorrent configured for all arr services!"
      '';
    };

    arr-prowlarr-setup = {
      description = "Configure Prowlarr indexers and connect to arr services";
      after = [
        "arr-config.service"
        "arr-qbittorrent-setup.service"
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
      ];
      wants = [
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        export CURL_BIN="${pkgs.curl}/bin/curl"
        source ${./systemd_helpers.sh}
        set -euo pipefail
        echo "🔍 Configuring Prowlarr and connecting to arr services..."

        # Wait for services to be ready using API health checks
        echo "Waiting for Prowlarr, Sonarr, and Radarr services to be ready..."

        # Wait for each service API to be ready
        wait_for_api "Prowlarr" "http://localhost:9696/ping" 30
        wait_for_api "Sonarr" "http://localhost:8989/ping" 30
        wait_for_api "Radarr" "http://localhost:7878/ping" 30

        # Connect arr services to Prowlarr
        add_arr_application "Sonarr" "8989" "${
          config.sops.secrets."sonarr_api_key".path
        }" "[5000,5030,5040]" "${config.sops.secrets."prowlarr_api_key".path}"
        add_arr_application "Radarr" "7878" "${
          config.sops.secrets."radarr_api_key".path
        }" "[2000,2010,2020,2030,2040,2045,2050,2060]" "${config.sops.secrets."prowlarr_api_key".path}"

        # Add popular public indexers (examples - these would need proper configuration)
        echo "ℹ️  Consider adding indexers like 1337x, RARBG alternatives, or private trackers via Prowlarr UI"
        echo "ℹ️  Prowlarr will automatically sync indexers to connected arr services"

        echo "🎉 Prowlarr configured and connected to arr services!"
      '';
    };
  };

  # Meta orchestration target for complete media services setup
  systemd.targets.media-services-setup = {
    description = "Complete media services configuration orchestration";
    wants = [
      "arr-config.service"
      "arr-qbittorrent-setup.service"
      "arr-prowlarr-setup.service"
    ];
    after = [
      "arr-config.service"
      "arr-qbittorrent-setup.service"
      "arr-prowlarr-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];
  };

  services.alldebrid-proxy = {
    enable = true;
    apiKeyFile = config.sops.secrets."alldebrid_api_key".path;
    downloadDir = "/mnt/media/downloads/alldebrid";
  };
}
