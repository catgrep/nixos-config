# SPDX-License-Identifier: Apache-2.0

{
  description = "Shared sandboxed agent launcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    claude-code-sandbox = {
      url = "github:neko-kai/claude-code-sandbox/ac2c33ca11714cbe7f518a9209564545eb26eb61";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ast-bro = {
      url = "github:aeroxy/ast-bro/9466139f09cc9fac36b64ca6177bdf76840d9738"; # v3.0.0
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treehouse = {
      url = "github:kunchenguid/treehouse/68fa3d2556542add76bf80255787b8625a5041a6"; # v2.0.0
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      claude-code-sandbox,
      ast-bro,
      treehouse,
      ...
    }:
    import ./outputs.nix {
      inherit (nixpkgs) lib;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      inherit claude-code-sandbox ast-bro treehouse;
    };
}
