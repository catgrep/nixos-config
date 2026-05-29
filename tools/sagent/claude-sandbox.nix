# SPDX-License-Identifier: Apache-2.0

# Patched claude-code-sandbox: extends upstream noread.sb with shared
# allow/deny rules. The sagent wrapper consumes this derivation as a runtime
# input for Claude profiles.

{
  lib,
  writeText,
  claude-code-sandbox-src,
  extraReadPaths ? [ ],
  extraWritePaths ? [ ],
  denyClaudeConfigWrites ? true,
  allowDockerSocket ? false,
}:

let
  # SBPL's `subpath` operand is a literal string; it does not expand `~`.
  mkSubpath =
    p:
    if lib.hasPrefix "~/" p then
      ''(subpath (string-append (param "HOME_DIR") "${lib.removePrefix "~" p}"))''
    else if lib.hasPrefix "/" p then
      ''(subpath "${p}")''
    else
      throw "extra sandbox path must be absolute or '~/'-prefixed: ${p}";

  extraReadsFragment = lib.optionalString (extraReadPaths != [ ]) ''

    ;; sagent: extra read-only paths
    (allow file-read*
    ${lib.concatMapStringsSep "\n" mkSubpath extraReadPaths}
    )
  '';

  extraWritesFragment = lib.optionalString (extraWritePaths != [ ]) ''

    ;; sagent: extra read-write paths
    (allow file-read* file-write*
    ${lib.concatMapStringsSep "\n" mkSubpath extraWritePaths}
    )
  '';

  configDenyFragment = lib.optionalString denyClaudeConfigWrites ''

    ;; sagent: prevent in-sandbox tampering with Claude config and hooks.
    (deny file-write*
      (regex #"/\.claude/settings(\.local)?\.json([.~].*)?$")
      (subpath (string-append (param "HOME_DIR") "/.claude/hooks")))
  '';

  officialInstallerFragment = ''

    ;; sagent: official-installer Claude binary, data, and state
    (allow file-read*
      (subpath (string-append (param "HOME_DIR") "/.local/bin"))
      (subpath (string-append (param "HOME_DIR") "/.local/share/claude"))
      (subpath (string-append (param "HOME_DIR") "/.local/state/claude")))
  '';

  # Docker Desktop on macOS routes /var/run/docker.sock to a per-user socket
  # under ~/.docker/run/docker.sock. The sandbox needs both file-read on the
  # symlink and real path, plus network-outbound on the unix socket.
  dockerSocketFragment = lib.optionalString allowDockerSocket ''

    ;; sagent: docker daemon socket access (Docker Desktop on macOS)
    (allow file-read*
      (literal "/var/run/docker.sock")
      (literal (string-append (param "HOME_DIR") "/.docker/config.json"))
      (literal (string-append (param "HOME_DIR") "/.docker/run/docker.sock")))
    (allow network-outbound
      (literal (string-append (param "HOME_DIR") "/.docker/run/docker.sock")))
  '';

  fragment = writeText "sagent-claude-sandbox-extras.sb" (
    officialInstallerFragment
    + extraReadsFragment
    + extraWritesFragment
    + dockerSocketFragment
    + configDenyFragment
  );
in
claude-code-sandbox-src.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    grep -q '=== IMPORTANT === MODIFY this section' noread.sb \
      || { echo "upstream noread.sb changed; review tools/sagent/claude-sandbox.nix" >&2; exit 1; }
    cat ${fragment} >> noread.sb
  '';
})
