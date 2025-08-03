# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Enable the system banner
  programs.system-banner = {
    enable = true;
    shellHook = ''
      echo
      echo "Welcome back, $(whoami)!" | cowsay | lolcat
    '';
    showOnLogin = true;
  };

  # Host identification
  networking = {
    hostName = "pi4";
    hostId = "7406fd88"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '
  };

  # Network configuration
  networking = {
    interfaces.end0.useDHCP = true; # Pi4 uses 'end0' for ethernet
    firewall.enable = true;
  };

  networking.firewall = {
    allowedTCPPorts = [
      53 # DNS
      80 # AdGuard Home web interface
      3000 # AdGuard Home initial setup
      9100 # Node exporter
      9617 # AdGuard Home exporter
    ];
    allowedUDPPorts = [
      53 # DNS
    ];
  };

  # Enable adguardhome DHCP
  services.adguardhome = {
    enable = true;
    settings = {
      dhcp = {
        enabled = true;
        interface_name = "end0";
      };
    };
  };

  # Raspberry Pi packages
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom

    # DNS tools
    dig
    host

    # Network monitoring
    bandwhich
    nethogs
  ];

  # SOPS configuration
  sops = {
    defaultSopsFile = ../../secrets/pi4.yaml;
    defaultSopsFormat = "yaml";

    # Use SSH host key for decryption
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "adguard_user_password_hash" = {
        owner = "adguardhome";
        group = "adguardhome";
        restartUnits = [ "adguardhome.service" ];
      };
    };
  };

  # Override the preStart to inject the password
  systemd.services.adguardhome = {
    preStart = lib.mkAfter ''
      # The config file should already exist at this point
      adguard_yaml=/var/lib/AdGuardHome/AdGuardHome.yaml
      sops_pass_file="${config.sops.secrets.adguard_user_password_hash.path}"
      if [ ! -f "$adguard_yaml" ]; then
          echo "Warning: 'AdGuardHome.yaml' not found"
      elif [ ! -f "$sops_pass_file" ]; then
          echo "Warning: sops password file not found"
      else
        echo "Injecting AdGuard admin password hash..."
        HASH=$(cat "$sops_pass_file")
        ${pkgs.yq-go}/bin/yq eval -i ".users[0].password = \"$HASH\"" "$adguard_yaml"
        echo "Password hash injected successfully"
      fi
    '';
  };

  # System state version
  system.stateVersion = "24.11";
}
