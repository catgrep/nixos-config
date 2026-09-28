# SPDX-License-Identifier: GPL-3.0-or-later

# direnv loads the repository dev shell on entry; nix-direnv caches the
# evaluated shell so a new terminal does not re-evaluate the flake.
{ pinned, ... }:

{
  programs.direnv = {
    enable = true;
    package = pinned.direnv;
    nix-direnv = {
      enable = true;
      package = pinned.nix-direnv;
    };
  };
}
