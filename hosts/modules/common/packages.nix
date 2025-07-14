{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
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

    # Archive tools
    unzip
    zip
    p7zip

    # Development
    nixfmt-rfc-style

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
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };
}
