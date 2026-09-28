# SPDX-License-Identifier: GPL-3.0-or-later

# The nix-darwin system layer of bob-mac. It holds only what Nix cannot
# manage from a user profile on macOS: Homebrew casks and brew-only
# formulae, and the launchd agents of the window manager. Home Manager
# stays a separate, standalone layer, so nh home switch and nh darwin
# switch remain independent steps.
{ ... }:
{
  imports = [
    ./homebrew
    ./services.nix
  ];

  # Determinate Nix owns /etc/nix/nix.conf and the nix-daemon launchd job.
  # Leaving Nix unmanaged keeps nix-darwin from rewriting either.
  nix.enable = false;

  # Homebrew and the launchd user agents belong to this account.
  system.primaryUser = "bobby";

  # Option defaults follow this nix-darwin state version, the newest one
  # at the time of the first install.
  system.stateVersion = 7;
}
