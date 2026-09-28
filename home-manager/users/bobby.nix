# SPDX-License-Identifier: GPL-3.0-or-later

# The one user file: the Mac and every Linux host build bobby's home from
# this module, so platform differences live inside the modules they affect.
{ pkgs, ... }:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  imports = [ ../modules ];

  home.username = "bobby";
  home.homeDirectory = if darwin then "/Users/bobby" else "/home/bobby";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
