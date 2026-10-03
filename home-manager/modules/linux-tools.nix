# SPDX-License-Identifier: GPL-3.0-or-later

# Tools for administering a Linux host from a shell on the host itself.
# iotop and iftop read the Linux kernel's accounting; tree and whois stay
# with them because the Mac does not want them in its home.
{
  lib,
  pkgs,
  pinned,
  ...
}:
{
  home.packages = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) [
    pinned.tree
    pinned.whois
    pinned.iotop
    pinned.iftop
  ];
}
