# SPDX-License-Identifier: GPL-3.0-or-later

# Interactive shell. The zsh dotfiles live under XDG, oh-my-zsh comes from
# the store, and the custom functions and pre-generated completions are
# linked from this directory so every machine gets the same shell.
{
  config,
  lib,
  pinned,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  programs.zsh = {
    enable = true;
    package = pinned.zsh;
    dotDir = "${config.xdg.configHome}/zsh";

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true;
    };

    oh-my-zsh = {
      enable = true;
      package = pinned.oh-my-zsh;
      theme = "fino-time";
      plugins = [ "git" ];
      custom = "${config.xdg.configHome}/oh-my-zsh";
      # The completions directory holds store symlinks, which compfix would
      # otherwise flag as insecure on every start.
      extraConfig = "ZSH_DISABLE_COMPFIX=true";
    };

    initContent = lib.mkMerge [
      # Order 550 runs before oh-my-zsh calls compinit, so the pre-generated
      # completions are found on the first pass.
      (lib.mkOrder 550 ''
        fpath+=("${config.xdg.configHome}/zsh/completions")
      '')
      ''
        # iTerm2 installs its integration script itself; load it only inside
        # iTerm2 so other terminals do not get its prompt hooks.
        if [[ "$TERM_PROGRAM" == iTerm.app && -r "$HOME/.iterm2_shell_integration.zsh" ]]; then
          source "$HOME/.iterm2_shell_integration.zsh"
        fi

        # ghcup is managed outside Home Manager; its env file adds ~/.ghcup/bin
        # and ~/.cabal/bin to PATH.
        [[ -f "$HOME/.ghcup/env" ]] && . "$HOME/.ghcup/env"
      ''
    ];
  };

  home.sessionVariables = {
    PROJ = "${home}/github";
    # Silence the buildx warning about read access to paths outside the context.
    BUILDX_BAKE_ENTITLEMENTS_FS = "0";
  };

  # Tool installers that Nix does not manage put their binaries here.
  home.sessionPath = [
    "${home}/.local/bin"
    "${home}/bin"
    "${home}/.cargo/bin"
    "${home}/.npm-global/bin"
  ];

  xdg.configFile = {
    "oh-my-zsh" = {
      source = ./omz-custom;
      recursive = true;
    };
    "zsh/completions" = {
      source = ./completions;
      recursive = true;
    };
  };
}
