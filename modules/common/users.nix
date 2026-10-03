# SPDX-License-Identifier: GPL-3.0-or-later

{ config, ... }:

{
  users = {
    mutableUsers = false;

    # Create media and samba and groups for Samba
    groups.media = {
      gid = 1100;
    };

    # Create jellyfin group
    groups.jellyfin = {
      gid = 1101;
    };

    users = {
      root = {
        # # Disable root login
        hashedPassword = "!";
      };

      # The one interactive account. Its home is built by Home Manager from
      # home-manager/users/bobby.nix, wired in flake.nix.
      bobby = {
        isNormalUser = true;
        description = "Bobby Dhillon";
        extraGroups = [
          "wheel"
          "networkmanager"
          "media"
          "render"
        ];
        uid = 1000;
        shell = config.multiverse.locked.zsh;

        openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
        ];
      };

      # Media is for users uploading content to the media drives over SMB
      media = {
        isNormalUser = true;
        group = "media";
        home = "/var/empty";

        description = "Media user for Samba shares";
        uid = 1100;
      };
    };
  };

  # Enable zsh system-wide but let home-manager handle user configuration
  programs.zsh.enable = true;
  # The NixOS zsh module has no package option and installs pkgs.zsh itself.
  nixpkgs.overlays = [ (_: _: { inherit (config.multiverse.locked) zsh; }) ];

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
