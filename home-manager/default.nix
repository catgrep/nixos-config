# SPDX-License-Identifier: GPL-3.0-or-later

{ pinned, ... }:

{
  home.username = "bobby";
  home.homeDirectory = "/Users/bobby";
  home.stateVersion = "24.11"; # Update with appropriate version

  # Packages to install
  home.packages = with pinned; [
    ripgrep
    fd
    bat
    nixfmt
    nixd
    nil
    charasay
    gitingest # From unstable channel
    colmena
    colima
    openssh
    openssl
    shellcheck
    shfmt
    nmap
    yq-go
    addlicense
    jujutsu
    just
    nh
    nix-output-monitor
    nvd
  ];

  # direnv loads the repository dev shell on entry; nix-direnv caches the
  # evaluated shell so a new terminal does not re-evaluate the flake.
  programs.direnv = {
    enable = true;
    package = pinned.direnv;
    nix-direnv = {
      enable = true;
      package = pinned.nix-direnv;
    };
  };

  # Enable home-manager
  programs.home-manager.enable = true;
}
