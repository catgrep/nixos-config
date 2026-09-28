# SPDX-License-Identifier: GPL-3.0-or-later

# The vimrc is compiled into the vim wrapper, so it travels with the package.
{ pinned, ... }:

{
  programs.vim = {
    enable = true;
    packageConfigurable = pinned.vim;
    defaultEditor = true;
    extraConfig = ''
      filetype indent plugin on
      syntax on
      autocmd FileType gitcommit setlocal textwidth=72
      set backspace=indent,eol,start
    '';
  };
}
