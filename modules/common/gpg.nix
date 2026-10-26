# SPDX-License-Identifier: GPL-3.0-or-later

# The hosts hold no OpenPGP private key. The signing key lives on the Mac, and
# an interactive SSH session from the Mac forwards the Mac's gpg-agent: the ssh
# client asks sshd to listen at the host's agent socket path,
# /run/user/1000/gnupg/S.gpg-agent, and relays every connection to the Mac
# agent's restricted "extra" socket. gpg on the host then signs through the
# Mac, pinentry prompts on the Mac, and no key material crosses the wire.
# Nothing unattended on a host can sign.
#
# This module is the host side of that arrangement. The user side (the socket
# directory, the public keyring, no agent autostart) is home-manager/modules/gpg,
# and the forward itself is declared in home-manager/modules/ssh.nix.
_:

{
  # A dropped session leaves its socket file behind; sshd must unlink it to
  # bind the next session's forward at the same path.
  services.openssh.settings.StreamLocalBindUnlink = "yes";

  # programs.gnupg.agent stays off: it would start a keyless agent on the
  # socket path the forward needs and, with SSH support, point every shell's
  # SSH_AUTH_SOCK at that agent.
}
