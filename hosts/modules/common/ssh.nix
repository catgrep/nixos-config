{ config, lib, pkgs, ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };

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
