# SPDX-License-Identifier: GPL-3.0-or-later

# The machine-wide Rust toolchain is rust-overlay's binary distribution of
# the newest stable release, so cargo, clippy, rustfmt and rust-analyzer
# are the same build on every machine and rustup is not needed. The
# rust-bin set is constructed on this configuration's pkgs directly: an
# overlay would be discarded under useGlobalPkgs on the hosts. A project
# that needs another toolchain declares it in its own rust-toolchain.toml
# and dev shell.
{ pkgs, rust-overlay, ... }:
let
  rustBin = rust-overlay.lib.mkRustBin { } pkgs;
in
{
  home.packages = [
    (rustBin.stable.latest.default.override {
      extensions = [
        "rust-src"
        "clippy"
        "rustfmt"
        "rust-analyzer"
      ];
    })
  ];
}
