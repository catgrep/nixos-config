# SPDX-License-Identifier: GPL-3.0-or-later

# Every entry in the list resolves through multiverse.lock, so the installed
# version is the pinned one on every machine.
{ pinned, ... }:

{
  home.packages = map (name: pinned.${name}) (import ../packages.nix);
}
