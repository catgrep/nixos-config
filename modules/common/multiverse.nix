# SPDX-License-Identifier: GPL-3.0-or-later

# Version-pinned packages, resolved from the repo-root multiverse.lock.
# The lock file is the source of truth for these versions and is edited only
# through `mvs lock` (add/update/status); hosts consume a pin by pointing the
# relevant package option at `config.multiverse.locked.<attr>`.
#
# This imports the core multiverse module rather than mvs.nixosModules.default
# on purpose: the default wrapper installs every locked package into
# environment.systemPackages, which would put ser8's applications on every
# host that shares this module. The core module only resolves derivations.
{ inputs, ... }:

{
  imports = [ "${inputs.mvs}/modules/multiverse.nix" ];

  multiverse = {
    enable = true;
    lock = ../../multiverse.lock;
  };
}
