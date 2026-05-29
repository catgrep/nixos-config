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
  networkAccess ? false,
  unixSocketPaths ? [ ],
}:

let
  # SBPL's `subpath` operand is a literal string; it does not expand `~`.
  mkSubpath =
    p:
    let
      path = toString p;
    in
    if lib.hasPrefix "~/" path then
      ''(subpath (string-append (param "HOME_DIR") "${lib.removePrefix "~" path}"))''
    else if lib.hasPrefix "/" path then
      ''(subpath "${path}")''
    else
      throw "extra sandbox path must be absolute or '~/'-prefixed: ${path}";

  mkLiteral =
    p:
    let
      path = toString p;
    in
    if lib.hasPrefix "~/" path then
      ''(literal (string-append (param "HOME_DIR") "${lib.removePrefix "~" path}"))''
    else if lib.hasPrefix "/" path then
      ''(literal "${path}")''
    else
      throw "unix socket path must be absolute or '~/'-prefixed: ${path}";

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

  networkFragment = lib.optionalString networkAccess ''

    ;; sagent: unrestricted outbound network access
    (allow network-outbound)
  '';

  unixSocketsFragment = lib.optionalString (unixSocketPaths != [ ]) ''

    ;; sagent: Unix socket access
    (allow file-read*
    ${lib.concatMapStringsSep "\n" mkLiteral unixSocketPaths}
    )
    (allow network-outbound
    ${lib.concatMapStringsSep "\n" mkLiteral unixSocketPaths}
    )
  '';

  fragment = writeText "sagent-claude-sandbox-extras.sb" (
    officialInstallerFragment
    + extraReadsFragment
    + extraWritesFragment
    + networkFragment
    + unixSocketsFragment
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
