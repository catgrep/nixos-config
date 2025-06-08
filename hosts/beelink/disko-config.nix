{ ... }:

{
  disko.devices = {
    disk = {
      # Main system disk (NVMe) - Used for OS, nix store, and builds
      main = {
        type = "disk";
        # Update this with actual disk ID after running 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL'
        device = "/dev/disk/by-id/nvme-CT1000P3PSSD8_24464C21DB62";
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

      # RAID-Z2 disks (4 x 6TB) for NAS backups
      backup-disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500ea5da96a";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "backup";
              };
            };
          };
        };
      };

      backup-disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e9ec4a9a";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "backup";
              };
            };
          };
        };
      };

      backup-disk3 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e9ec48bb";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "backup";
              };
            };
          };
        };
      };

      backup-disk4 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500e9ec29cf";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "backup";
              };
            };
          };
        };
      };

      # Media storage disks (2 x 12TB) - For MergerFS
      media-disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";
        content = {
          type = "gpt";
          partitions = {
            # Using ext4 for MergerFS compatibility
            media = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/disk1";
                mountOptions = [ "defaults" "nofail" ];
              };
            };
          };
        };
      };

      media-disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500b3733a87";
        content = {
          type = "gpt";
          partitions = {
            # Using ext4 for MergerFS compatibility
            media = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/disk2";
                mountOptions = [ "defaults" "nofail" ];
              };
            };
          };
        };
      };
    };

    zpool = {
      # Root pool (system) - Implements "Erase Your Darlings"
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
          # Blank root dataset
          "local" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          # Root filesystem - this gets rolled back
          "local/root" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/";
            postCreateHook = ''
              zfs snapshot rpool/local/root@blank
            '';
          };
          # Nix store - preserved across reboots
          "local/nix" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/nix";
          };
          # Persistent state
          "safe" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          # Home directories - preserved
          "safe/home" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/home";
          };
          # Persistent system state
          "safe/persist" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/persist";
          };
        };
      };

      # Backup pool (RAID-Z2 for redundancy)
      backup = {
        type = "zpool";
        mode = "raidz2";
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
          # Good for backups
          recordsize = "1M";
        };
        datasets = {
          "backups" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/backups";
              # Enable deduplication for backup data
              dedup = "on";
            };
          };
        };
      };
    };
  };
}
