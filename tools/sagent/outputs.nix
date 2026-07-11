# SPDX-License-Identifier: Apache-2.0

{
  lib,
  pkgsFor,
  claude-code-sandbox,
  ast-bro,
  treehouse,
}:

let
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  forAllSystems = f: lib.genAttrs supportedSystems f;

  # Crane's cleanCargoSource strips .md files, but ast-bro embeds
  # skills/ast-bro/SKILL.md at compile time (include_str!). Overriding `src`
  # with the full flake source restores it. Owned here so no consumer repeats it.
  fixedAstBroFor = system: ast-bro.packages.${system}.default.overrideAttrs { src = ast-bro; };
  treehouseFor = system: treehouse.packages.${system}.default;

  mkSagent =
    {
      system,
      pkgs ? pkgsFor system,
      extraReadPaths ? [ ],
      extraWritePaths ? [ ],
      extraEnv ? { },
      denyClaudeConfigWrites ? true,
      claudeBin ? "~/.local/bin/claude",
      codexBin ? null,
      codexFallbackBins ? [
        "/opt/homebrew/bin/codex"
        "/usr/local/bin/codex"
      ],
      networkAccess ? false,
      unixSocketPaths ? [ ],
      claudeArgs ? [ ],
      claudeYoloArgs ? [ ],
      codexArgs ? [ ],
      codexYoloArgs ? [ ],
    }:
    let
      # Keep both agent profiles on the same writable state roots. Codex runs
      # inside this shared seatbelt profile instead of using its internal
      # per-command workspace-write sandbox. ~/.Trash and ~/.treehouse let
      # `trash` and `treehouse` create files from inside the sandbox.
      defaultWritePaths = [
        "~/.cache"
        "~/.codex"
        "~/.nix-defexpr"
        "~/.Trash"
        "~/.treehouse"
      ];
      sharedWritePaths = defaultWritePaths ++ extraWritePaths;

      claude-sandbox = pkgs.callPackage ./claude-sandbox.nix {
        claude-code-sandbox-src = claude-code-sandbox.packages.${system}.default;
        inherit
          extraReadPaths
          denyClaudeConfigWrites
          networkAccess
          unixSocketPaths
          ;
        extraWritePaths = sharedWritePaths;
      };
    in
    pkgs.callPackage ./. {
      inherit
        claude-sandbox
        extraEnv
        claudeBin
        codexBin
        codexFallbackBins
        claudeArgs
        claudeYoloArgs
        codexArgs
        codexYoloArgs
        ;
      # Internal wiring, not consumer-facing mkSagent knobs.
      tmux = pkgs.tmux;
      astBro = fixedAstBroFor system;
      treehouse = treehouseFor system;
    };
in
{
  lib = {
    inherit mkSagent;
  };

  packages = forAllSystems (
    system:
    let
      pkgs = pkgsFor system;
      sagent = mkSagent { inherit system pkgs; };
    in
    {
      ast-bro = fixedAstBroFor system;
      treehouse = treehouseFor system;
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      inherit sagent;
      default = sagent;
    }
  );
}
