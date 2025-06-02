{ config, lib, pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot.enable = lib.mkDefault true;
      efi.canTouchEfiVariables = lib.mkDefault true;
      timeout = lib.mkDefault 3;
    };

    # Kernel parameters for better performance
    kernelParams = [
      "quiet"
      "loglevel=3"
    ];

    # Enable support for additional filesystems
    # supportedFilesystems = [ "ntfs" "btrfs" ];

    # Temporary file system
    tmp = {
      useTmpfs = lib.mkDefault true;
      tmpfsSize = lib.mkDefault "50%";
    };
  };
}
