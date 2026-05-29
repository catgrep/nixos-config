# SPDX-License-Identifier: Apache-2.0

{
  lib,
  writeShellApplication,
  claude-sandbox,
  extraWritePaths ? [ ],
  extraEnv ? { },
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
    SAGENT_NETWORK_ACCESS=${if networkAccess then "1" else "0"}
    ${mkShellArray "SAGENT_EXTRA_WRITE_PATHS" extraWritePaths}
    ${mkShellArray "SAGENT_UNIX_SOCKET_PATHS" unixSocketPaths}
    ${mkShellArray "SAGENT_CODEX_FALLBACK_BINS" codexFallbackBins}
    ${mkShellArray "SAGENT_CLAUDE_ARGS" claudeArgs}
    ${mkShellArray "SAGENT_CLAUDE_YOLO_ARGS" claudeYoloArgs}
    ${mkShellArray "SAGENT_CODEX_ARGS" codexArgs}
    ${mkShellArray "SAGENT_CODEX_YOLO_ARGS" codexYoloArgs}

    ${envExports}

    usage() {
      cat >&2 <<'EOF'
    usage: sagent <codex|codex-yolo|claude|claude-yolo> [agent args...]
    EOF
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

    toml_escape_string() {
      local value="$1"
      value="''${value//\\/\\\\}"
      value="''${value//\"/\\\"}"
      printf '"%s"' "$value"
    }

    toml_array() {
      local first=1
      local path
      local expanded

      printf '['
      for path in "$@"; do
        expanded="$(expand_path "$path")"
        if [ "$first" = "0" ]; then
          printf ','
        fi
        toml_escape_string "$expanded"
        first=0
      done
      printf ']'
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
      local approval_policy="$1"
      shift

      local codex_bin
      codex_bin="$(find_executable codex SAGENT_CODEX_BIN "$SAGENT_DEFAULT_CODEX_BIN" "''${SAGENT_CODEX_FALLBACK_BINS[@]}")"

      local args=(
        --sandbox workspace-write
        --ask-for-approval "$approval_policy"
      )

      if [ "$SAGENT_NETWORK_ACCESS" = "1" ]; then
        args+=(-c sandbox_workspace_write.network_access=true)
      fi

      if [ "''${#SAGENT_UNIX_SOCKET_PATHS[@]}" -gt 0 ]; then
        local unix_socket_config
        unix_socket_config="$(toml_array "''${SAGENT_UNIX_SOCKET_PATHS[@]}")"
        args+=(-c "network.allow_unix_sockets=$unix_socket_config")
      fi

      local dir
      local expanded_dir
      for dir in "''${SAGENT_EXTRA_WRITE_PATHS[@]}"; do
        expanded_dir="$(expand_path "$dir")"
        args+=(--add-dir "$expanded_dir")
        if [ -d "$expanded_dir/.git" ]; then
          args+=(--add-dir "$expanded_dir/.git")
        fi
      done

      if [ "$approval_policy" = "never" ]; then
        args+=("''${SAGENT_CODEX_YOLO_ARGS[@]}")
      else
        args+=("''${SAGENT_CODEX_ARGS[@]}")
      fi

      exec "$codex_bin" "''${args[@]}" "$@"
    }

    if [ "$#" -lt 1 ]; then
      usage
      exit 2
    fi

    profile="$1"
    shift
    if [ "''${1:-}" = "--" ]; then
      shift
    fi

    case "$profile" in
      claude)
        run_claude 0 "$@"
        ;;
      claude-yolo)
        run_claude 1 "$@"
        ;;
      codex)
        run_codex on-request "$@"
        ;;
      codex-yolo)
        run_codex never "$@"
        ;;
      -h|--help|help)
        usage
        ;;
      *)
        echo "error: unknown sagent profile: $profile" >&2
        usage
        exit 2
        ;;
    esac
  '';
}
