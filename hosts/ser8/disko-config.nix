# SPDX-License-Identifier: GPL-3.0-or-later

_:

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

      # Media storage disks (2 x 12TB) - ZFS mirror for the media pool
      media-disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/wwn-0x5000c500b56ea81a";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "media";
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
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "media";
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
          # One dataset per service that has a unit of its own, listed
          # alphabetically because the membership rule is mechanical rather than
          # curated. The parent above is still what guarantees coverage -- a
          # recursive snapshot of it captures everything underneath, registered
          # or not -- so a service without its own dataset here loses
          # granularity, never protection.
          #
          # The `mountpoint` attribute beside each block, as opposed to the
          # `mountpoint` inside `options`, is what generates the NixOS
          # fileSystems entry for the path. That generation is the whole
          # mechanism: no fileSystems entry for any of these paths should ever
          # be hand-written, and nothing under /persist should bind-mount them.
          #
          # atime is set locally on each child rather than left to inherit,
          # because an inherited value is only accidentally right and reverses
          # without warning the day a parent property changes. A local value is
          # a recorded intent. It is off at all because on a copy-on-write
          # filesystem every read-triggered timestamp write becomes a new record
          # that the next snapshot pins, so leaving it on means paying snapshot
          # space in order to read files.
          #
          # Only the database child overrides recordsize; see the reason above
          # that block. Every other child keeps the 128K default deliberately.
          # Their contents are mixed -- a small database sitting beside images,
          # metadata trees and configuration files -- and 128K is the compromise
          # mixed content is designed around. Tuning them on the strength of the
          # database's reasoning would be guessing. If a nightly delta ever
          # fingers one of them, dropping that one is a one-line change made
          # with a measurement in hand.
          #
          # These properties are not checked at build time. Nothing at build
          # time can read a property back off a pool that does not exist yet, so
          # the assertion in hosts/ser8/backup/datasets.nix compares fileSystems
          # entries and stops there. The two layers that can see a real pool
          # check the properties instead: the layout test in tests/, against a
          # pool built from these declarations, and the dataset-properties
          # smoketest, against the live host.
          "safe/persist/actual" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/actual";
          };
          "safe/persist/bazarr" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/bazarr";
          };
          "safe/persist/donetick" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/donetick";
          };
          "safe/persist/frigate" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/frigate";
          };
          "safe/persist/hass" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/hass";
          };
          "safe/persist/homebox" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/homebox";
          };
          "safe/persist/jellyfin" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/jellyfin";
          };
          "safe/persist/mealie" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/mealie";
          };
          "safe/persist/mosquitto" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/mosquitto";
          };
          "safe/persist/nzbget" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/nzbget";
          };
          # The record is this filesystem's copy-on-write unit and therefore its
          # snapshot-pinning unit: change one byte inside a record and the whole
          # record is rewritten, and every snapshot referencing the old one
          # holds it. At the 128K default a single row update inside an 8K
          # database page pins 128K of snapshot space. At 16K it pins 16K. 16K
          # rather than 8K because it holds two compressed pages, which is the
          # standard guidance for this database on this filesystem. The effect
          # is on nightly snapshot deltas rather than on throughput, which is
          # what earns it a place in an otherwise untuned layout.
          "safe/persist/postgresql" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
              recordsize = "16K";
            };
            mountpoint = "/var/lib/postgresql";
          };
          "safe/persist/prowlarr" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/prowlarr";
          };
          "safe/persist/radarr" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/radarr";
          };
          "safe/persist/sabnzbd" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/sabnzbd";
          };
          "safe/persist/sonarr" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/sonarr";
          };
          "safe/persist/tailscale" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/var/lib/tailscale";
          };
          # NVMe staging for download and unpack churn. Quota is the hard
          # cap on download-client disk usage: a stuck or oversized import
          # can never again bloat the media mirror the way it once did.
          # Imports copy from here into the media mirror rather than
          # hardlinking, because nothing seeds anymore.
          "safe/downloads" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/downloads";
              quota = "500G";
              compression = "lz4";
              recordsize = "128K";
              atime = "off";
              dedup = "off";
            };
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
        # The replicated copy of the persisted system state lives on this pool
        # as backup/persist-replica, and it is deliberately NOT declared below.
        # Replication has to create it: the first send of a dataset must land on
        # a target that does not yet exist, and the replication tool refuses to
        # run rather than destroy a target it finds already there. Declaring it
        # would create it empty on a fresh install and wedge the first send.
        #
        # It is safe undeclared. The receive drops the mountpoint property from
        # the stream, so the replica inherits mountpoint=none from this pool
        # root and cannot mount anywhere, let alone over the live directories
        # its datasets were copied from. To read a replica snapshot during a
        # restore, give it a mountpoint explicitly and mount it by hand.
        datasets = {
          "backups" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/backups";
              # Enable deduplication for backup data
              dedup = "on";
            };
          };

          # Camera storage for Frigate NVR
          "cameras" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/cameras";
              compression = "lz4";
              recordsize = "1M"; # Optimal for video files
              atime = "off"; # Reduce write overhead
              dedup = "off"; # Video has low dedup ratio, uses lots of RAM
              "com.sun:auto-snapshot" = "false"; # Frigate handles its own retention
            };
          };
          "cameras/recordings" = {
            type = "zfs_fs";
            options = {
              quota = "600G";
            };
          };
          "cameras/clips" = {
            type = "zfs_fs";
            options = {
              quota = "5T";
            };
          };
        };
      };

      # Media pool (two-disk mirror, replacing the old ext4 + MergerFS pair).
      # media/data is a single dataset holding the media libraries (movies,
      # tv, music, books). One dataset, not one per library, because the old
      # reason for that split -- letting hardlinks cross directories -- no
      # longer applies now that torrents are retired; imports copy in from
      # NVMe download staging instead of hardlinking. Compression (lz4) and a
      # 1M recordsize suit the mostly-large media files. No auto-snapshots:
      # the operator manages backup lifecycle by hand, and media content is
      # deliberately outside the backup engine's scope -- the mirror is its
      # own redundancy.
      media = {
        type = "zpool";
        mode = "mirror";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          compression = "lz4";
          recordsize = "1M";
          atime = "off";
          xattr = "sa";
          normalization = "formD";
          dedup = "off";
          mountpoint = "none";
          canmount = "off";
        };
        datasets = {
          "data" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/media";
              "com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
  };
}
