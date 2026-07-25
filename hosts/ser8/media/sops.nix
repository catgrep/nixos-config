# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  sops = {
    defaultSopsFile = ../../../secrets/ser8.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  };
}
