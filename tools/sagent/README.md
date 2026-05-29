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

- `extraReadPaths`: common read-only roots added to the Claude sandbox.
- `extraWritePaths`: common writable roots added to the Claude sandbox and to
  Codex with `--add-dir`. Codex also gets `<root>/.git` when it exists so it
  can update repository metadata for writable roots.
- `unixSocketPaths`: Unix sockets each launcher may connect to, such as
  `/nix/var/nix/daemon-socket/socket` for local Nix daemon evaluation or
  `/var/run/docker.sock` for Docker.
- `networkAccess`: opt-in unrestricted outbound network access.
- `extraEnv`: runtime environment variables. Use `~/...` for HOME-relative
  paths; do not put secrets in Nix values.
