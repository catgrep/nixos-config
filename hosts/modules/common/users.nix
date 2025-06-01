{ config, lib, pkgs, ... }:

{
  users = {
    mutableUsers = false;

    users = {
      root = {
        # Disable root login
        hashedPassword = "!";
      };

      bobby = {
        isNormalUser = true;
        description = "Bobby Hill";
        extraGroups = [ "wheel" "networkmanager" ];
        uid = 1000;

        # SSH keys - replace with your actual public keys
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILdMFWLeCpeDFMKJyLaTtLgmfJ6G8HxrBObvlaBE8eoH bobby@macbook"
          # Add more keys as needed
        ];

        # Initial password hash (change after first login)
        # Generated with: mkpasswd -m SHA-512
        hashedPassword = "$6$rounds=1000000$salt$hash"; # Replace with actual hash
      };
    };
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
