# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./gerrit.nix
    # Add other development services here
    # ./gitea.nix
    # ./jenkins.nix
    # ./devbox.nix
  ];
}
