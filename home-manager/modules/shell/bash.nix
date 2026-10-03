# SPDX-License-Identifier: GPL-3.0-or-later

# bash is the fallback shell on the hosts, so it carries the same aliases
# as zsh. The Mac's bash dotfiles stay unmanaged.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.bash = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
    enable = true;
    shellAliases = config.programs.zsh.shellAliases;
  };
}
