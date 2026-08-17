# SPDX-License-Identifier: GPL-3.0-or-later

{
  config,
  pkgs,
  lib,
  ...
}:

# Pulled from: https://github.com/nvmd/nixos-raspberrypi-demo/blob/3b53c7747c6dae174f25468d5533c51b92dbe222/flake.nix
{
  options.homelab.raspberryPi.variant = lib.mkOption {
    type = lib.types.enum [
      "4"
      "5"
    ];
    description = ''
      Raspberry Pi board revision, used for boot-menu tagging. Deliberately has no
      default: an unset variant must fail at evaluation rather than silently produce
      an empty tag.
    '';
  };

  config = {
    # Base Network configuration
    networking = {
      useNetworkd = true;
    };

    # DHCP configuration
    systemd.network.networks = {
      "99-ethernet-default-dhcp" = {
        matchConfig.Name = "en* eth*";
        networkConfig.DHCP = "yes";
      };
      "99-wireless-client-dhcp" = {
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

    # Mainline kernel, not the vendor linux-rpi. Both nixos-hardware board modules
    # default boot.kernelPackages to the vendor kernel with lib.mkDefault, and that
    # kernel has no Hydra cache build -- falling through to it turns any build into
    # an hours-long local compile. A plain assignment outranks mkDefault. The rpi5
    # module branches on kernel.pname and selects mainline initrd modules, so this
    # is a supported path rather than a workaround.
    boot.kernelPackages = pkgs.linuxPackages;

    # System tags for identification
    system.nixos.tags = [
      "raspberry-pi-${config.homelab.raspberryPi.variant}"
      "extlinux"
      config.boot.kernelPackages.kernel.version
    ];
  };
}
