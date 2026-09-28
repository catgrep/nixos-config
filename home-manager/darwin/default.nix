# SPDX-License-Identifier: GPL-3.0-or-later

# Mac-only additions on top of the shared modules. Everything is gated on
# isDarwin so the Linux hosts, which import this directory too, are
# unaffected.
{
  lib,
  pkgs,
  sagent,
  ...
}:

{
  imports = [
    ./ghostty.nix
    ./files.nix
  ];

  config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    # trash moves files to the Finder Trash. It is a nested attribute, which
    # the lock cannot hold, so it comes from the flake's nixpkgs input.
    # ast-bro is built by the sagent subflake and is not in nixpkgs at all.
    home.packages = [
      pkgs.darwin.trash
      sagent.packages.${pkgs.stdenv.hostPlatform.system}.ast-bro
    ];

    home.sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/opt/llvm/bin"
    ];

    # bindgen needs the SDK sysroot to find libc headers; the path changes
    # with Xcode updates, so it is resolved at shell start, not at build time.
    programs.zsh.initContent = ''
      export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --show-sdk-path)"
    '';
  };
}
