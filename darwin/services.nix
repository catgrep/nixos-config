# SPDX-License-Identifier: GPL-3.0-or-later

# The window manager as launchd user agents on the nixpkgs binaries,
# currently disabled. The rc files are kept next to this module and read
# into the modules' own options. Every binding and signal in them runs a
# command that exists on this machine when the agents are enabled: the
# borders invocation is services.jankyborders below, and the skhd binding
# that restarts yabai names the org.nixos.yabai agent.
{
  config,
  lib,
  pinned,
  ...
}:
{
  # The agents run with the system path, not the user's Home Manager
  # profile, and the skhd bindings pipe every yabai query through jq.
  environment.systemPackages = lib.optional config.services.skhd.enable pinned.jq;

  services.yabai = {
    enable = false;
    extraConfig = builtins.readFile ./yabai/yabairc;
  };

  services.skhd = {
    enable = false;
    skhdConfig = builtins.readFile ./skhd/skhdrc;
  };

  services.jankyborders = {
    enable = false;
    active_color = "0xffe1e3e4";
    inactive_color = "0xff494d64";
    width = 5.0;
  };
}
