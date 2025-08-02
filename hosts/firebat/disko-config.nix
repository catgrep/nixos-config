# SPDX-License-Identifier: GPL-3.0-or-later

# Simple single-disk configuration for Firebat gateway
{ ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Update this with actual disk ID after running lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL
        device = "/dev/disk/by-id/nvme-NVME_SSD_512GB_D5BIRL16301155";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
