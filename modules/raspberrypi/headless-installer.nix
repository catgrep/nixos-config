{ config, pkgs, lib, ... }:

{
  # User configuration for headless installer
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Allow login without password initially
    initialHashedPassword = "";
    # Add your SSH key
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
    ];
  };

  # Allow root login with same SSH key
  users.users.root = {
    initialHashedPassword = "";
    openssh.authorizedKeys.keys = config.users.users.nixos.openssh.authorizedKeys.keys;
  };

  # Passwordless sudo
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # Enable SSH with root login
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Auto-login at console
  services.getty.autologinUser = "nixos";

  # Don't require sudo/root to reboot or poweroff
  security.polkit.enable = true;

  # Trust the nixos user for nix operations
  nix.settings.trusted-users = [ "nixos" ];

  # Network configuration for installer
  networking = {
    useNetworkd = true;
    hostName = "nixos-installer";

    # Enable mDNS
    firewall.allowedUDPPorts = [ 5353 ];
  };

  # mDNS configuration
  systemd.network.networks = {
    "99-ethernet-default-dhcp" = {
      networkConfig.MulticastDNS = "yes";
      matchConfig.Name = "en* eth*";
      networkConfig.DHCP = "yes";
    };
    "99-wireless-client-dhcp" = {
      networkConfig.MulticastDNS = "yes";
      matchConfig.Name = "wlan*";
      networkConfig.DHCP = "yes";
    };
  };

  # Basic packages for installer
  environment.systemPackages = with pkgs; [
    vim
    git
    tree
    htop
  ];

  # System tags for identification
  system.nixos.tags = let
    cfg = config.boot.loader.raspberryPi;
  in [
    "raspberry-pi-${cfg.variant}"
    cfg.bootloader
    config.boot.kernelPackages.kernel.version
  ];

  # Stateless - use latest
  system.stateVersion = config.system.nixos.release;
}
