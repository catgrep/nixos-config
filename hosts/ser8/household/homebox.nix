# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  services.homebox = {
    enable = true;
    package = pkgs.homebox;

    settings = {
      HBOX_WEB_PORT = "7745";
      HBOX_OPTIONS_ALLOW_ANALYTICS = "false";
      HBOX_OPTIONS_GITHUB_RELEASE_CHECK = "false";
      HBOX_OPTIONS_HOSTNAME = "homebox.shad-bangus.ts.net";
      HBOX_DEMO = "false";
      HBOX_OPTIONS_ALLOW_REGISTRATION = "false";
    };
  };
}
