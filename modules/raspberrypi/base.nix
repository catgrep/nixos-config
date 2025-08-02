# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  lib,
  ...
}:

# Pulled from: https://github.com/nvmd/nixos-raspberrypi-demo/blob/3b53c7747c6dae174f25468d5533c51b92dbe222/flake.nix
{
  # Base Network configuration
  networking = {
    useNetworkd = true;
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

  # Base packages
  environment.systemPackages = with pkgs; [
    vim
    git
    tree
    htop
  ];

  # From https://github.com/nvmd/nixos-raspberrypi-demo/blob/3b53c7747c6dae174f25468d5533c51b92dbe222/flake.nix#L154
  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
  '';

  # From https://github.com/nvmd/nixos-raspberrypi-demo/blob/3b53c7747c6dae174f25468d5533c51b92dbe222/flake.nix#L254
  boot.tmp.useTmpfs = true;

  # System tags for identification
  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];
}
