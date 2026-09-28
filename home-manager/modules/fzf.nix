# SPDX-License-Identifier: GPL-3.0-or-later

# fzf key bindings and completion are sourced into zsh after oh-my-zsh, so
# the fzf widgets take precedence over the plugin bindings.
{ pinned, ... }:

{
  programs.fzf = {
    enable = true;
    package = pinned.fzf;
    enableZshIntegration = true;
  };
}
