# SPDX-License-Identifier: GPL-3.0-or-later

{ pinned, ... }:

{
  programs.yt-dlp = {
    enable = true;
    package = pinned.yt-dlp;
  };
}
