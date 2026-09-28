# SPDX-License-Identifier: GPL-3.0-or-later

# One signed git identity on every machine. The macOS keychain credential
# helper is the only platform-specific setting.
{
  lib,
  pkgs,
  pinned,
  ...
}:
let
  darwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  programs.git = {
    enable = true;
    package = pinned.git;

    signing = {
      key = "05BE930549C3E945BA3D8B6E72B6A6E95F049306";
      format = "openpgp";
      signByDefault = true;
    };

    lfs = {
      enable = true;
      package = pinned.git-lfs;
    };

    ignores = [
      "*~"
      ".DS_Store"
      "**/.claude/settings.local.json"
    ];

    settings = lib.mkMerge [
      {
        user = {
          name = "Bobby Dhillon";
          email = "bdhillon1994@gmail.com";
        };
        core.editor = "vim +':set colorcolumn=50,72'";
        init.defaultBranch = "main";
        pull.rebase = true;
        push.default = "simple";
        color.ui = true;
        format.pretty = "format:%C(auto)%h %s%n%n%b";
        credential."https://dev.azure.com".useHttpPath = true;

        alias = {
          rb = "rebase";
          rbi = "rebase --interactive";
          rbc = "rebase --continue";
          resign = "rebase origin/main --gpg-sign --committer-date-is-author-date --force-rebase";
          sh = "stash";
          shp = "stash pop";
          co = "checkout";
          cp = "cherry-pick";
          cpa = "cherry-pick --amend";
          br = "branch";
          brl = "!git --no-pager branch --list";
          ci = "commit";
          cia = "commit --amend";
          st = "status";
          lgo = "log --pretty=oneline";
          lg =
            "log --graph --abbrev-commit --pretty=format:'"
            + "%G? %Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'";
          big-files = lib.concatStringsSep " | " [
            "!git rev-list --objects --all"
            "git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)'"
            "sed -n 's/^blob //p'"
            "sort -nk2"
            "cut -c 1-12,41-"
            (
              "$(command -v gnumfmt || echo numfmt)"
              + " --field=2 --to=iec-i --suffix=B --padding=7 --round=nearest"
            )
          ];
          big-objects = lib.concatStringsSep " | " [
            "!git rev-list --all"
            "parallel git ls-tree -r --long {}"
            "sort -uk3"
            "sort -nk4"
          ];
        };
      }
      (lib.mkIf darwin { credential.helper = "osxkeychain"; })
    ];
  };
}
