# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  # services.postgresql.enable arrives implicitly from
  # services.mealie.database.createLocally. Without this pin the postgresql
  # module derives its major from system.stateVersion ("24.11" on this host),
  # which selects postgresql_16 with no warning.
  #
  # Plain assignment, not a defaultable one: a mkDefault on a one-way version
  # pin is not a pin. dataDir follows the package and resolves to
  # /var/lib/postgresql/17.
  #
  # Changing this major after data exists requires a manual pg_upgrade against
  # the impermanence-persisted data directory under /persist/var/lib/postgresql;
  # the server refuses to start on a data directory written by another major.
  services.postgresql.package = pkgs.postgresql_17;
}
