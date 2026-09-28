# SPDX-License-Identifier: GPL-3.0-or-later

# The one user file: the Mac and every Linux host build bobby's home from
# this module, so platform differences live inside the modules they affect.
# The darwin directory is imported everywhere because the platform is only
# known through `pkgs`, a module argument that cannot decide `imports`; its
# files gate their own contents on isDarwin instead.
{ pkgs, ... }:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  imports = [
    ../modules
    ../darwin
  ];

  home.username = "bobby";
  home.homeDirectory = if darwin then "/Users/bobby" else "/home/bobby";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
