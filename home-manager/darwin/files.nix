# SPDX-License-Identifier: GPL-3.0-or-later

# Editor and package-manager config files that Home Manager links in place.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    xdg.configFile = {
      "zed/settings.json".source = ./zed/settings.json;
      "zed/keymap.json".source = ./zed/keymap.json;
    };

    # Global npm packages install under ~/.npm-global, whose bin directory
    # the shell module puts on PATH.
    home.file.".npmrc".text = ''
      prefix=${config.home.homeDirectory}/.npm-global
    '';
  };
}
