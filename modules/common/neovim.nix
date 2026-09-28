# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
  programs.neovim = {
    enable = true;
    package = config.multiverse.locked.neovim-unwrapped;
    defaultEditor = true;
  };
}
