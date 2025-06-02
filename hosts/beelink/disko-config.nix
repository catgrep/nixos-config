{ ... }:

{
  disko.devices = {
    disk = {
      # Main system disk (NVMe)
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme0n1"; # Update with actual disk ID
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
            zfs = {
              end = "-8G";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
            swap = {
              size = "100%";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };
          };
        };
      };

      # RAID 10 disks (4 x 6TB)
      raid-disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_6TB_DISK_1"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      raid-disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_6TB_DISK_2"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      raid-disk3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_6TB_DISK_3"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      raid-disk4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_6TB_DISK_4"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage";
              };
            };
          };
        };
      };

      # Media storage disks (2 x 12TB) - Individual pools for MergerFS
      media-disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_12TB_DISK_1"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "media1";
              };
            };
          };
        };
      };

      media-disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_YOUR_12TB_DISK_2"; # Update with actual disk ID
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "media2";
              };
            };
          };
        };
      };
    };

    zpool = {
      # Root pool (system)
      rpool = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "nixos" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "nixos/root" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/";
          };
          "nixos/nix" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/nix";
          };
          "nixos/var" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/var";
          };
          "nixos/home" = {
            type = "zfs_fs";
            options.mountpoint = "legacy";
            mountpoint = "/home";
          };
        };
      };

      # Storage pool (RAID 10)
      storage = {
        type = "zpool";
        mode = "mirror";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "downloads" = {
            type = "zfs_fs";
            options.mountpoint = "/mnt/downloads";
          };
          "backups" = {
            type = "zfs_fs";
            options.mountpoint = "/mnt/backups";
          };
        };
      };

      # Media pools (separate 12TB drives for MergerFS)
      media1 = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "media1" = {
            type = "zfs_fs";
            options.mountpoint = "/mnt/media1";
          };
        };
      };

      media2 = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "media2" = {
            type = "zfs_fs";
            options.mountpoint = "/mnt/media2";
          };
        };
      };
    };
  };
}
