# this configuration is from https://github.com/nix-community/nixos-anywhere-examples/blob/main/configuration.nix
{
  modulesPath,
  lib,
  pkgs,
  ...
} @ args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];
  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  users.users.root.openssh.authorizedKeys.keys =
  [
    # change this to your ssh key
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCleOKn5PTvChYNXoKIJ0bleq3EYn9ZyT0sL7qnc3jV4Gc2JoR0gk3yGL0FG/TGn5/cQ59bh8JPSQxmAG2DDzXhyztfK7bINCL+l7ESCciSdIOrhZHS+oeEZzrKyZFBJd0kC+YgoUMvMbyK/xqdMyc5uww50cAqORFX55g7sW0p6KGjVydQEU6Vbi9Dwmt9Ldt0sBBudLO0O+DDwFcort1l5hWurXFWxQWQQhhkm3OIk+5KPuwfbMgJp/YteD8UbsO9s7dhBMasqF8ybzYH7T7hBJNERZWMiyrkzdVY0kyytlFBDCQvCjlS3Vp8SfV+6XkGnHu9sl1bj72iaFYPj4QkggjhEBF6gumMpUBr95hDvECLKtfP2SZ3S5NXjIcJGEltgmd28CItLLYbqA3ENGrkunQyyowBFjMyxvcREFiTmr+FdKwYPdu23UAFQj5WrJPRjiuDuHK9jjW4jMzymaYnYqwsXp6lFAjfe0+mdY9/UqUNyfK7RUY9M+cwJ4YZ4E= bobby@bob-mac.local"
  ] ++ (args.extraPublicKeys or []); # this is used for unit-testing this module and can be removed if not needed

  system.stateVersion = "24.05";
}
