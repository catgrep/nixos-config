# SPDX-License-Identifier: GPL-3.0-or-later

# nh performs the switches and hm drives nh, mvs and the list files under
# home-manager/. programs.nh.flake sets NH_FLAKE, which nh and hm both
# read, so every command works from any directory. Periodic cleaning stays
# off until a rollback to an earlier generation has been exercised.
{
  config,
  pkgs,
  pinned,
  mvs,
  ...
}:
{
  programs.nh = {
    enable = true;
    package = pinned.nh;
    flake = "${config.home.homeDirectory}/github/catgrep/nixos-config";
    clean.enable = false;
  };

  home.packages = [
    mvs.packages.${pkgs.stdenv.hostPlatform.system}.mvs
    (pkgs.callPackage ../../tools/hm {
      inherit (pinned) nh git go-tools;
      buildGoModule = pkgs.buildGoModule.override { go = pinned.go_1_27; };
    })
  ];
}
