# SPDX-License-Identifier: Apache-2.0

{
  lib,
  writeShellApplication,
  claude-sandbox,
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
in
writeShellApplication {
  name = "sagent";
  runtimeInputs = [ claude-sandbox ];

  text = ''
    : "''${HOME:?HOME must be set}"

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
    usage: sagent [sagent flags...] <debug|codex|claude> [args...]

    sagent flags:
      --yolo       run the selected agent with its yolo permissions flag
      -h, --help   show this help
    EOF
    }

    debug_usage() {
      cat >&2 <<'EOF'
    usage: sagent debug [debug flags...] [--probe path...]

    debug flags:
      --target-dir <dir>   directory used for TARGET_DIR rules (default: current directory)
      --output <file>      write the generated sandbox profile to a file
      --base               dump the built-in base profile instead of the generated profile
      --no-workaround      omit generated parent-directory read rules
      --probe              probe path readability inside the generated sandbox
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

    run_debug_probe() {
      local target_dir="$1"
      local no_workaround="$2"
      shift 2

      local sandbox_args=(--target-dir "$target_dir")
      if [ "$no_workaround" = "1" ]; then
        sandbox_args+=(--no-workaround)
      fi

      # shellcheck disable=SC2016
      exec claude-sandbox "''${sandbox_args[@]}" -- /bin/sh -c '
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

      if [ "$debug_probe" = "0" ] && [ "''${#debug_paths[@]}" -gt 0 ]; then
        echo "error: debug path arguments require --probe" >&2
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

      local sandbox_args=(--target-dir "$debug_target_dir")
      if [ "$debug_no_workaround" = "1" ]; then
        sandbox_args+=(--no-workaround)
      fi

      exec claude-sandbox "''${sandbox_args[@]}" --write-profile "$output_path"
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

      exec claude-sandbox -- "$claude_bin" "''${args[@]}" "$@"
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

      exec claude-sandbox -- "$codex_bin" "''${args[@]}" "$@"
    }

    yolo=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --yolo)
          yolo=1
          shift
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
      claude)
        run_claude "$yolo" "$@"
        ;;
      codex)
        run_codex "$yolo" "$@"
        ;;
      debug)
        if [ "$yolo" = "1" ]; then
          echo "error: --yolo only applies to claude or codex" >&2
          exit 2
        fi
        run_debug "$@"
        ;;
      help)
        usage
        ;;
      *)
        echo "error: unknown sagent command: $subcommand" >&2
        usage
        exit 2
        ;;
    esac
  '';
}
