# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prometheus exporter for AdGuard Home
# See: https://github.com/henrywhitaker3/adguard-exporter

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Fetch pre-built AdGuard exporter binary (ARM64 for pi4)
  adguardExporterTarball = pkgs.fetchurl {
    url = "https://github.com/henrywhitaker3/adguard-exporter/releases/download/v1.2.1/adguard-exporter_1.2.1_linux_arm64.tar.gz";
    hash = "sha256-36GJIu27ctcjh8ywAiUea4S/zKwJueyeaJA+mjiOa4Y=";
  };

  # Extract the binary
  adguardExporter = pkgs.stdenv.mkDerivation {
    pname = "adguard-exporter";
    version = "1.2.1";
    src = adguardExporterTarball;

    # Tarball contains files at root, not in a subdirectory
    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      cp adguard-exporter $out/bin/
      chmod +x $out/bin/adguard-exporter
    '';
  };

  # Wrapper script to read password from systemd credential and pass as environment variable
  # AdGuard exporter expects ADGUARD_PASSWORDS (not _FILE), so we need to read the secret
  # systemd LoadCredential makes the secret available at $CREDENTIALS_DIRECTORY/adguard-password
  adguardExporterWrapper = pkgs.writeShellScript "adguard-exporter-wrapper" ''
    export ADGUARD_PASSWORDS=$(cat $CREDENTIALS_DIRECTORY/adguard-password)
    exec ${adguardExporter}/bin/adguard-exporter
  '';
in
{
  # SOPS secret for AdGuard admin password (plaintext for exporter)
  sops.secrets.adguard_password = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.services.adguard-exporter = {
    description = "Prometheus exporter for AdGuard Home";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "adguardhome.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = "${adguardExporterWrapper}";
      Restart = "on-failure";
      RestartSec = "10s";

      # Load SOPS secret as systemd credential (accessible at $CREDENTIALS_DIRECTORY/adguard-password)
      LoadCredential = "adguard-password:${config.sops.secrets.adguard_password.path}";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };

    # Environment variables for AdGuard exporter
    # See: https://github.com/henrywhitaker3/adguard-exporter#configuration
    # ADGUARD_PASSWORDS is set by wrapper script (reads from SOPS secret)
    environment = {
      ADGUARD_SERVERS = "http://127.0.0.1:3000";
      ADGUARD_USERNAMES = "admin";
      INTERVAL = "30s";
      PORT = "9618";
    };
  };

  # Open firewall for prometheus scraping
  networking.firewall.allowedTCPPorts = [ 9618 ];
}
