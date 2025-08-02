# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  home.username = "bobby";
  home.homeDirectory = "/Users/bobby";
  home.stateVersion = "24.11"; # Update with appropriate version

  # Packages to install
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    nixfmt-rfc-style
    nixd
    nil
    charasay
    gitingest # From unstable channel
    colmena
    openssh
    openssl
    shellcheck
    shfmt
    nmap
    yq-go
    addlicense
  ];

  # Enable home-manager
  programs.home-manager.enable = true;
}
