# SPDX-License-Identifier: GPL-3.0-or-later

# The services whose state is snapshotted as a dataset of its own.
#
# Each key does three jobs at once: it is the directory name under /var/lib, the
# child dataset name under rpool/safe/persist, and the name the restore tool
# takes as its argument. Holding all three to one string is what stops them from
# drifting apart, and a build-time assertion in datasets.nix turns any drift
# that does happen into a build failure rather than a silent coverage hole.
#
# The unit is the only thing that genuinely varies, because a state directory
# and the unit that owns it are not always named alike -- Home Assistant keeps
# its state in /var/lib/hass but its unit is home-assistant.service.
#
# Nothing else belongs here. Directory ownership and modes are already settled
# by the service modules' own StateDirectory handling and by the existing
# tmpfiles rules; repeating them here would create a second source of truth,
# and two sources of truth about file modes eventually disagree.
#
# This file is data, not a module. It is read with `import`, so it must never
# appear in an `imports` list.
#
# Membership is decided by a rule, not by judgement: every service on this host
# that has a unit of its own gets a dataset of its own. A hand-picked list would
# have to answer "why is this one in and that one out" at every future review,
# and answering it wrongly once produces a service nobody can restore
# individually. "Has a unit, has a dataset" needs no argument and no upkeep.
#
# What the rule leaves out is everything that is not one service's state: Samba,
# whose tdb files are written by several units and belong to none of them; the
# systemd and network state; the machine identity and host keys; the log tree;
# the dump and manifest directories this slice writes. Those stay in the parent
# dataset, which is a safety net rather than a leftovers bin -- its recursive
# snapshot covers all of them, and covers every path nobody thought to register
# here as well. Being outside this set costs granularity, never protection.
#
# One ordering note for whoever writes a restore or a migration that touches
# both an application and the database behind it: postgresql is in this set and
# so are the applications whose tables live in it. Stop the dependants before
# the database and start them after it, or they will write into a server that
# is being replaced underneath them.

{
  actual = {
    unit = "actual.service";
  };
  bazarr = {
    unit = "bazarr.service";
  };
  donetick = {
    unit = "donetick.service";
  };
  frigate = {
    unit = "frigate.service";
  };
  # Home Assistant is the reason the unit is recorded rather than derived: its
  # state lives in /var/lib/hass and its unit is home-assistant.service.
  hass = {
    unit = "home-assistant.service";
  };
  homebox = {
    unit = "homebox.service";
  };
  jellyfin = {
    unit = "jellyfin.service";
  };
  mealie = {
    unit = "mealie.service";
  };
  mosquitto = {
    unit = "mosquitto.service";
  };
  nzbget = {
    unit = "nzbget.service";
  };
  postgresql = {
    unit = "postgresql.service";
  };
  prowlarr = {
    unit = "prowlarr.service";
  };
  radarr = {
    unit = "radarr.service";
  };
  sabnzbd = {
    unit = "sabnzbd.service";
  };
  sonarr = {
    unit = "sonarr.service";
  };
  # The second name that does not follow from its directory: the state is in
  # /var/lib/tailscale, the daemon is tailscaled.service.
  tailscale = {
    unit = "tailscaled.service";
  };
}
