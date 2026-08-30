# SPDX-License-Identifier: GPL-3.0-or-later

# A reduced mirror of hosts/ser8/disko-config.nix, holding only the parts the
# layout test is about: the rpool zpool, its rootFsOptions, the persist dataset,
# and the one child per covered service.
#
# KEEP THE CHILD LIST IN STEP WITH THAT FILE. Nothing enforces the coupling --
# a child added there and not here leaves the test quietly passing on a tree
# that no longer matches the host, which is the failure this test exists to
# prevent, reintroduced one level up.
#
# Reduced rather than imported whole because the real host declares seven
# physical disks across three pools. Installing all of that in a guest costs
# time and tests nothing further about the persist tree; the backup and media
# pools hold no service state.
#
# Three deliberate divergences from the file this mirrors, each forced by the
# guest rather than chosen:
#
#   - One disk instead of seven, sized by the harness rather than by the real
#     hardware, so the zfs partition takes the remainder of the disk instead of
#     leaving 8G for the encrypted swap the host carves out.
#   - cachefile = "none" on the pool. Without it the pool fails to import inside
#     the test guest with an I/O error; disko's own ZFS example carries the same
#     workaround for the same reason.
#   - No @blank snapshot hook on the root dataset. The harness formats and
#     mounts more than once in a run, and the host's unguarded hook would fail
#     the second time. The rollback anchor is not what this test is about.
#
# The local and local/nix datasets are here only because the installed system
# has to boot from somewhere.

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vdb";
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
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        mode = "";
        options = {
          ashift = "12";
          autotrim = "on";
          cachefile = "none";
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
          "local" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          "local/root" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/";
          };
          "local/nix" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
              atime = "off";
            };
            mountpoint = "/nix";
          };
          "safe" = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          "safe/persist" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/persist";
          };

          # One child per covered service, alphabetical, mirroring the host.
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
        };
      };
    };
  };
}
