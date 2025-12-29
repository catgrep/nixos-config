# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.alldebrid-proxy;
in
{
  # Default configuration for alldebrid-proxy
  # Host-specific files (e.g., hosts/ser8/media.nix) control enable state
  services.alldebrid-proxy = {
    listenAddress = "127.0.0.1:9091";
    client = "transmission";
    logLevel = "debug";
  };

  # Create dedicated alldebrid-proxy system user/group only when enabled
  users.groups.alldebrid-proxy = lib.mkIf cfg.enable { };

  users.users.alldebrid-proxy = lib.mkIf cfg.enable {
    isSystemUser = true;
    group = "alldebrid-proxy";
    description = "AllDebrid-Proxy";
    extraGroups = [
      "media"
    ];
  };

  # Open port when enabled
  networking.firewall.allowedTCPPorts = lib.mkIf cfg.enable [ 9091 ];

  environment.systemPackages = lib.mkIf cfg.enable [
    inputs.alldebrid-proxy.packages.${pkgs.system}.alldebrid-proxy-ctl
  ];
}
