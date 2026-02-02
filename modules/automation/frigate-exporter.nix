# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prometheus exporter for Frigate NVR
# Uses prometheus-frigate-exporter to scrape /api/stats endpoint
# See: https://github.com/bairhys/prometheus-frigate-exporter

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Fetch the Frigate exporter Python script
  frigateExporterScript = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/bairhys/prometheus-frigate-exporter/8a5b45c3f853f1ce537c99e773baef629a2d68dd/prometheus_frigate_exporter.py";
    hash = "sha256-RtWPFlfZM2BTZoYy9yz+/Xz+EqWb1BcZpWvhxAvsf/c=";
  };

  # Python environment with prometheus_client
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ prometheus-client ]);
in
{
  systemd.services.frigate-exporter = lib.mkIf config.services.frigate.enable {
    description = "Prometheus exporter for Frigate NVR";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "frigate.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      ExecStart = "${pythonEnv}/bin/python ${frigateExporterScript}";
      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };

    # Environment variables expected by prometheus_frigate_exporter.py
    # See: https://github.com/bairhys/prometheus-frigate-exporter/blob/8a5b45c/prometheus_frigate_exporter.py#L338-L357
    # FRIGATE_STATS_URL: Required, Frigate API stats endpoint
    # PORT: Optional, defaults to 9100 (we use 9710 to avoid conflict with node-exporter)
    environment = {
      FRIGATE_STATS_URL = "http://127.0.0.1:5000/api/stats";
      PORT = "9710";
    };
  };

  # Open firewall for prometheus scraping
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.frigate.enable [ 9710 ];
}
