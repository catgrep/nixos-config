{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./monitoring.nix
    ./backup.nix
    ./security.nix
  ];

  # Server-specific optimizations
  boot = {
    # Optimize for server workloads
    kernel.sysctl = {
      "vm.swappiness" = 10;
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 65536 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    };

    # Disable unnecessary services for servers
    blacklistedKernelModules = [
      "pcspkr" # Disable PC speaker
    ];
  };

  # Server packages
  environment.systemPackages = with pkgs; [
    # System monitoring
    htop
    iotop
    nethogs

    # Network tools
    nmap
    tcpdump
    mtr

    # Storage tools
    smartmontools
    hdparm

    # Performance tools
    sysstat
    perf-tools
  ];
}
