# SPDX-License-Identifier: GPL-3.0-or-later

# Shared tmux configuration. The clipboard command and the load average
# source are the only parts that differ between macOS and Linux.
{
  lib,
  pkgs,
  pinned,
  ...
}:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
  copyCommand = if darwin then "pbcopy" else "wl-copy";
  loadAverage =
    if darwin then
      "sysctl -n vm.loadavg | awk '{print $2,$3,$4}'"
    else
      "awk -F ' ' '{print $1,$2,$3}' /proc/loadavg";
  statusRight = lib.concatStringsSep " " [
    "#(uptime | awk -F 'up |,' '{print \\\"up\\\",$2}' | sed 's/  / /g')"
    "#(${loadAverage})"
    "\\\"#H\\\""
    "#(date '+%H:%M %a %m-%d')"
  ];
in
{
  programs.tmux = {
    enable = true;
    package = pinned.tmux;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 10;
    historyLimit = 5000;
    keyMode = "vi";
    mouse = true;
    newSession = true;
    prefix = "C-a";
    terminal = "tmux-256color";

    extraConfig = ''
      # Copy mode and clipboard
      set -s copy-command '${copyCommand}'
      bind -T copy-mode-vi WheelUpPane send-keys -X scroll-up
      bind -T copy-mode-vi WheelDownPane send-keys -X scroll-down

      # Key bindings
      # Last active window
      unbind l
      bind C-a last-window
      bind C-d detach-client
      unbind " "
      bind " " next-window
      bind C-" " next-window
      bind C-c new-window
      bind C-n next-window
      bind C-p previous-window
      bind v run "tmux show-buffer | ${copyCommand}"

      # Highlighting the active window in status bar
      setw -g window-status-current-style bg=red
      set -g status-bg magenta
      set -g status-fg black

      # Add uptime and load average to status bar
      set -g status-interval 5
      set -g status-right-length 100
      set -g status-right "${statusRight}"
    '';
  };
}
