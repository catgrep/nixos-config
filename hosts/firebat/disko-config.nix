# Simple single-disk configuration for Firebat gateway
{ ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Update this with actual disk ID after running lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL
        device = "/dev/sda"; # CHANGE THIS to match your actual disk
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
