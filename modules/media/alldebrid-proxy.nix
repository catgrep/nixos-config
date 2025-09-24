# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  # Create dedicated alldebrid-proxy system user
  users.users.alldebrid-proxy = lib.mkIf config.services.radarr.enable {
    isSystemUser = true;
    group = "alldebrid-proxy";
    description = "AllDebrid-Proxy";
    extraGroups = [
      "media"
    ];
  };

  services.alldebrid-proxy = {
    listenAddress = "127.0.0.1:9091";
    client = "transmission";
    logLevel = "debug";
  };

  # Open port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.radarr.enable [ 9091 ];

  environment.systemPackages = with pkgs; [
    inputs.alldebrid-proxy.packages.${system}.alldebrid-proxy-ctl
  ];
}
