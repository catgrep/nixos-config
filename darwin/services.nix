# SPDX-License-Identifier: GPL-3.0-or-later

# The window manager as launchd user agents on the nixpkgs binaries. The rc
# files are kept verbatim next to this module and read into the modules'
# own options; the only edits are the two that named Homebrew: the borders
# invocation left yabairc for services.jankyborders below, and the skhd
# binding that restarts yabai names the org.nixos.yabai agent.
{ pkgs, ... }:
{
  # The agents run with the system path, not the user's Home Manager
  # profile, and the skhd bindings pipe every yabai query through jq.
  environment.systemPackages = [ pkgs.jq ];

  services.yabai = {
    enable = true;
    extraConfig = builtins.readFile ./yabai/yabairc;
  };

  services.skhd = {
    enable = true;
    skhdConfig = builtins.readFile ./skhd/skhdrc;
  };

  services.jankyborders = {
    enable = true;
    active_color = "0xffe1e3e4";
    inactive_color = "0xff494d64";
    width = 5.0;
  };
}
