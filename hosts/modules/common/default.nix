{ config, lib, pkgs, ... }:

{
  imports = [
    ./boot.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./ssh.nix
    ./users.nix
    ./locale.nix
  ];
}
