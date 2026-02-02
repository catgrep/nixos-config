# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prometheus exporter for Jellyfin Media Server
# Uses rebelcore/jellyfin_exporter (Go-based exporter)
# See: https://github.com/rebelcore/jellyfin_exporter

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Fetch pre-built Jellyfin exporter binary
  jellyfinExporterTarball = pkgs.fetchurl {
    url = "https://github.com/rebelcore/jellyfin_exporter/releases/download/v1.3.9/jellyfin_exporter-1.3.9.linux-amd64.tar.gz";
    hash = "sha256-oWI1j9d6TV0nY2oXbxmF0OHsMNN44mEfvqLPWq9RTxA=";
  };

  # Extract the binary
  jellyfinExporter = pkgs.stdenv.mkDerivation {
    pname = "jellyfin-exporter";
    version = "1.3.9";
    src = jellyfinExporterTarball;
    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src
      cp jellyfin_exporter-1.3.9.linux-amd64/jellyfin_exporter $out/bin/
      chmod +x $out/bin/jellyfin_exporter
    '';
  };

  # Wrapper script to read API key from systemd credential and pass to exporter
  # systemd LoadCredential makes the secret available at $CREDENTIALS_DIRECTORY/jellyfin-api-key
  jellyfinExporterWrapper = pkgs.writeShellScript "jellyfin-exporter-wrapper" ''
    API_KEY=$(cat $CREDENTIALS_DIRECTORY/jellyfin-api-key)
    exec ${jellyfinExporter}/bin/jellyfin_exporter \
      --jellyfin.address=http://localhost:8096 \
      --jellyfin.token="$API_KEY" \
      --web.listen-address=:9711
  '';
in
{
  # SOPS secret for Jellyfin API key (already exists in ser8.yaml)
  # config.sops.secrets.jellyfin_api_key is defined in hosts/ser8/media.nix

  systemd.services.jellyfin-exporter = {
    description = "Prometheus exporter for Jellyfin Media Server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "jellyfin.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = "${jellyfinExporterWrapper}";
      Restart = "on-failure";
      RestartSec = "10s";

      # Load SOPS secret as systemd credential (accessible at $CREDENTIALS_DIRECTORY/jellyfin-api-key)
      LoadCredential = "jellyfin-api-key:${config.sops.secrets.jellyfin_api_key.path}";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  # Open firewall for prometheus scraping
  networking.firewall.allowedTCPPorts = [ 9711 ];
}
