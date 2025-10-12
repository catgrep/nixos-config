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

      "alldebrid_transmission_admin_password" = {
        owner = "alldebrid-proxy";
        group = "alldebrid-proxy";
        mode = "0400";
      };

      # SABnzbd authentication and Usenet provider
      "sabnzbd_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_nzb_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_username" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "sabnzbd_usenet_provider" = {
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

      "sabnzbd.ini" = {
        content = ''
          [misc]
          host = 0.0.0.0
          port = 8085
          api_key = ${config.sops.placeholder."sabnzbd_api_key"}
          nzb_key = ${config.sops.placeholder."sabnzbd_nzb_key"}
          username = admin
          password = ${config.sops.placeholder."sabnzbd_admin_password"}
          download_dir = /mnt/media/downloads/usenet/incomplete
          complete_dir = /mnt/media/downloads/usenet/complete/default
          script_dir =
          log_dir = /var/lib/sabnzbd/logs
          admin_dir = /var/lib/sabnzbd/admin
          nzb_backup_dir = /var/lib/sabnzbd/backup
          dirscan_dir =
          auto_browser = 0
          rating_enable = 0
          enable_https = 0
          https_port = 9090
          bandwidth_max =
          refresh_rate = 0
          cache_limit = 1G
          pause_on_post_processing = 0
          ignore_samples = 0
          deobfuscate_final_filenames = 1
          auto_sort = 0
          propagation_delay = 0
          folder_rename = 1
          direct_unpack = 0
          no_penalties = 0
          par_option = 1
          pre_check = 0
          nice =
          ionice =
          win_process_prio = 3
          enable_all_par = 0
          top_only = 0
          safe_postproc = 1
          pause_on_pwrar = 1
          enable_unrar = 1
          enable_7zip = 1
          enable_filejoin = 1
          enable_tsjoin = 1
          overwrite_files = 0
          ignore_unrar_dates = 0
          backup_for_duplicates = 1
          empty_postproc = 0
          wait_for_dfolder = 0
          rss_rate = 60
          ampm = 0
          start_paused = 0
          preserve_paused_state = 0
          enable_par_cleanup = 1
          process_unpacked_par2 = 1
          enable_recursive = 1
          flat_unpack = 0
          script_can_fail = 0
          new_nzb_on_failure = 0
          unwanted_extensions =
          action_on_unwanted_extensions = 0
          unwanted_extensions_mode = 0
          sanitize_safe = 0
          replace_illegal = 1
          max_art_tries = 3
          max_art_opt = 1
          load_balancing = 2
          fail_hopeless_jobs = 1
          fast_fail = 1
          auto_disconnect = 1
          pre_script =
          end_queue_script =
          no_dupes = 0
          no_series_dupes = 0
          series_propercheck = 1
          no_smart_dupes = 0
          smart_dupes_whitelist =
          dupes_propercheck = 1
          pause_on_queue_finish = 0
          history_retention = 0
          enable_https_verification = 1
          quota_size =
          quota_day =
          quota_resume = 0
          quota_period = m
          pre_check_opt = 1

          [servers]
          [[${config.sops.placeholder."sabnzbd_usenet_provider"}]]
          name = ${config.sops.placeholder."sabnzbd_usenet_provider"}
          displayname = ${config.sops.placeholder."sabnzbd_usenet_provider"}
          host = ${config.sops.placeholder."sabnzbd_usenet_provider"}
          port = 563
          timeout = 120
          username = ${config.sops.placeholder."sabnzbd_usenet_username"}
          password = ${config.sops.placeholder."sabnzbd_usenet_password"}
          connections = 20
          ssl = 1
          ssl_verify = 2
          ssl_ciphers =
          enable = 1
          required = 0
          optional = 0
          retention = 0
          send_group = 0
          priority = 0
          notes =

          [categories]
          [[tv]]
          name = tv
          order = 0
          pp = 3
          script = Default
          dir = /mnt/media/downloads/usenet/complete/tv
          newzbin =
          priority = 0

          [[movies]]
          name = movies
          order = 1
          pp = 3
          script = Default
          dir = /mnt/media/downloads/usenet/complete/movies
          newzbin =
          priority = 0

          [[prowlarr]]
          name = *
          order = 2
          pp = 3
          script = Default
          dir = /mnt/media/downloads/usenet/complete/prowlarr
          newzbin =
          priority = 0

          [[*]]
          name = *
          order = 2
          pp = 3
          script = Default
          dir = /mnt/media/downloads/usenet/complete/default
          newzbin =
          priority = 0
        '';
        owner = "sabnzbd";
        group = "sabnzbd";
        mode = "0600";
      };
    };
  };

  services.sabnzbd = {
    configFile = "/var/lib/sabnzbd/sabnzbd.ini";
  };

  # Jellyfin API key configuration
  services.declarative-jellyfin.apikeys = {
    jellyfinarr = {
      keyPath = config.sops.secrets.jellyfin_api_key.path;
    };
  };

  # Media Stack SystemD Services Architecture:
  #
  # This module configures the complete media automation stack using a 3-service architecture
  # that ensures correct initialization order and dependency management.
  #
  # Service Hierarchy:
  # 1. media-config.service (Phase 1: Configuration)
  #    - Deploys all service configurations from SOPS templates
  #    - Runs before any media services start
  #    - Configures: Sonarr, Radarr, Prowlarr, SABnzbd, qBittorrent
  #
  # 2. servarrs-setup.service (Phase 2: Indexer Management)
  #    - Connects Prowlarr to Sonarr and Radarr for indexer synchronization
  #    - Depends on: media-config + all arr services running
  #    - Runs in parallel with download-clients-setup
  #
  # 3. download-clients-setup.service (Phase 2: Download Client Integration)
  #    - Connects download clients (qBittorrent, SABnzbd) to all arr services
  #    - Configures categories for automatic media organization
  #    - Depends on: media-config + all services running
  #    - Runs in parallel with servarrs-setup
  #
  # 4. media-setup.target (Meta Target)
  #    - Coordinates all setup services
  #    - Provides single target for "complete media stack configuration"
  #
  # Key Features:
  # - API key sanitization in all logs (prevents secrets exposure)
  # - Idempotent operations (safe to run multiple times)
  # - Explicit API readiness checks (no blind sleep delays)
  # - Parallel execution where possible (servarrs-setup || download-clients-setup)
  #
  systemd.services = {
    media-config = {
      description = "Deploy all media service configurations with secrets";
      before = [
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
        "qbittorrent-nox.service"
        "sabnzbd.service"
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

        echo "Starting media services configuration (Sonarr, Radarr, Prowlarr, qBittorrent, SABnzbd)..."

        # Deploy arr service configurations
        configure_arr sonarr ${config.sops.templates."sonarr-config.xml".path}
        configure_arr radarr ${config.sops.templates."radarr-config.xml".path}
        configure_arr prowlarr ${config.sops.templates."prowlarr-config.xml".path}
        configure_arr sabnzbd ${config.sops.templates."sabnzbd.ini".path}

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

        echo "✓ Completed media services configuration"
      '';
    };

    servarrs-setup = {
      description = "Configure Prowlarr connections to Sonarr and Radarr";
      after = [
        "media-config.service"
        "prowlarr.service"
        "sonarr.service"
        "radarr.service"
      ];
      requires = [ "media-config.service" ];
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

        echo "Starting Prowlarr connections to Sonarr and Radarr..."

        # Wait for APIs to be ready
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

        echo "✓ Completed Prowlarr connections to Sonarr and Radarr"
      '';
    };

    download-clients-setup = {
      description = "Configure download clients (qBittorrent, SABnzbd) for all Servarr services";
      after = [
        "media-config.service"
        "qbittorrent-nox.service"
        "sabnzbd.service"
        "sonarr.service"
        "radarr.service"
        "prowlarr.service"
      ];
      requires = [ "media-config.service" ];
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

        echo "Starting download client connections..."

        # Wait for all APIs to be ready
        wait_for_api "SABnzbd" "http://localhost:8085/api?mode=version&apikey=$(cat ${
          config.sops.secrets."sabnzbd_api_key".path
        })" 60
        # wait_for_api "qBittorrent" "http://localhost:8080/api/v2/app/version" 30

        # Configure qBittorrent for arr services
        setup_qbittorrent_client "Sonarr" "8989" "${
          config.sops.secrets."sonarr_api_key".path
        }" "tvCategory" "tv" "${config.sops.secrets."qbittorrent_admin_password".path}"

        setup_qbittorrent_client "Radarr" "7878" "${
          config.sops.secrets."radarr_api_key".path
        }" "movieCategory" "movies" "${config.sops.secrets."qbittorrent_admin_password".path}"

        # Verify SABnzbd categories are configured
        echo "Verifying SABnzbd categories..."
        CATEGORIES=$($CURL_BIN -s "http://localhost:8085/api?mode=get_cats&apikey=$(cat ${
          config.sops.secrets."sabnzbd_api_key".path
        })")

        if echo "$CATEGORIES" | grep -q '"tv"' && echo "$CATEGORIES" | grep -q '"movies"'; then
          echo "✓ SABnzbd categories configured correctly"
        else
          echo "⚠ Warning: SABnzbd categories may not be configured correctly"
        fi

        # Configure SABnzbd for arr services
        setup_sabnzbd_client "Sonarr" "8989" "${config.sops.secrets."sonarr_api_key".path}" "tv" "${
          config.sops.secrets."sabnzbd_api_key".path
        }"

        setup_sabnzbd_client "Radarr" "7878" "${config.sops.secrets."radarr_api_key".path}" "movies" "${
          config.sops.secrets."sabnzbd_api_key".path
        }"

        # Add SABnzbd to Prowlarr as download client
        add_sabnzbd_to_prowlarr "${config.sops.secrets."sabnzbd_api_key".path}" "${
          config.sops.secrets."prowlarr_api_key".path
        }"

        echo "✓ Completed download client connections"
      '';
    };
  };

  # Meta orchestration target for complete media stack setup
  systemd.targets.media-setup = {
    description = "Complete media stack setup orchestration";
    wants = [
      "media-config.service"
      "servarrs-setup.service"
      "download-clients-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];
  };

  services.alldebrid-proxy = {
    enable = true;
    adminPasswordFile = config.sops.secrets."alldebrid_transmission_admin_password".path;
    apiKeyFile = config.sops.secrets."alldebrid_api_key".path;
    downloadDir = "/mnt/media/downloads/alldebrid";
  };
}
