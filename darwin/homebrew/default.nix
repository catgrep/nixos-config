# SPDX-License-Identifier: GPL-3.0-or-later

# Homebrew stays for GUI applications and for the few formulae that are
# tap-only, Darwin-only or stale in nixpkgs. Activation installs what the
# two lists declare and never removes anything: cleanup is a previewed,
# manual step through hm brew cleanup. The lists are data files owned by
# hm add --cask and hm add --brew; taps are declared here by hand, one per
# entry that needs it.
_: {
  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    # Plain `brew bundle` commands read the generated Brewfile.
    global.brewfile = true;
    # Homebrew refuses formulae and casks from a third-party tap it has not
    # been told to trust, so activation would abort on peon-ping and skip
    # stacktower without these flags.
    taps = [
      # peon-ping
      {
        name = "peonping/tap";
        trusted = true;
      }
      # stacktower
      {
        name = "stacktower-io/tap";
        trusted = true;
      }
    ];
    casks = import ./casks.nix;
    brews = import ./brews.nix;
  };
}
