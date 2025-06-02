{ pkgs, ... }:

{
  home.username = "bobby";
  home.homeDirectory = "/home/bobby";  # Linux path
  home.stateVersion = "24.11";

  # Packages to install
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    nixfmt-rfc-style
    nixd
    nil
    charasay
    gitingest
  ];

  # Enable home-manager
  programs.home-manager.enable = true;
}
