# SPDX-License-Identifier: GPL-3.0-or-later

# GnuPG with the same agent cache policy everywhere. On Linux the agent is a
# systemd user socket. On macOS the launchd unit Home Manager would generate
# listens under /private/var/run, a directory the user cannot create and that
# the Nix gnupg never looks in (it keeps its sockets in ~/.gnupg), so the Mac
# only gets the agent configuration and lets gpg start the agent on demand.
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
  };

  services.gpg-agent = lib.mkIf (!darwin) {
    enable = true;
    defaultCacheTtl = cacheTtl;
    maxCacheTtl = cacheTtl;
    pinentry.package = pkgs.pinentry-curses;
  };

  home.file.".gnupg/gpg-agent.conf" = lib.mkIf darwin {
    text = ''
      default-cache-ttl ${toString cacheTtl}
      max-cache-ttl ${toString cacheTtl}
      pinentry-program ${lib.getExe' pinned.pinentry_mac "pinentry-mac"}
    '';
  };

  # The agent needs the terminal for curses-style prompts; the service module
  # exports this on Linux.
  programs.zsh.initContent = lib.mkIf darwin "export GPG_TTY=$TTY";

  # The hosts sign with a subkey that sops delivers from secrets/shared.yaml
  # as gpg_signing_subkey, readable by bobby only; the primary key never
  # leaves the Mac, so a compromised host can sign but not certify or
  # revoke. The import is idempotent and runs at every session start. The
  # condition lets a host activate before the secret has been entered.
  systemd.user.services.gpg-import-signing-subkey = lib.mkIf (!darwin) {
    Unit = {
      Description = "Import the git signing subkey delivered by sops";
      ConditionPathExists = "/run/secrets/gpg_signing_subkey";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pinned.gnupg "gpg"} --batch --import /run/secrets/gpg_signing_subkey";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
