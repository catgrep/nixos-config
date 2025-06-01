{ config, lib, pkgs, ... }:

{
  # Fail2ban for SSH protection
  services.fail2ban = {
    enable = true;
    bantime = "10m";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
    };

    jails = {
      ssh = ''
        enabled = true
        port = 22
        filter = sshd
        logpath = /var/log/auth.log
        maxretry = 5
        bantime = 600
      '';
    };
  };

  # Automatic security updates
  security = {
    # Disable sudo password for wheel group (using SSH keys)
    sudo.wheelNeedsPassword = false;

    # Lock down kernel
    lockKernelModules = false; # Set to true for maximum security

    # Protect kernel logs
    dmesg.restrict = true;
  };

  # Network security
  boot.kernel.sysctl = {
    # Disable IPv6 if not needed
    "net.ipv6.conf.all.disable_ipv6" = 0; # Set to 1 to disable IPv6

    # Network security hardening
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
  };
}
