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

  # DNS networking configuration
  networking = {
    # Host identification
    hostName = "pi4";
    hostId = "7406fd88"; # Generate with: head -c 4 /dev/urandom | od -A none -t x4 | tr -d ' '

    firewall = {
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
  };

  # custom internal settings
  networking.internal = {
    interface = "end0";
    adguard.enabled = false; # Don't use AdGuard DNS (it IS the DNS server)

    # Bottom is WRONG. Just assign a static IP to avoid the lease renewal. DUH!
    #
    # DISABLE DHCP client and assign static IP!
    # This may create a circular dependency of the pi4 being a DHCP client of
    # the original router DHCP server.
    #
    # Pi4 (DNS/DHCP Server) → DHCP Client → Router (DHCP Server)
    #               |                                    |
    #               -------- Circular Dependency ---------
    #
    # This caused a failure when the router rebooted and the pi4 tried to
    # renew its lease when the DHCP server was unavailable. I originally
    # tested a router reboot, but I might've still had the fallback DNS listed
    # as the router which is probably why it didn't break.
    # staticIP = {
    #   address = "192.168.68.56";
    #   prefixLength = 22;
    # };
  };

  # Consider the network ready when 'end0' is up, not ALL interfaces
  # Sometimes this will timeout and fail during the boot process
  systemd.services.systemd-networkd-wait-online = {
    serviceConfig = {
      ExecStart = lib.mkForce [
        ""
        "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=end0 --timeout=120"
      ];
    };
  };

  # Enable adguardhome DHCP
  services.adguardhome = {
    enable = true;
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
