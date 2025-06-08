# Raspberry Pi 4 SD card configuration
{ ... }:

{
  disko.devices = {
    disk = {
      sdcard = {
        type = "disk";
        # Typically mmcblk0 for SD cards on Pi
        device = "/dev/mmcblk0"; # UPDATE if using USB drive instead
        content = {
          type = "gpt";
          partitions = {
            # Pi needs a specific firmware partition
            firmware = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [ "nofail" "noauto" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                # SD card optimizations
                mountOptions = [ "noatime" "nodiratime" ];
              };
            };
          };
        };
      };
    };
  };
}
