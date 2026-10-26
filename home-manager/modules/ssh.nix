# SPDX-License-Identifier: GPL-3.0-or-later

# The ssh client configuration, rendered to ~/.ssh/config on every machine.
# Private keys and known_hosts stay outside Nix; the blocks only name them.
#
# The Mac is the only machine with the signing key, so only the Mac forwards
# its gpg-agent. The Match block asks sshd on the host to listen at gpg's
# socket path and relays each connection to the restricted extra socket of the
# Mac's agent. Its exec clause starts the agent when it is not running yet,
# because sshd would otherwise accept the forward and gpg on the host would
# find nobody behind it. It matches the names after HostName substitution, so
# it is ordered after the host blocks. A second session to the same host
# rebinds the socket, and closing that session leaves the first one without an
# agent until it reconnects. The host side is modules/common/gpg.nix and
# home-manager/modules/gpg.
{
  config,
  lib,
  pkgs,
  pinned,
  ...
}:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
  gpgconf = lib.getExe' pinned.gnupg "gpgconf";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # colima writes this file; ssh ignores an Include that does not exist.
    includes = lib.optional darwin "/Users/bobby/.colima/ssh_config";

    settings = lib.mkMerge [
      {
        "gerrithub.io" = {
          User = "bosdhill";
          IdentityFile = "~/.ssh/id_bobmac";
          IdentitiesOnly = true;
        };

        ser8.HostName = "ser8.local";
        firebat.HostName = "firebat.local";
        "ser8 firebat *.shad-bangus.ts.net" = {
          User = "bobby";
          IdentityFile = "~/.ssh/id_rsa";
        };
      }

      (lib.mkIf darwin {
        gpg-agent-forward =
          lib.hm.dag.entryAfter
            [
              "ser8"
              "firebat"
            ]
            {
              header = ''Match host ser8.local,firebat.local,*.shad-bangus.ts.net exec "${gpgconf} --launch gpg-agent"'';
              RemoteForward = "/run/user/1000/gnupg/S.gpg-agent ${config.programs.gpg.homedir}/S.gpg-agent.extra";
            };
      })
    ];
  };
}
