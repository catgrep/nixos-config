# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prometheus exportarr exporters for arr stack monitoring
# See: https://github.com/onedr0p/exportarr

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.prometheus.exporters = {
    # Sonarr exporter (TV shows)
    exportarr-sonarr = {
      enable = lib.mkDefault true;
      port = 9707;
      url = "http://localhost:8989";
      apiKeyFile = config.sops.secrets.sonarr_api_key.path;
      openFirewall = true;
    };

    # Radarr exporter (Movies)
    exportarr-radarr = {
      enable = lib.mkDefault true;
      port = 9708;
      url = "http://localhost:7878";
      apiKeyFile = config.sops.secrets.radarr_api_key.path;
      openFirewall = true;
    };

    # Prowlarr exporter (Indexers)
    exportarr-prowlarr = {
      enable = lib.mkDefault true;
      port = 9709;
      url = "http://localhost:9696";
      apiKeyFile = config.sops.secrets.prowlarr_api_key.path;
      openFirewall = true;
    };
  };
}
