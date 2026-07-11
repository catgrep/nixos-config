# SPDX-License-Identifier: Apache-2.0

{
  lib,
  writeShellApplication,
  writeText,
  tmux,
  claude-sandbox,
  astBro,
  treehouse,
  extraEnv ? { },
  claudeBin ? "~/.local/bin/claude",
  codexBin ? null,
  codexFallbackBins ? [
    "/opt/homebrew/bin/codex"
    "/usr/local/bin/codex"
  ],
  claudeArgs ? [ ],
  claudeYoloArgs ? [ ],
  codexArgs ? [ ],
  codexYoloArgs ? [ ],
}:

let
  mkShellWord =
    value:
    let
      stringValue = toString value;
    in
    if stringValue == "~" then
      ''"$HOME"''
    else if lib.hasPrefix "~/" stringValue then
      ''"$HOME"/${lib.escapeShellArg (lib.removePrefix "~/" stringValue)}''
    else
      lib.escapeShellArg stringValue;

  mkShellArray = name: values: ''
    ${name}=(${lib.concatMapStringsSep " " mkShellWord values})
  '';

  mkEnvExport =
    name: value:
    let
      stringValue = toString value;
    in
    if builtins.match "[A-Za-z_][A-Za-z0-9_]*" name == null then
      throw "sagent extraEnv key is not a valid shell variable name: ${name}"
    else if lib.hasPrefix "~/" stringValue then
      ''export ${name}="$HOME"/${lib.escapeShellArg (lib.removePrefix "~/" stringValue)}''
    else
      "export ${name}=${lib.escapeShellArg stringValue}";

  envExports = lib.concatStringsSep "\n" (lib.mapAttrsToList mkEnvExport extraEnv);

  # Config applied only when sagent creates the isolated `-L sagent` tmux
  # server; an already-running server keeps its own config, so all targeting
  # is by session/window name rather than index.
  tmuxConf = writeText "sagent-tmux.conf" ''
    set -g mouse on
    set -g history-limit 50000
    set -g base-index 0
    set -g escape-time 10
    set -g focus-events on
    set -g status-interval 5
    set -g status-left "#[bold] sagent:#S "
    set -g status-right "detach: C-b d "
  '';
