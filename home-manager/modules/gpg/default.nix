# SPDX-License-Identifier: GPL-3.0-or-later

# One OpenPGP identity on every machine, with the private key only on the Mac.
#
# The Mac runs the real gpg-agent, started by gpg on demand. Besides its main
# socket the agent opens the restricted "extra" socket, which answers signing
# and decryption requests but refuses key export and the other commands meant
# for the local user. The ssh module forwards that socket to the hosts, where
# sshd binds it at the path gpg expects, /run/user/1000/gnupg/S.gpg-agent. gpg
# on a host then signs through the Mac, and pinentry prompts on the Mac.
#
# For that to work a host must not run an agent of its own on that path, the
# socket directory must exist before sshd binds into it, and gpg must not start
# a keyless agent when the forward is missing. Every machine imports the public
# key with ultimate trust, because gpg builds the signature packet from its own
# keyring before it asks the agent to sign. The host side of the arrangement is
# modules/common/gpg.nix.
{
  lib,
  pkgs,
  pinned,
  ...
}:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
  # 400 days: a passphrase entered once stays cached for the life of the
  # agent, so signing every commit does not prompt.
  cacheTtl = 34560000;
in
{
  programs.gpg = {
    enable = true;
    package = pinned.gnupg;

    # The public half of the signing key, exported with
    # `gpg --armor --export 05BE930549C3E945BA3D8B6E72B6A6E95F049306`.
    # The keyring stays mutable, so on the Mac this import changes nothing.
    publicKeys = [
      {
        source = ./bobby.asc;
        trust = "ultimate";
      }
    ];

    # Without the forward a host fails with "no gpg-agent running" instead of
    # spawning a local agent that has no keys and then owns the socket path.
    settings.no-autostart = lib.mkIf (!darwin) true;
  };

  # On macOS the launchd unit Home Manager would generate listens under
  # /private/var/run, a directory the user cannot create and that the Nix
  # gnupg never looks in (it keeps its sockets in ~/.gnupg), so the Mac only
  # gets the agent configuration and lets gpg start the agent on demand. The
  # extra socket is on by default.
  home.file.".gnupg/gpg-agent.conf" = lib.mkIf darwin {
    text = ''
      default-cache-ttl ${toString cacheTtl}
      max-cache-ttl ${toString cacheTtl}
      pinentry-program ${lib.getExe' pinned.pinentry_mac "pinentry-mac"}
    '';
  };

  # The agent needs the terminal for curses-style prompts.
  programs.zsh.initContent = lib.mkIf darwin "export GPG_TTY=$TTY";

  # sshd does not create parent directories for a forwarded socket. The user
  # tmpfiles service runs before basic.target, so the directory exists before
  # the session's forward request arrives.
  systemd.user.tmpfiles.rules = lib.mkIf (!darwin) [ "d %t/gnupg 0700 - - -" ];
}
