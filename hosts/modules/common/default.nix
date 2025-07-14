{ config, lib, pkgs, ... }:

{
  imports = [
    ./banner.nix
    ./boot.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./ssh.nix
    ./users.nix
    ./locale.nix
  ];
}
