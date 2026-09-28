# SPDX-License-Identifier: GPL-3.0-or-later

# Ghostty itself is a Homebrew cask; Home Manager only writes its config and
# wires the shell integration into zsh.
{ lib, pkgs, ... }:

{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.ghostty = {
      enable = true;
      package = null;
      settings.theme = "Nvim Dark";
    };
  };
}
