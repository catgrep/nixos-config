{
  config,
  lib,
  pkgs,
  ...
}:

{
  users = {
    mutableUsers = false;

    users = {
      root = {
        # # Disable root login
        hashedPassword = "!";
      };

      bdhill = {
        isNormalUser = true;
        description = "Bobby Hill";
        extraGroups = [
          "wheel"
          "networkmanager"
          "samba"
        ];
        uid = 1000;

        # SSH keys - replace with your actual public keys
        openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
          # Add more keys as needed
        ];
      };

      guest = {
        isNormalUser = true;
        description = "Guest";
        extraGroups = [
          "samba"
          "guest"
        ];
        uid = 1001;
      };

      # Media is for users uploading content to the media drives over SMB
      media = {
        isNormalUser = true;
        description = "Samba Media User";
        extraGroups = [
          "samba"
          "guest"
        ];
        uid = 1002;
      };
    };
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
