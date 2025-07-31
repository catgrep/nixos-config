{ ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/mmcblk0";
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


            # Swap partition
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
