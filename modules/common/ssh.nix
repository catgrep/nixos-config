# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.openssh = {
    enable = true;
    settings = {
      LogLevel = "DEBUG";
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];

    # Performance tuning
    extraConfig = ''
      ClientAliveInterval 60
      ClientAliveCountMax 3
      MaxAuthTries 3
      MaxSessions 10
    '';
  };

  # Open SSH port
  networking.firewall.allowedTCPPorts = [ 22 ];
}
