# SPDX-License-Identifier: Apache-2.0

{
  lib,
  pkgsFor,
  claude-code-sandbox,
}:

let
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  forAllSystems = f: lib.genAttrs supportedSystems f;

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
      # per-command workspace-write sandbox.
      defaultWritePaths = [
        "~/.cache"
        "~/.codex"
        "~/.nix-defexpr"
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
    pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      inherit sagent;
      default = sagent;
    }
  );
}
