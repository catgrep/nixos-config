# SPDX-License-Identifier: GPL-3.0-or-later

{ pkgs, ... }:

{
  services.homebox = {
    enable = true;

    # nixpkgs 26.05 currently resolves this to 0.25.0, satisfying HBX-01's
    # "pinned 0.25.x". An explicit (non-mkDefault) pin: a future nixpkgs bump
    # moving Homebox to 0.26 would silently drift this pin unless
    # re-verified.
    package = pkgs.homebox;

    settings = {
      # Every value MUST be a literal Nix string: services.homebox.settings is
      # a freeform attrsOf (nullOr str), so a bare Nix boolean is a hard eval
      # error here (unlike Mealie's toString-based module, which fails
      # silently instead).
      HBOX_WEB_PORT = "7745";
      HBOX_OPTIONS_ALLOW_ANALYTICS = "false";
      HBOX_OPTIONS_GITHUB_RELEASE_CHECK = "false";
      HBOX_OPTIONS_HOSTNAME = "homebox.shad-bangus.ts.net";
      HBOX_DEMO = "false";

      # Closed now that both household accounts exist (verified via
      # GET /api/v1/groups/members returning the same 2-member group from
      # both jordan's and sawnia's tokens). Homebox's own POST
      # /api/v1/users/register handler still permits registration when a
      # valid invite token is supplied -- an intentional exception, not a
      # residual open-registration bug (T-11-02's disposition).
      HBOX_OPTIONS_ALLOW_REGISTRATION = "false";
    };
  };
}
