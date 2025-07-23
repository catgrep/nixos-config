{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot = {
    loader = {
      # Only enable systemd-boot on x86_64 systems by default
      systemd-boot.enable = lib.mkDefault (pkgs.stdenv.hostPlatform.system == "x86_64-linux");
      efi.canTouchEfiVariables = lib.mkDefault (pkgs.stdenv.hostPlatform.system == "x86_64-linux");
      timeout = lib.mkDefault 3;
    };

    # Kernel parameters for better performance
    kernelParams = [
      "quiet"
      "loglevel=3"
    ];

    # Enable support for additional filesystems
    supportedFilesystems = [
      "ntfs"
      "btrfs"
    ];

    # Temporary file system
    tmp = {
      useTmpfs = lib.mkDefault true;
      tmpfsSize = lib.mkDefault "50%";
    };
  };
}
