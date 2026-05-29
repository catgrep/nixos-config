# sagent

Shared sandboxed agent launcher for native Claude Code and Codex CLIs.

Use this subflake from another project:

```nix
inputs.sagent = {
  url = "github:catgrep/nixos-config?dir=tools/sagent";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then add a project-specific wrapper:

```nix
sagent.lib.mkSagent {
  inherit system pkgs;
  extraWritePaths = [ "~/github/my-project" ];
  extraEnv.MY_CACHE_DIR = "~/.cache/my-project";
}
```

The wrapper exposes:

- `sagent codex [...]`
- `sagent codex-yolo [...]`
- `sagent claude [...]`
- `sagent claude-yolo [...]`

`codex-yolo` keeps Codex in `workspace-write` sandbox mode and changes only
the approval policy to `never`. It does not use Codex's unsandboxed
`--dangerously-bypass-approvals-and-sandbox` mode.

Important override knobs:

- `extraWritePaths`: common writable roots; used by Codex and, by default, the
  Claude sandbox.
- `claudeExtraReadPaths`, `claudeExtraWritePaths`, `codexExtraWritePaths`:
  per-agent path overrides when the common defaults are not right.
- `extraEnv`: runtime environment variables. Use `~/...` for HOME-relative
  paths; do not put secrets in Nix values.
- `allowDockerSocket`: opt-in Docker Desktop socket access for Claude's outer
  macOS sandbox.
- `codexNetworkAccess`: opt-in Codex sandbox network access.
