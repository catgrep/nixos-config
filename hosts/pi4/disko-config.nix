{ lib, ... }:
# Adapted from: https://github.com/nvmd/nixos-raspberrypi-demo/blob/df753b734815e4d6e4534f0bc939146ffb1586cc/disko-usb-btrfs.nix
let
  firmwarePartition = lib.recursiveUpdate {
    priority = 1;

    type = "0700"; # Microsoft basic data
    attributes = [
      0 # Required Partition
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    type = "EF00"; # EFI System Partition (ESP)
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "umask=0077"
      ];
    };
  };
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/mmc-FD4Q9_0x687854a5";

    content = {
      type = "gpt";
      partitions = {
        FIRMWARE = firmwarePartition {
          label = "FIRMWARE";
          content.mountpoint = "/boot/firmware";
        };

        ESP = espPartition {
          label = "ESP";
          content.mountpoint = "/boot";
        };

        # Swap partition
        swap = {
          type = "8200"; # Linux swap
          size = "9G"; # RAM + 1GB
          content = {
            type = "swap";
            resumeDevice = true; # "hibernation" swap
            # zram's swap will be used first, and this one only
            # used when the system is under pressure enough that zram and
            # "regular" swap above didn't work
            # https://github.com/systemd/systemd/issues/16708#issuecomment-1632592375
            priority = 2;
          };
        };

        # Root partition
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
