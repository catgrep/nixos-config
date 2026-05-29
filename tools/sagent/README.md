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

Both Codex profiles run inside the same macOS seatbelt profile as Claude via
`claude-sandbox`. Codex is started with
`--dangerously-bypass-approvals-and-sandbox`, so the SBPL profile is the
sandbox boundary instead of Codex's internal per-command sandbox.
`codex-yolo` is kept as a compatibility profile for `codexYoloArgs`.

Important override knobs:

- `extraReadPaths`: common read-only roots added to the shared sandbox.
- `extraWritePaths`: additional common writable roots added to the Claude
  sandbox used by both launchers. Both launchers also get shared default
  writable roots for agent and Nix state: `~/.cache`, `~/.codex`, and
  `~/.nix-defexpr`.
- `unixSocketPaths`: Unix sockets each launcher may connect to, such as
  `/nix/var/nix/daemon-socket/socket` for local Nix daemon evaluation or
  `/var/run/docker.sock` for Docker.
- `networkAccess`: compatibility knob for adding explicit outbound network
  access to the shared profile. The upstream Claude sandbox profile already
  permits network so the native agent CLIs can reach their APIs.
- `extraEnv`: runtime environment variables. Use `~/...` for HOME-relative
  paths; do not put secrets in Nix values.
