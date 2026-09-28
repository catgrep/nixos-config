# SPDX-License-Identifier: GPL-3.0-or-later

# The GitHub CLI from the lock. git keeps its own credential helper, so the
# module does not register gh as the helper for github.com.
{ pinned, ... }:

{
  programs.gh = {
    enable = true;
    package = pinned.gh;
    gitCredentialHelper.enable = false;
  };
}
