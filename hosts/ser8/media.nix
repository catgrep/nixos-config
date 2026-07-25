# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
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

      # AllDebrid-Proxy (only create secrets when service is enabled)
      "alldebrid_api_key" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "alldebrid_transmission_admin_password" = {
        owner = "root";
        group = "root";
        mode = "0600";
      };

    };

    # Templates for config files
    templates = {
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

  # Media Stack SystemD Services Architecture:
  #
  # This module configures the complete media automation stack using a 3-service architecture
  # that ensures correct initialization order and dependency management.
  #
  # Service Hierarchy:
  # 1. media-config.service (Phase 1: Configuration)
  #    - Deploys all service configurations from SOPS templates
  #    - Runs before any media services start
  #    - Configures: Sonarr, Radarr, Prowlarr, NZBGet, SABnzbd, qBittorrent
  #
  # 2. servarrs-setup.service (Phase 2: Indexer Management)
  #    - Connects Prowlarr to Sonarr and Radarr for indexer synchronization
  #    - Depends on: media-config + all arr services running
  #    - Runs in parallel with download-clients-setup
  #
  # 3. download-clients-setup.service (Phase 2: Download Client Integration)
  #    - Connects download clients (qBittorrent, NZBGet, SABnzbd) to all arr services
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
      before = lib.mkMerge [
        (lib.mkOrder 450 [ "qbittorrent-nox.service" ])
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = lib.mkMerge [
        (lib.mkOrder 100 ''
          export CURL_BIN="${pkgs.curl}/bin/curl"
          source ${./systemd_helpers.sh}
          set -euo pipefail

          echo "Starting media services configuration (Sonarr, Radarr, Prowlarr, qBittorrent, NZBGet, SABnzbd)..."
        '')
        (lib.mkOrder 700 ''
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
        '')
        (lib.mkOrder 800 ''
          echo "✓ Completed media services configuration"
        '')
      ];
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
      description = "Configure download clients (qBittorrent, NZBGet, SABnzbd) for all Servarr services";
      after = [
        "media-config.service"
        "qbittorrent-nox.service"
        "nzbget.service"
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
        export JQ_BIN="${pkgs.jq}/bin/jq"
        source ${./systemd_helpers.sh}
        set -euo pipefail

        echo "Starting download client connections..."

        # Wait for all APIs to be ready
        wait_for_api_basic_auth "NZBGet" "http://localhost:6789/" 60 "admin" "${
          config.sops.secrets."sabnzbd_admin_password".path
        }"
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

        # Configure NZBGet as the default Usenet client for arr services
        setup_nzbget_client "Sonarr" "8989" "${
          config.sops.secrets."sonarr_api_key".path
        }" "tvCategory" "tv" "${config.sops.secrets."sabnzbd_admin_password".path}" 1

        setup_nzbget_client "Radarr" "7878" "${
          config.sops.secrets."radarr_api_key".path
        }" "movieCategory" "movies" "${config.sops.secrets."sabnzbd_admin_password".path}" 1

        # Keep SABnzbd available as a lower-priority Usenet fallback
        setup_sabnzbd_client "Sonarr" "8989" "${
          config.sops.secrets."sonarr_api_key".path
        }" "tvCategory" "tv" "${config.sops.secrets."sabnzbd_api_key".path}" 2

        setup_sabnzbd_client "Radarr" "7878" "${
          config.sops.secrets."radarr_api_key".path
        }" "movieCategory" "movies" "${config.sops.secrets."sabnzbd_api_key".path}" 2

        # Add Usenet clients to Prowlarr with NZBGet as the default
        add_nzbget_to_prowlarr "${config.sops.secrets."sabnzbd_admin_password".path}" "${
          config.sops.secrets."prowlarr_api_key".path
        }" 1

        add_sabnzbd_to_prowlarr "${config.sops.secrets."sabnzbd_api_key".path}" "${
          config.sops.secrets."prowlarr_api_key".path
        }" 2

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

  # Disabled - API integration is currently broken
  # TODO: Re-enable once alldebrid-rs API issues are resolved
  # services.alldebrid-proxy = {
  #   enable = false;
  #   adminPasswordFile = config.sops.secrets."alldebrid_transmission_admin_password".path;
  #   apiKeyFile = config.sops.secrets."alldebrid_api_key".path;
  #   downloadDir = "/mnt/media/downloads/alldebrid";
  # };
}
