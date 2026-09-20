# SPDX-License-Identifier: GPL-3.0-or-later

{ config, lib, ... }:

{
  services.bazarr.enable = true;

  homelab.monitoring.systemd.units = lib.mkIf config.services.bazarr.enable {
    "bazarr.service".expectedRunning = true;
  };
}
