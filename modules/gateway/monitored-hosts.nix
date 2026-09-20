# SPDX-License-Identifier: GPL-3.0-or-later

# Hosts scraped by the per-host Prometheus jobs in prometheus.nix. pi4 has
# been physically disconnected since 2026-06-15 and is deliberately left out
# rather than commented out here; re-adding it is one list entry, not an
# archaeology dig through relabel configs.
[
  {
    host = "ser8";
    address = "ser8.local";
  }
  {
    host = "firebat";
    address = "firebat.local";
  }
]
