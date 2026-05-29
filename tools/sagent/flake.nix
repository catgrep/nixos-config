# SPDX-License-Identifier: Apache-2.0

{
  description = "Shared sandboxed agent launcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    claude-code-sandbox = {
      url = "github:neko-kai/claude-code-sandbox/ac2c33ca11714cbe7f518a9209564545eb26eb61";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      claude-code-sandbox,
      ...
    }:
    import ./outputs.nix {
      lib = nixpkgs.lib;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      inherit claude-code-sandbox;
    };
}
