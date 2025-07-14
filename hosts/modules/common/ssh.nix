{ config, lib, pkgs, ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      LogLevel = "DEBUG";
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };

    # Persistent host keys (conditional on first boot since they may not exist)
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
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
