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
