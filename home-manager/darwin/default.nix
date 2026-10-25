# SPDX-License-Identifier: GPL-3.0-or-later

# Mac-only additions on top of the shared modules. Everything is gated on
# isDarwin so the Linux hosts, which import this directory too, are
# unaffected.
{
  config,
  lib,
  pkgs,
  sagent,
  ...
}:
let
  homebrewPaths = [
    "/opt/homebrew/bin"
    "/opt/homebrew/opt/llvm/bin"
  ];
  isHomebrew = lib.hasPrefix "/opt/homebrew";
  sessionPaths = lib.filter (p: !isHomebrew p) config.home.sessionPath;
  shellWords = paths: lib.concatMapStringsSep " " lib.escapeShellArg paths;
  cacert = pkgs.cacert.override { blacklist = import ../../lib/distrusted-cas.nix; };
  caBundle = "${cacert}/etc/ssl/certs/ca-bundle.crt";
in
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

    home.sessionPath = homebrewPaths;

    # Nix-built curl, git, and certifi verify against NIX_SSL_CERT_FILE,
    # which Determinate Nix otherwise points at its own default profile's
    # cacert, and requests outside nixpkgs reads REQUESTS_CA_BUNDLE. The
    # bundle is built here rather than taken from nix-darwin's /etc/ssl so
    # it does not depend on the system layer having been switched.
    home.sessionVariables = {
      NIX_SSL_CERT_FILE = caBundle;
      REQUESTS_CA_BUNDLE = caBundle;
    };

    programs.zsh.initContent = lib.mkMerge [
      # The session entries are prepended from .zshenv, but path_helper then
      # puts the system directories in front of them in every login shell,
      # and a shell that inherits __ETC_PROFILE_NIX_SOURCED never gets the
      # Nix profiles prepended by the /etc/zshrc hook. The order is set here
      # instead, where it runs after both: Nix profiles, the session entries,
      # the inherited directories, and Homebrew last so a formula never
      # shadows a Nix package. Order 515 follows Home Manager's
      # `typeset -U path` line, so the array stays free of duplicates.
      (lib.mkOrder 515 ''
        () {
          local per_user="/etc/profiles/per-user/$USER/bin"
          local -a front=("$HOME/.nix-profile/bin")
          [[ -d "$per_user" ]] && front+=("$per_user")
          front+=(/nix/var/nix/profiles/default/bin ${shellWords sessionPaths})
          local -a brew=(${shellWords homebrewPaths})
          path=($front ''${''${path:|front}:|brew} $brew)
        }
      '')
      # bindgen needs the SDK sysroot to find libc headers; the path changes
      # with Xcode updates, so it is resolved at shell start, not at build time.
      ''
        export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --show-sdk-path)"
      ''
    ];
  };
}
