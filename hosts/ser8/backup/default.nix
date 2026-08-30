# SPDX-License-Identifier: GPL-3.0-or-later

{ ... }:

{
  imports = [
    ./datasets.nix
    ./dump.nix
    ./mail.nix
    ./policy.nix
    ./restore.nix
    ./verify.nix
  ];
}
