# SPDX-License-Identifier: GPL-3.0-or-later

_:

{
  services.actual = {
    enable = true;
    user = "actual";
    group = "actual";
    openFirewall = true;

    # settings.hostname, settings.port (3000), and settings.dataDir
    # (/var/lib/actual) are left at the module's own defaults -- no port
    # conflicts exist on ser8's port map, and the freeform settings type
    # accepts arbitrary JSON but Actual's server only reads what its own
    # config schema (actualbudget.org/docs/config) defines.
  };
}
