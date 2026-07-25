# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
  sops.secrets = {
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

  # Disabled until the AllDebrid API integration is functional.
  # services.alldebrid-proxy = {
  #   enable = false;
  #   adminPasswordFile = config.sops.secrets."alldebrid_transmission_admin_password".path;
  #   apiKeyFile = config.sops.secrets."alldebrid_api_key".path;
  #   downloadDir = "/mnt/media/downloads/alldebrid";
  # };
}
