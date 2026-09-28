# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  environment.systemPackages = with config.multiverse.locked; [
    # Essential tools
    curl
    wget
    git
    htop
    btop
    nano
    vim
    tmux
    screen
    mosh
    jq
    yq-go

    # Funsies
    cowsay
    charasay
    lolcat
    fastfetch

    # Network tools
    dig
    nmap
    iperf3
    tcpdump

    # System tools
    lsof
    pciutils
    usbutils
    smartmontools
    ghostty.terminfo

    # Archive tools
    unzip
    zip
    p7zip

    # Development
    nixfmt

    # File management
    ripgrep
    fd
    bat
    eza

    # Analysis Tools
    audit
    blktrace
    bpftrace
    inotify-tools
    perf-tools
  ];

  # Enable some useful programs
  programs = {
    mtr.enable = true;
    mtr.package = config.multiverse.locked.mtr;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    mosh.enable = true;
    mosh.package = config.multiverse.locked.mosh;
    gnupg.package = config.multiverse.locked.gnupg;
  };
}
