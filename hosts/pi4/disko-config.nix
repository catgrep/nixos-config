{ ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # For SD card use: /dev/mmcblk0
        # For NVMe use: /dev/nvme0n1
        # Or use by-id for more stability
        device = "/dev/disk/by-id/mmc-SK32G_0xd722200b"; # Update based on your storage
        content = {
          type = "gpt";
          partitions = {
            # Firmware partition (required for Pi bootloader)
            firmware = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Optional swap
            swap = {
              size = "4G";
              content = {
                type = "swap";
                randomEncryption = true;
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
    };
  };
}
