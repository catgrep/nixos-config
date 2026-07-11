# sagent

Shared sandboxed agent launcher for the native Claude Code and Codex CLIs.

It wraps each agent in a macOS seatbelt sandbox, holds a caffeinate sleep assertion for the agent's lifetime, and runs the agent inside a durable tmux session so a closed terminal or dropped SSH connection never loses progress.

## Using the subflake

```nix
inputs.sagent = {
  url = "github:catgrep/nixos-config?dir=tools/sagent";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Add a project-specific wrapper. Only project configuration is passed; the shared tooling is owned by the subflake.

```nix
sagent.lib.mkSagent {
  inherit system pkgs;
  extraWritePaths = [ "~/github/my-project" ];
  extraEnv.MY_CACHE_DIR = "~/.cache/my-project";
}
```

The subflake also exports fixed `ast-bro` and `treehouse` packages for every supported system, so a consumer dev shell can drop its own pins:

```nix
buildInputs =
  [
    sagent.packages.${system}.ast-bro
    sagent.packages.${system}.treehouse
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    sagent.packages.${system}.sagent
  ];
```

`sagent` and `default` are Darwin-only; `ast-bro` and `treehouse` are exported for all four supported systems (`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`).

## Commands

```
sagent claude [args...]     run Claude Code in the sandbox
sagent codex  [args...]     run Codex in the sandbox
sagent --yolo claude [...]  add the agent's yolo permissions flag
sagent debug  [...]         inspect the sandbox profile
sagent ls                   list sagent tmux sessions
sagent kill <name|--all>    kill one session, or the whole sagent tmux server
sagent --attach <session>   reattach to an existing session
```

`--yolo` selects the agent-specific yolo arguments.
For Claude it also adds `--dangerously-skip-permissions`.
Codex always runs with `--dangerously-bypass-approvals-and-sandbox`, so the seatbelt profile is the sandbox boundary instead of Codex's internal per-command sandbox.

## Durable tmux sessions

On an interactive terminal `sagent claude` / `sagent codex` launches inside an isolated tmux server (`tmux -L sagent`, a bundled config).
Each launch creates a fresh session with two windows:

- Window `agent` runs the sandboxed, caffeinated agent.
- Window `shell` is a plain host shell in the working directory, for `git`, merges, and `treehouse return`.

A launch focuses the `agent` window.
`C-b d` detaches; the server keeps both windows running.
Recover with:

```sh
sagent ls
sagent --attach <session>
```

`--attach` reconnects to the existing panes (the same running agent, in the same directory) and focuses the `shell` window.
It never leases a new worktree and never re-runs the agent.
Do not recover by re-running the original launch command; with `--treehouse` that would lease a second worktree.
A launch with an explicit `--session` name that already exists fails fast and points you at `sagent --attach`.

The durability boundary is the running tmux server.
`tmux kill-server`, an OOM of the server, a reboot, or a crash ends the session (there is no tmux-resurrect).
A `--treehouse` lease survives that; recover it with `treehouse status` / `treehouse prune`.

Every tmux target names the session with an `=` prefix (`=<session>`) and windows by name, never by index.
This stops tmux's prefix matching from hitting a sibling session (so `sagent kill foo` never destroys `foobar`) and keeps window selection correct even if a pre-existing `-L sagent` server uses a non-zero `base-index`.

### Session names

The default name is `<base>-<agent>-<hash4>-<seq>`, derived from the repo working directory.
Override it with `--session NAME` or `SAGENT_SESSION`.
Concurrent auto-named launches that compute the same `seq` are settled at creation time: tmux rejects a duplicate name atomically and the loser retries under a freshly scanned `seq`.

## Isolated worktrees

`sagent --treehouse claude` leases an isolated git worktree with `treehouse get --lease --lease-holder sagent`, launches the agent in it, and points both windows at the worktree.
The lease is never returned automatically; merge and run `treehouse return <path>` yourself.
The worktree is leased before the session is created, so a launch that cannot create its session returns the fresh lease before exiting rather than orphaning it.

`treehouse` is bundled on the agent's PATH and `~/.treehouse` is writable inside the sandbox, so an in-sandbox agent can also lease worktrees.

## Caffeinate

On macOS the agent runs under `caffeinate -i -m -s`, held inside the agent pane for the agent's lifetime, so an idle Mac does not interrupt an unattended run.
Detaching the tmux client does not drop the assertion.
`caffeinate -s` only holds on AC power; on battery with the lid closed the Mac still sleeps.
If `/usr/bin/caffeinate` is missing on macOS the launch fails; set `SAGENT_NO_CAFFEINE=1` to bypass.

## Agent awareness

Claude gets an `--append-system-prompt` note that it runs inside sagent (a restricted sandbox), should prefer `trash` over `rm`, and should tear worktrees down with `git worktree remove` / `treehouse return`.
Codex has no system-prompt flag, so its awareness is the `SAGENT=1` / `SAGENT_SANDBOX=1` environment variables plus `~/AGENTS.md`.
Set `SAGENT_NO_CONTEXT_NOTE=1` to suppress the Claude note.

## Native Claude flags

Claude Code exposes its own `--tmux` and `--worktree`.
When sagent is actually wrapping the run in tmux, `sagent claude --tmux` fails fast, because sagent already owns tmux durability; set `SAGENT_TMUX=0` to use Claude's native tmux instead.
Claude requires `--worktree` for `--tmux`, so this single guard also covers the nested-worktree case.
A non-TTY run, a `SAGENT_TMUX=0` run, or a run already inside tmux leaves Claude's native flags untouched.

## Environment variables

| Variable | Effect |
|---|---|
| `SAGENT_TMUX=0` | Disable the tmux wrapper; run the agent directly (still sandboxed and caffeinated). |
| `SAGENT_NO_CAFFEINE=1` | Do not hold a caffeinate sleep assertion. |
| `SAGENT_SESSION=NAME` | Name the durable session (like `--session`). |
| `SAGENT_LINK_SESSION=1` | Derive the Claude session id from the tmux name so a later session reusing that name resumes the prior conversation. Resume happens only once the old session is gone (killed, or the tmux server restarted); while it is alive the duplicate-session guard sends you to `--attach` instead. Off by default; Codex is a no-op. |
| `SAGENT_NO_CONTEXT_NOTE=1` | Do not tell the agent it runs under sagent. |
| `SAGENT_TMUX_SOCKET=NAME` | tmux server socket label (default `sagent`). |
| `SAGENT_CLAUDE_BIN` / `SAGENT_CODEX_BIN` | Override the resolved agent binary. |

## Failure modes

| Event | Outcome |
|---|---|
| Terminal closed, SSH drops, client killed | Safe. The `-L sagent` server keeps both windows alive; the agent and its in-pane caffeinate keep running. Recover with `sagent ls` then `sagent --attach <session>`. |
| `C-b d` | Clean detach, same as above. |
| Agent (window `agent`) exits | Window `agent` closes; the `shell` window keeps the session alive for review or merge. Close the shell or `sagent kill <session>` to end it. |
| `tmux kill-server`, OOM, reboot, crash | Session lost (durability boundary). A `--treehouse` lease persists; recover with `treehouse status` / `treehouse prune`. |
| `caffeinate` missing on macOS | Hard error, unless `SAGENT_NO_CAFFEINE=1`. |
| `--treehouse` with the treehouse CLI missing | Hard error before any agent launch. |
| Explicit `--session` names an existing session | Hard error before leasing; message points at `sagent --attach`. |
| Two concurrent auto-named launches collide on `seq` | The loser retries under a freshly scanned `seq`; a held `--treehouse` lease is returned if every retry fails. No shared name, no orphaned worktree. |
| `--session` set but tmux inactive | Hard error before leasing; a name has no effect without tmux, so sagent refuses rather than run unnamed. |
| `sagent kill foo` when only `foobar` exists | "no such session: foo"; nothing is destroyed (targets are exact). |
| `claude --tmux` while sagent tmux is active | Hard error with guidance; `SAGENT_TMUX=0` is the escape hatch. |
| Not a TTY (piped / CI `sagent claude -p`) | tmux wrap skipped; the agent runs directly, still caffeinated. |

## debug

`debug` inspects the shared sandbox profile.

```sh
sagent debug > /tmp/sagent.sb
sagent debug --output /tmp/sagent.sb
sagent debug --target-dir "$PWD" --probe "$PWD/flake.nix" "$HOME/.ssh"
sagent debug --exec -- trash "$PWD/probe"
sagent debug --exec -- touch ~/.treehouse/probe
```

`--probe` reports whether each path has metadata, directory-listing, or file-read access inside the generated profile.
`--exec` runs an arbitrary command inside the generated sandbox, for real write/create probing that `--probe` cannot do.
The debug command is not agent-specific because Claude and Codex run inside the same generated profile.

When `sagent` starts inside a Git worktree it detects the worktree's `.git` pointer before entering the sandbox and grants narrow access to the referenced gitdir and common `.git` directory, so `git status` works in Treehouse checkouts without exposing the whole source checkout.

## mkSagent knobs

`mkSagent` owns only project-specific configuration; the `claude-code-sandbox`, `ast-bro`, and `treehouse` pins and the `ast-bro` build workaround live in the subflake.

- `extraReadPaths`: common read-only roots added to the shared sandbox.
- `extraWritePaths`: additional writable roots. Both launchers also get shared default writable roots for agent, Nix, `trash`, and `treehouse` state: `~/.cache`, `~/.codex`, `~/.nix-defexpr`, `~/.Trash`, `~/.treehouse`.
- `unixSocketPaths`: Unix sockets each launcher may connect to, such as `/nix/var/nix/daemon-socket/socket` for the Nix daemon or `/var/run/docker.sock` for Docker.
- `networkAccess`: add explicit outbound network access (the upstream profile already permits the network the agent CLIs need).
- `denyClaudeConfigWrites`: block in-sandbox writes to `~/.claude/settings*.json` and `~/.claude/hooks` (default on).
- `extraEnv`: runtime environment variables. Use `~/...` for HOME-relative paths; do not put secrets in Nix values.
