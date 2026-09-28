# SPDX-License-Identifier: GPL-3.0-or-later

# Policy: preserve each indexed flake's recorded dependency graph.
# Different upstream nixpkgs revisions remain separate; any substitution must
# be explicit and justified here rather than introduced through shared follows.
# https://github.com/fzakaria/omniflake/blob/main/docs/unification.md
#
# The root flake.lock pins the omniflake snapshot. Updating that input can
# advance several selected flakes together. "pinned" preserves dependencies;
# it does not select a branch or hold one flake across omniflake updates.
#
# Omniflake can supply a computed lock when an upstream lock is missing or
# inconsistent. Recorded inputs are not proof that upstream tested that graph.
# Imported NixOS modules and overlays still receive the consumer's pkgs, so
# preserving flake inputs does not isolate them from the host package set.
#
# Direct-input exceptions in flake.nix:
# - mvs: refresh package history independently of third-party flake updates.
# - home-manager: retain the release branch matching the host baseline.
# - nixos-hardware: retain the explicitly selected Pi boot configuration.
# - nixos-images: the exact nix-community repository is not indexed.
# The sagent subflake retains its exact upstream tool inputs, also absent from
# the index. Recheck coverage before migrating these exceptions, and use
# qualified repository names to avoid selecting a similarly named fork.
{ omniflake }:

let
  upstream = omniflake.pinned;
in
{
  disko = upstream."github:nix-community/disko";
  impermanence = upstream."github:nix-community/impermanence";
  sops-nix = upstream."github:Mic92/sops-nix";
  declarative-jellyfin = upstream."github:Sveske-Juice/declarative-jellyfin";

  # Caddy with plugins support (cleaner than withPlugins)
  caddy-nix = upstream."github:vincentbernat/caddy-nix";
}