in
writeShellApplication {
  name = "sagent";
  runtimeInputs = [
    claude-sandbox
    tmux
    astBro
    treehouse
  ];

  text = ''
    : "''${HOME:?HOME must be set}"

    SAGENT_TMUX_SOCKET="''${SAGENT_TMUX_SOCKET:-sagent}"

    SAGENT_DEFAULT_CLAUDE_BIN=${mkShellWord claudeBin}
    SAGENT_DEFAULT_CODEX_BIN=${mkShellWord (if codexBin == null then "" else codexBin)}
    ${mkShellArray "SAGENT_CODEX_FALLBACK_BINS" codexFallbackBins}
    ${mkShellArray "SAGENT_CLAUDE_ARGS" claudeArgs}
    ${mkShellArray "SAGENT_CLAUDE_YOLO_ARGS" claudeYoloArgs}
    ${mkShellArray "SAGENT_CODEX_ARGS" codexArgs}
    ${mkShellArray "SAGENT_CODEX_YOLO_ARGS" codexYoloArgs}

    ${envExports}

    usage() {
      cat >&2 <<'EOF'
    usage: sagent [sagent flags...] <command> [args...]
           sagent --attach <session>
           sagent ls
           sagent kill <session|--all>

    commands:
      claude [args...]     run Claude Code in the sandbox (durable tmux session on a TTY)
      codex [args...]      run Codex in the sandbox
      debug [...]          inspect the sandbox profile (see: sagent debug --help)
      ls                   list sagent tmux sessions
      kill <name|--all>    kill one session, or the whole sagent tmux server
      help                 show this help

    sagent flags:
      --yolo               run the selected agent with its yolo permissions flag
      --treehouse          lease an isolated git worktree and launch the agent in it
      --session NAME       name the durable tmux session (default: auto-generated)
      --attach NAME        reattach to an existing session (focuses its shell window)
      -h, --help           show this help

    environment:
      SAGENT_TMUX=0             disable the tmux wrapper (run the agent directly)
      SAGENT_NO_CAFFEINE=1      do not hold a caffeinate sleep assertion (macOS)
      SAGENT_SESSION=NAME       like --session
      SAGENT_LINK_SESSION=1     link the agent session id to the tmux name (resume on reuse)
      SAGENT_NO_CONTEXT_NOTE=1  do not tell the agent it runs under sagent
      SAGENT_TMUX_SOCKET=NAME   tmux server socket label (default: sagent)
    EOF
    }

    debug_usage() {
      cat >&2 <<'EOF'
    usage: sagent debug [debug flags...] [--probe path...]
           sagent debug --exec [debug flags...] -- CMD [ARGS...]

    debug flags:
      --target-dir <dir>   directory used for TARGET_DIR rules (default: current directory)
      --output <file>      write the generated sandbox profile to a file
      --base               dump the built-in base profile instead of the generated profile
      --no-workaround      omit generated parent-directory read rules
      --probe              probe path readability inside the generated sandbox
      --exec               run CMD [ARGS...] inside the generated sandbox (after --)
      -h, --help           show this help
    EOF
    }

    require_arg() {
      local flag="$1"
      local value="''${2:-}"

      if [ -z "$value" ]; then
        echo "error: $flag requires an argument" >&2
        exit 2
      fi
    }

    sanitize() {
      printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '-'
    }

    # Reject Claude's native --tmux only when sagent will actually own tmux.
    # A non-TTY / SAGENT_TMUX=0 / missing-tmux run leaves it untouched. Claude
    # requires --worktree for --tmux, so this single guard covers tmux-in-tmux.
    guard_claude_native_flags() {
      local tmux_enabled="$1" kind="$2"
      shift 2

      [ "$tmux_enabled" = "1" ] || return 0
      [ "$kind" = "claude" ] || return 0

      local arg
      for arg in "$@"; do
        case "$arg" in
          --tmux | --tmux=*)
            echo "error: sagent already manages tmux durability; drop 'claude --tmux' or set SAGENT_TMUX=0 to use Claude's native tmux" >&2
            exit 2
            ;;
        esac
      done
    }

    resolve_treehouse() {
      command -v treehouse >/dev/null 2>&1 ||
        {
          echo "error: --treehouse requires the treehouse CLI" >&2
          exit 1
        }

      local worktree
      worktree="$(treehouse get --lease --lease-holder sagent)" ||
        {
          echo "error: 'treehouse get --lease' failed" >&2
          exit 1
        }

      if [ -z "$worktree" ] || [ ! -d "$worktree" ]; then
        echo "error: treehouse returned an invalid path: '$worktree'" >&2
        exit 1
      fi

      printf '%s' "$worktree"
    }

    # Best-effort lowest free integer for an auto-name prefix. The launch step
    # re-scans on collision, so a stale value here is settled at creation time.
    next_seq() {
      local prefix="$1"
      local n=1
      local existing
      existing="$(tmux -L "$SAGENT_TMUX_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null || true)"
      # -F/-- so a prefix that sanitizes to a leading dash (e.g. ~/.dotfiles ->
      # -dotfiles) is matched as a literal string, not parsed as grep options.
      while printf '%s\n' "$existing" | grep -qxF -- "$prefix-$n"; do
        n=$((n + 1))
      done
      printf '%s' "$n"
    }

    # Auto-name prefix derived from the repo cwd (never the worktree path).
    compute_auto_prefix() {
      local kind="$1"
      local base hash4
      base="$(sanitize "$(basename "$PWD")")"
      hash4="$(printf '%04d' "$(( $(printf '%s' "$PWD" | cksum | cut -d' ' -f1) % 10000 ))")"
      printf '%s-%s-%s' "$base" "$kind" "$hash4"
    }

    # Explicit --session / SAGENT_SESSION only. Fails fast if the name is taken
    # so a re-run of a launch command never orphans a fresh worktree.
    resolve_session_name() {
      local name
      if [ -n "$session_flag" ]; then
        name="$(sanitize "$session_flag")"
      else
        name="$(sanitize "$SAGENT_SESSION")"
      fi

      if tmux -L "$SAGENT_TMUX_SOCKET" has-session -t "=$name" 2>/dev/null; then
        echo "error: session '$name' already exists; reattach with: sagent --attach $name" >&2
        exit 1
      fi

      printf '%s' "$name"
    }

    launch_tmux_session() {
      local session="$1" auto_prefix="$2" leased_dir="$3" kind="$4"
      shift 4

      local reexec=()
      [ "$yolo" = 1 ] && reexec+=(--yolo)
      reexec+=("$kind" "$@")

      # new-session -s NAME takes the name literally and rejects a duplicate
      # atomically. Auto names retry under a freshly scanned seq to close the
      # compute-then-create race; an explicit name surfaces the collision.
      local attempt=0 created=0
      while [ "$attempt" -lt 5 ]; do
        attempt=$((attempt + 1))
        if tmux -L "$SAGENT_TMUX_SOCKET" -f "${tmuxConf}" \
          new-session -d -s "$session" -c "$PWD" -n agent \
          env SAGENT_IN_TMUX=1 SAGENT_TMUX_SESSION="$session" "$0" "''${reexec[@]}" 2>/dev/null; then
          created=1
          break
        fi
        [ -n "$auto_prefix" ] || break
        session="$auto_prefix-$(next_seq "$auto_prefix")"
      done

      if [ "$created" = "0" ]; then
        # Never orphan a fresh worktree if session creation could not settle.
        local returned_note=""
        if [ -n "$leased_dir" ]; then
          treehouse return --force "$leased_dir" >/dev/null 2>&1 || true
          returned_note=" (returned worktree lease: $leased_dir)"
        fi
        echo "error: could not create tmux session '$session'$returned_note" >&2
        exit 1
      fi

      # Exact session (=session) and windows by name, so a pre-existing server's
      # base-index cannot break selection and no sibling matches by prefix.
      tmux -L "$SAGENT_TMUX_SOCKET" new-window -t "=$session:" -n shell -c "$PWD"
      tmux -L "$SAGENT_TMUX_SOCKET" select-window -t "=$session:agent"
      exec tmux -L "$SAGENT_TMUX_SOCKET" attach -t "=$session"
    }

    build_context_note() {
      local note
      note="You are running inside sagent, a macOS seatbelt sandbox with restricted filesystem writes."
      note="$note Prefer 'trash' over 'rm'; remove git worktrees with 'git worktree remove' or 'treehouse return', never 'rm -rf'."
      if [ -n "''${SAGENT_TMUX_SESSION:-}" ]; then
        note="$note This is a persistent tmux session '$SAGENT_TMUX_SESSION' (tmux -L $SAGENT_TMUX_SOCKET) that survives terminal disconnects."
      fi
      printf '%s' "$note"
    }

    # Deterministic UUID-shaped id (not a strict RFC UUIDv5). Version nibble 5,
    # variant nibble 8; passes format-level validation and is stable per name.
    name_to_uuid() {
      local h
      h="$(printf '%s' "sagent:$1" | shasum -a 1 | cut -c1-40)"
      printf '%s-%s-5%s-%s-%s' "''${h:0:8}" "''${h:8:4}" "''${h:13:3}" "8''${h:17:3}" "''${h:20:12}"
    }

    run_ls() {
      tmux -L "$SAGENT_TMUX_SOCKET" list-sessions \
        -F '#{session_name}  [#{?session_attached,attached,detached}]  #{session_path}' 2>/dev/null ||
        echo "no sagent sessions"
    }

    run_attach() {
      local name="$1"
      { [ -t 0 ] && [ -t 1 ]; } ||
        {
          echo "error: --attach requires a terminal" >&2
          exit 1
        }
      tmux -L "$SAGENT_TMUX_SOCKET" has-session -t "=$name" 2>/dev/null ||
        {
          echo "error: no such session: $name" >&2
          run_ls >&2
          exit 1
        }
      tmux -L "$SAGENT_TMUX_SOCKET" select-window -t "=$name:shell" 2>/dev/null || true
      exec tmux -L "$SAGENT_TMUX_SOCKET" attach -t "=$name"
    }

    run_kill() {
      case "$#" in
        1) : ;;
        *)
          echo "error: kill takes exactly one argument (a session name or --all)" >&2
          exit 2
          ;;
      esac

      if [ "$1" = "--all" ]; then
        tmux -L "$SAGENT_TMUX_SOCKET" kill-server 2>/dev/null || echo "no sagent server running"
        return 0
      fi

      # Exact match so 'kill foo' can never destroy a sibling like 'foobar'.
      tmux -L "$SAGENT_TMUX_SOCKET" has-session -t "=$1" 2>/dev/null ||
        {
          echo "error: no such session: $1" >&2
          run_ls >&2
          exit 1
        }
      tmux -L "$SAGENT_TMUX_SOCKET" kill-session -t "=$1"
    }

    expand_path() {
      local path="$1"
      case "$path" in
        \~)
          printf '%s\n' "$HOME"
          ;;
        \~/*)
          printf '%s/%s\n' "$HOME" "''${path:2}"
          ;;
        *)
          printf '%s\n' "$path"
          ;;
      esac
    }

    resolve_executable() {
      local candidate="$1"
      local expanded

      [ -n "$candidate" ] || return 1
      expanded="$(expand_path "$candidate")"

      if [[ "$expanded" == */* ]]; then
        [ -x "$expanded" ] || return 1
        printf '%s\n' "$expanded"
      else
        command -v "$expanded"
      fi
    }

    find_executable() {
      local command_name="$1"
      local env_name="$2"
      local configured="$3"
      shift 3

      local candidate
      local resolved

      candidate="''${!env_name:-}"
      if resolved="$(resolve_executable "$candidate")"; then
        printf '%s\n' "$resolved"
        return 0
      fi

      if resolved="$(resolve_executable "$configured")"; then
        printf '%s\n' "$resolved"
        return 0
      fi

      for candidate in "$@"; do
        if resolved="$(resolve_executable "$candidate")"; then
          printf '%s\n' "$resolved"
          return 0
        fi
      done

      if resolved="$(command -v "$command_name")"; then
        printf '%s\n' "$resolved"
        return 0
      fi

      echo "error: $command_name not found. Install the native $command_name CLI or set SAGENT_''${command_name^^}_BIN." >&2
      return 1
    }

    realpath_or_echo() {
      local path="$1"

      realpath -m "$path" 2>/dev/null || realpath "$path" 2>/dev/null || printf '%s\n' "$path"
    }

    resolve_path() {
      local base="$1"
      local path="$2"

      case "$path" in
        /*)
          realpath_or_echo "$path"
          ;;
        *)
          realpath_or_echo "$base/$path"
          ;;
      esac
    }

    escape_for_sandbox() {
      local path="$1"

      path="''${path//\\/\\\\}"
      path="''${path//\"/\\\"}"
      printf '%s' "$path"
    }

    find_git_node() {
      local dir

      dir="$(realpath_or_echo "$1")"
      while [ "$dir" != "/" ]; do
        if [ -e "$dir/.git" ]; then
          printf '%s\n' "$dir/.git"
          return 0
        fi
        dir="$(dirname "$dir")"
      done

      return 1
    }

    emit_ancestor_read_literals() {
      local path="$1"
      local current_path=""
      local component
      local escaped_path
      local components=()

      path="$(realpath_or_echo "$path")"
      IFS='/' read -ra components <<<"$path"

      for component in "''${components[@]}"; do
        if [ -z "$component" ]; then
          if [ -z "$current_path" ]; then
            current_path="/"
          fi
          continue
        fi

        if [ "$current_path" = "/" ]; then
          current_path="/$component"
        else
          current_path="$current_path/$component"
        fi

        escaped_path="$(escape_for_sandbox "$current_path")"
        printf '  (literal "%s")\n' "$escaped_path"
      done
    }

    emit_subpath() {
      local path="$1"
      local escaped_path

      path="$(realpath_or_echo "$path")"
      escaped_path="$(escape_for_sandbox "$path")"
      printf '  (subpath "%s")\n' "$escaped_path"
    }

    generate_git_profile_fragment() {
      local target_dir="$1"
      local git_node
      local gitdir
      local gitdir_line
      local gitdir_base
      local commondir
      local commondir_line

      if ! git_node="$(find_git_node "$target_dir")"; then
        return 0
      fi

      if [ -f "$git_node" ]; then
        gitdir_line="$(sed -n 's/^gitdir: //p' "$git_node" | head -n 1)"
        [ -n "$gitdir_line" ] || return 0
        gitdir_base="$(dirname "$git_node")"
        gitdir="$(resolve_path "$gitdir_base" "$gitdir_line")"
      elif [ -d "$git_node" ]; then
        gitdir="$(realpath_or_echo "$git_node")"
      else
        return 0
      fi

      commondir="$gitdir"
      if [ -f "$gitdir/commondir" ]; then
        IFS= read -r commondir_line <"$gitdir/commondir" || true
        if [ -n "$commondir_line" ]; then
          commondir="$(resolve_path "$gitdir" "$commondir_line")"
        fi
      fi

      cat <<EOF

    ;; sagent: Git metadata access for target $(escape_for_sandbox "$target_dir")
    ;; gitdir: $(escape_for_sandbox "$gitdir")
    ;; commondir: $(escape_for_sandbox "$commondir")
    (allow file-read*
    $(emit_ancestor_read_literals "$git_node")
    $(emit_ancestor_read_literals "$gitdir")
    $(emit_ancestor_read_literals "$commondir")
    )
    (allow file-read* file-write* file-write-create file-read-metadata file-ioctl
    $(emit_subpath "$gitdir")
    $(emit_subpath "$commondir")
    )
    EOF
    }

    write_git_profile() {
      local target_dir="$1"
      local fragment
      local profile

      fragment="$(generate_git_profile_fragment "$target_dir")"
      [ -n "$fragment" ] || return 1

      # This runs as the command of `if profile="$(write_git_profile ...)"`, so
      # errexit is suppressed for the whole body; guard the fallible steps
      # explicitly. On failure, return 1 to fall back to the default profile
      # rather than emitting a headerless (corrupt) one.
      profile="$(mktemp "''${TMPDIR:-/tmp}/sagent-profile.XXXXXXXXXX")" || return 1
      if ! claude-sandbox --write-base-profile "$profile"; then
        rm -f "$profile"
        return 1
      fi
      printf '%s\n' "$fragment" >>"$profile"
      printf '%s\n' "$profile"
    }

    run_with_sandbox() {
      local target_dir="$1"
      local no_workaround="$2"
      shift 2

      local profile
      local sandbox_args=(--target-dir "$target_dir")
      local status

      if [ "$no_workaround" = "1" ]; then
        sandbox_args+=(--no-workaround)
      fi

      # Hold a sleep assertion for the agent's lifetime so an idle Mac does not
      # interrupt an unattended run. Set inside the agent pane by run_claude /
      # run_codex only; debug runs leave SAGENT_WANT_CAFFEINE unset.
      local caffeine=()
      if [ "''${SAGENT_WANT_CAFFEINE:-0}" = "1" ] && [ "''${SAGENT_NO_CAFFEINE:-0}" != "1" ]; then
        if [ "$(uname -s)" = "Darwin" ]; then
          if [ -x /usr/bin/caffeinate ]; then
            caffeine=(/usr/bin/caffeinate -i -m -s)
          else
            echo "error: /usr/bin/caffeinate not found (required on macOS; set SAGENT_NO_CAFFEINE=1 to bypass)" >&2
            exit 1
          fi
        fi
      fi

      if profile="$(write_git_profile "$target_dir")"; then
        status=0
        "''${caffeine[@]}" claude-sandbox "''${sandbox_args[@]}" --use-profile "$profile" -- "$@" || status="$?"
        rm -f "$profile"
        exit "$status"
      fi

      exec "''${caffeine[@]}" claude-sandbox "''${sandbox_args[@]}" -- "$@"
    }

    write_debug_profile() {
      local target_dir="$1"
      local no_workaround="$2"
      local output_path="$3"
      local profile
      local sandbox_args=(--target-dir "$target_dir")
      local status

      if [ "$no_workaround" = "1" ]; then
        sandbox_args+=(--no-workaround)
      fi

      if profile="$(write_git_profile "$target_dir")"; then
        status=0
        claude-sandbox "''${sandbox_args[@]}" --use-profile "$profile" --write-profile "$output_path" || status="$?"
        rm -f "$profile"
        exit "$status"
      fi

      exec claude-sandbox "''${sandbox_args[@]}" --write-profile "$output_path"
    }

    run_debug_probe() {
      local target_dir="$1"
      local no_workaround="$2"
      shift 2

      # shellcheck disable=SC2016
      run_with_sandbox "$target_dir" "$no_workaround" /bin/sh -c '
    for path do
      printf "\n== %s ==\n" "$path"

      if [ -e "$path" ]; then
        echo "exists: yes"
      else
        echo "exists: no or denied"
      fi

      if /usr/bin/stat "$path" >/dev/null 2>&1; then
        echo "metadata: ok"
      else
        echo "metadata: denied"
      fi

      if [ -d "$path" ]; then
        if /bin/ls "$path" >/dev/null 2>&1; then
          echo "list: ok"
        else
          echo "list: denied"
        fi
      else
        echo "list: skipped"
      fi

      if [ -f "$path" ]; then
        if /bin/cat "$path" >/dev/null 2>&1; then
          echo "read: ok"
        else
          echo "read: denied"
        fi
      else
        echo "read: skipped"
      fi
    done
    ' sagent-debug "$@"
    }

    run_debug() {
      local debug_base=0
      local debug_no_workaround=0
      local debug_output=""
      local debug_probe=0
      local debug_exec=0
      local debug_target_dir="$PWD"
      local debug_paths=()

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --target-dir)
            require_arg "$1" "''${2:-}"
            debug_target_dir="$2"
            shift 2
            ;;
          --output)
            require_arg "$1" "''${2:-}"
            debug_output="$2"
            shift 2
            ;;
          --base)
            debug_base=1
            shift
            ;;
          --no-workaround)
            debug_no_workaround=1
            shift
            ;;
          --probe)
            debug_probe=1
            shift
            ;;
          --exec)
            debug_exec=1
            shift
            ;;
          -h|--help)
            debug_usage
            exit 0
            ;;
          --)
            shift
            while [ "$#" -gt 0 ]; do
              debug_paths+=("$1")
              shift
            done
            ;;
          -*)
            echo "error: unknown debug flag: $1" >&2
            debug_usage
            exit 2
            ;;
          *)
            debug_paths+=("$1")
            shift
            ;;
        esac
      done

      # Run an arbitrary command inside the generated sandbox, for real
      # write/create probing that --probe (read/list/metadata only) cannot do.
      if [ "$debug_exec" = "1" ]; then
        if [ "$debug_probe" = "1" ] || [ "$debug_base" = "1" ] || [ -n "$debug_output" ]; then
          echo "error: --exec cannot be combined with --probe, --base, or --output" >&2
          exit 2
        fi
        if [ "''${#debug_paths[@]}" -eq 0 ]; then
          echo "error: --exec requires a command (sagent debug --exec [flags] -- CMD [ARGS...])" >&2
          debug_usage
          exit 2
        fi

        run_with_sandbox "$debug_target_dir" "$debug_no_workaround" "''${debug_paths[@]}"
        return
      fi

      if [ "$debug_probe" = "0" ] && [ "''${#debug_paths[@]}" -gt 0 ]; then
        echo "error: debug path arguments require --probe or --exec" >&2
        debug_usage
        exit 2
      fi

      if [ "$debug_probe" = "1" ]; then
        if [ "''${#debug_paths[@]}" -eq 0 ]; then
          echo "error: --probe requires at least one path" >&2
          debug_usage
          exit 2
        fi
        if [ "$debug_base" = "1" ] || [ -n "$debug_output" ]; then
          echo "error: --probe cannot be combined with --base or --output" >&2
          exit 2
        fi

        run_debug_probe "$debug_target_dir" "$debug_no_workaround" "''${debug_paths[@]}"
      fi

      local output_path="/dev/stdout"
      if [ -n "$debug_output" ]; then
        output_path="$debug_output"
      fi

      if [ "$debug_base" = "1" ]; then
        exec claude-sandbox --write-base-profile "$output_path"
      fi

      write_debug_profile "$debug_target_dir" "$debug_no_workaround" "$output_path"
    }

    run_claude() {
      local yolo="$1"
      shift

      local claude_bin
      claude_bin="$(find_executable claude SAGENT_CLAUDE_BIN "$SAGENT_DEFAULT_CLAUDE_BIN")"

      if [ -n "''${ANTHROPIC_API_KEY:-}" ] || [ -n "''${ANTHROPIC_AUTH_TOKEN:-}" ]; then
        echo "error: ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN are set in env; these pre-empt" >&2
        echo "       CLAUDE_CODE_OAUTH_TOKEN and cause auth conflicts. Unset them." >&2
        exit 1
      fi

      local token
      if ! token=$(security find-generic-password \
                    -a "$USER" \
                    -s "claude-code-sandbox-token" \
                    -w 2>/dev/null); then
        echo "error: no token in Keychain under service 'claude-code-sandbox-token'." >&2
        echo "       Run 'claude setup-token' and store it with security add-generic-password." >&2
        exit 1
      fi

      if [ "''${CCODE_AUTO_UPDATE:-0}" = "1" ]; then
        "$claude_bin" update >/dev/null 2>&1 || true
      fi

      export CLAUDE_CODE_OAUTH_TOKEN="$token"
      export DISABLE_AUTOUPDATER=1

      local args=()
      if [ "$yolo" = "1" ]; then
        args+=(--dangerously-skip-permissions)
        args+=("''${SAGENT_CLAUDE_YOLO_ARGS[@]}")
      else
        args+=("''${SAGENT_CLAUDE_ARGS[@]}")
      fi

      if [ "''${SAGENT_NO_CONTEXT_NOTE:-0}" != "1" ]; then
        args+=(--append-system-prompt "$(build_context_note claude)")
      fi

      if [ "''${SAGENT_LINK_SESSION:-0}" = "1" ] && [ -n "''${SAGENT_TMUX_SESSION:-}" ]; then
        args+=(--session-id "$(name_to_uuid "$SAGENT_TMUX_SESSION")")
      fi

      SAGENT_WANT_CAFFEINE=1
      run_with_sandbox "$PWD" 0 "$claude_bin" "''${args[@]}" "$@"
    }

    run_codex() {
      local yolo="$1"
      shift

      local codex_bin
      codex_bin="$(find_executable codex SAGENT_CODEX_BIN "$SAGENT_DEFAULT_CODEX_BIN" "''${SAGENT_CODEX_FALLBACK_BINS[@]}")"

      # Codex is sandboxed by the outer SBPL profile from claude-sandbox.
      local args=(
        --dangerously-bypass-approvals-and-sandbox
      )

      if [ "$yolo" = "1" ]; then
        args+=("''${SAGENT_CODEX_YOLO_ARGS[@]}")
      else
        args+=("''${SAGENT_CODEX_ARGS[@]}")
      fi

      # Codex has no system-prompt flag; awareness is env vars plus AGENTS.md.
      # SAGENT_TMUX_SESSION is already exported by the tmux re-exec.
      export SAGENT=1 SAGENT_SANDBOX=1

      SAGENT_WANT_CAFFEINE=1
      run_with_sandbox "$PWD" 0 "$codex_bin" "''${args[@]}" "$@"
    }

    yolo=0
    treehouse=0
    session_flag=""
    attach_target=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --yolo)
          yolo=1
          shift
          ;;
        --treehouse)
          treehouse=1
          shift
          ;;
        --session)
          require_arg "$1" "''${2:-}"
          session_flag="$2"
          shift 2
          ;;
        --attach)
          require_arg "$1" "''${2:-}"
          attach_target="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        --)
          shift
          break
          ;;
        -*)
          echo "error: unknown sagent flag: $1" >&2
          usage
          exit 2
          ;;
        *)
          break
          ;;
      esac
    done

    # --attach is a standalone action: no subcommand, no other flags.
    if [ -n "$attach_target" ]; then
      [ "$#" -eq 0 ] || {
        echo "error: --attach takes no other arguments" >&2
        exit 2
      }
      { [ "$treehouse" = 0 ] && [ -z "$session_flag" ] && [ "$yolo" = 0 ]; } || {
        echo "error: --attach cannot combine with --treehouse/--session/--yolo" >&2
        exit 2
      }
      run_attach "$attach_target"
      exit $?
    fi

    if [ "$#" -lt 1 ]; then
      usage
      exit 2
    fi

    subcommand="$1"
    shift
    if [ "''${1:-}" = "--" ]; then
      shift
    fi

    case "$subcommand" in
      ls)
        [ "$#" -eq 0 ] || {
          echo "error: ls takes no arguments" >&2
          exit 2
        }
        run_ls
        exit $?
        ;;
      kill)
        run_kill "$@"
        exit $?
        ;;
      debug)
        if [ "$yolo" = "1" ]; then
          echo "error: --yolo only applies to claude or codex" >&2
          exit 2
        fi
        if [ "$treehouse" = "1" ] || [ -n "$session_flag" ]; then
          echo "error: --treehouse/--session only apply to claude or codex" >&2
          exit 2
        fi
        run_debug "$@"
        exit $?
        ;;
      help)
        usage
        exit 0
        ;;
      claude | codex) ;;
      *)
        echo "error: unknown sagent command: $subcommand" >&2
        usage
        exit 2
        ;;
    esac

    # Agent path. The outer process (SAGENT_IN_TMUX unset) decides tmux, guards
    # native flags, resolves the session name, leases a worktree, and re-execs
    # into a tmux pane. The inner process skips straight to dispatch.
    if [ -z "''${SAGENT_IN_TMUX:-}" ]; then
      tmux_enabled=0
      if [ "''${SAGENT_TMUX:-1}" != "0" ] && [ -z "''${TMUX:-}" ] &&
        [ -t 0 ] && [ -t 1 ] && command -v tmux >/dev/null 2>&1; then
        tmux_enabled=1
      fi

      guard_claude_native_flags "$tmux_enabled" "$subcommand" "$@"

      # A session name only means something with tmux. Fail before leasing so a
      # named request never silently degrades to a direct, unnamed run.
      if [ "$tmux_enabled" = "0" ] && { [ -n "$session_flag" ] || [ -n "''${SAGENT_SESSION:-}" ]; }; then
        echo "error: --session/SAGENT_SESSION names a durable tmux session, but tmux is inactive here (SAGENT_TMUX=0, no TTY, tmux missing, or already inside a tmux session); re-run in a standalone terminal with tmux, or drop the session name" >&2
        exit 2
      fi

      # Resolve the session name from the repo cwd, before leasing treehouse.
      session=""
      auto_prefix=""
      if [ "$tmux_enabled" = "1" ]; then
        if [ -n "$session_flag" ] || [ -n "''${SAGENT_SESSION:-}" ]; then
          session="$(resolve_session_name)"
        else
          auto_prefix="$(compute_auto_prefix "$subcommand")"
          session="$auto_prefix-$(next_seq "$auto_prefix")"
        fi
      fi

      # Lease a fresh worktree only for a genuinely new launch, then cd into it.
      leased_dir=""
      if [ "$treehouse" = "1" ]; then
        leased_dir="$(resolve_treehouse)"
        cd "$leased_dir"
      fi

      if [ "$tmux_enabled" = "1" ]; then
        launch_tmux_session "$session" "$auto_prefix" "$leased_dir" "$subcommand" "$@"
      fi
    fi

    case "$subcommand" in
      claude) run_claude "$yolo" "$@" ;;
      codex) run_codex "$yolo" "$@" ;;
    esac
  '';
}
