# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
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
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = lib.mkMerge [
        (lib.mkOrder 100 ''
          export CURL_BIN="${pkgs.curl}/bin/curl"
          source ${./deployment-helpers.sh}
          set -euo pipefail

          echo "Starting media services configuration (Sonarr, Radarr, Prowlarr, qBittorrent, NZBGet, SABnzbd)..."
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
        source ${./orchestration-helpers.sh}
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
        source ${./orchestration-helpers.sh}
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
}
