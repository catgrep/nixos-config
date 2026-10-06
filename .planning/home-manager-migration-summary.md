# Home Manager migration summary

The Mac `bob-mac` moved from a dotfiles repository, a standalone Home Manager subflake at state version 24.11, Homebrew, rustup and ad hoc `go install`, `cargo install` and pipx tools to one root-flake Home Manager configuration at state version 26.05, a nix-darwin system layer for Homebrew and the window manager, and the `hm` helper that drives both.
The four NixOS hosts share the same user file, and the repository now declares the host account as `bobby` instead of `bdhill`.
The run took place on 2026-09-28 (171 commits) and 2026-10-03 (21 commits).
Every phase was committed on local `main` and reviewed by Codex.
The range `4a2f7c9..HEAD` (`d10a244`) holds 192 commits, of which 10 are `planning:` records.
Nothing was pushed, no commit was signed, and no host was deployed.

## How the run worked

One orchestrator session managed the run and edited no files itself.
It spawned one fresh agent per phase with the plan and the phase name, waited for the report, and reviewed the result before the next phase.
After each phase it ran a Codex review of the diff since the previous review, recorded under `.planning/reviews/phase-N-codex.md`.
A fix agent applied the findings that held up, and a `planning: record the codex review of phase N` commit added the review file with a body listing the accepted and the rejected findings and the reason for each rejection.
The orchestrator ran in the sagent sandbox, where the home directory, `/etc`, launchd, Homebrew and SSH to the hosts are read-only or unreachable, so every switch and every host step was recorded as a command for the user instead of being run.
Two agent sessions were cut off by usage limits on 2026-09-28: the Phase 3b darwin agent after its last commit `52cf0e3` and before its report, and the first Phase 3b review-fix agent before it had committed anything.
The tree was clean at `52cf0e3`, so on 2026-10-03 the orchestrator respawned the review-fix agent with the same prompt and the run continued without losing a commit.

## Phases

| Phase | First..last commit | Commits | Date |
|---|---|---|---|
| 0 bootstrap direnv | `7ebb9e9..373ed84` | 5 | 2026-09-28 |
| 1 one flake | `65b6a6f..8f055b2` | 5 | 2026-09-28 |
| 2 shell and dotfiles | `37eb86f..b041496` | 15 | 2026-09-28 |
| 3 first half, toolchains and `hm` | `a6d92d5..92445d1` | 23 | 2026-09-28 |
| 3 packages | `b6be331..4882d50` | 96 | 2026-09-28 |
| 3b nix-darwin | `e34bb15..eb90a1d` | 32 | 2026-09-28 (27), 2026-10-03 (5) |
| 4 repo side | `4767b24..44b3042` | 8 | 2026-10-03 |
| 5 docs | `d897bc3..15a54f6` | 6 | 2026-10-03 |
| PATH order fix after the first switch | `47acd25..d10a244` | 2 | 2026-10-03 |

### Phase 0: bootstrap direnv

Delivered: `multiverse.lock` pins for direnv, nix-direnv, nh, nix-output-monitor and nvd (`7ebb9e9`); `programs.direnv` with nix-direnv and nh, nom and nvd in `home.packages` of the old `home-manager/default.nix` (`d550f23`); `.direnv/` in `.gitignore` and the `watch_file` line in `.envrc` (`1f276d3`, corrected in `89cbb27`).
Commits: `7ebb9e9..373ed84`.
Review: 2 findings, 2 accepted, 0 rejected.
Finding 1 (no active zsh hook until Phase 2) needed no repository change; the hook lived in the unmanaged `.zshrc` as a user step until Phase 2 enabled `programs.zsh`.
Finding 2 was fixed in `89cbb27`.
Deviations: the `watch_file` line sits before `use flake`, because nix-direnv reads the registered watches inside `use_flake` when it decides whether the cached shell is stale, and the plan's Phase 0 example was corrected to match.

### Phase 1: one flake, new state version

Delivered: `homeConfigurations."bobby@bob-mac"` in `flake.nix` (`65b6a6f`); `home-manager/users/bobby.nix` with `stateVersion = "26.05"`; `home-manager/modules/{default,direnv,packages}.nix`; the package list moved unchanged to `home-manager/packages.nix` (`cb40577`); `home-manager/flake.nix` and `flake.lock` deleted (`483da78`); `make home-switch` runs `nh home switch .` (`6bcc018`).
Commits: `65b6a6f..8f055b2`.
Review: 2 findings, 2 accepted as facts, 0 rejected.
Both findings (the generation 19 GC root did not exist, the configuration had not been activated) are user steps outside the sandbox and were already recorded for the user; no repository code changed.
The reviewer's `-c bobby@bob-mac` flag was not adopted, because nh detects the configuration from the user and the LocalHostName and the Makefile relies on that.
Deviations: the switch command is `nh home switch . -b bak` and does not pass `-b bak` after `--`, since nh 4.4.2 takes `-b` itself and passes everything after `--` to `nix build`; the Verify line expects generation 21 rather than 20, because generation 20 is the Phase 0 bootstrap.

### Phase 2: shell and dotfiles

Delivered: pins for fzf, git-lfs, oh-my-zsh and pinentry_mac (`37eb86f`); `home-manager/modules/shell/omz-custom/{aliases,git}.zsh` (`ed56600`); `shell/zsh.nix` with `dotDir` under XDG, oh-my-zsh from the store and a completions directory (`9f22d84`); `git.nix` with signing, aliases and lfs (`fb2df31`); `gpg.nix` with per-platform pinentry (`ec7dad4`); `vim.nix` (`5d83e5e`); `tmux.nix` with a per-platform clipboard (`4bb8741`); `fzf.nix` (`5b310d9`); `home-manager/darwin/default.nix` for the Homebrew path and bindgen (`dc7802d`), `darwin/ghostty.nix` (`69ad0d0`), `darwin/files.nix` with the zed settings and keymap and the npm config (`36ff1a4`); pre-generated completions `_docker _hugo _kubectl _minikube _nfpm`.
Commits: `37eb86f..b041496`.
Review: 4 findings, 4 accepted, 0 rejected.
Findings 1, 3 and 4 were fixed in `c18ea14`, `5f32751` and `0496e2b`.
Finding 2, the missing ssh module, is accepted but deferred: the agent's permission rules deny reading `~/.ssh/config`, and the user is deciding between pasting the host blocks into `ssh.nix` and leaving the file unmanaged.
Deviations: `users/bobby.nix` imports `../darwin` unconditionally and every file there gates its `config` on `isDarwin`, because `imports` cannot depend on `pkgs`.
The gpg module keeps `services.gpg-agent` Linux-only and writes `~/.gnupg/gpg-agent.conf` on the Mac, because the launchd unit Home Manager would generate listens under `/private/var/run`, a directory the user cannot create and the Nix gnupg never looks in.
`vim.nix` sets `packageConfigurable` because `programs.vim.package` is read-only, so no `~/.vimrc` is written.
Phase 2 step 1 now moves `~/.gitconfig` aside, copies the history file under `dotDir` and kills gpg-agent after the switch.
Phase 3 step 3 regenerates the hugo, minikube and nfpm completions from the Nix binaries, and Phase 3 step 5 became a verification of the PATH order with the requirement that Homebrew tools shadowing Apple system tools move to pins.

### Phase 3, first half: toolchains and the hm helper

Delivered: rust-overlay from the omniflake index (`a6d92d5`); pins for go, node, uv and pnpm (`d5f45c6`) and go-tools (`8370229`); `toolchains.nix` and `rust.nix` (`3c0fe62`); `tools/hm` as a Go module with the `txn`, `cli`, `nixlist`, `run` and `sources` packages (`850779c`, `1bf7e25`, `fc05d31`, `6d3b61b`), the `doc` and `gendoc` packages with a generated man page and per-subcommand help (`a19cbf8`), the `completion` package with zsh, bash and fish completion (`63e962e`); `packages.<system>.hm` and `mvs` exported from the flake and `hm` built in `checks.nix` (`d0add8f`); `nh.nix` installing nh, mvs and hm (`55717cc`); the first `hm add`, zizmor 1.30.1 (`6b151dd`).
Commits: `a6d92d5..92445d1`.
Review: 8 findings, 8 accepted, 0 rejected.
Fixed in `27af3e6` (restore only files that still hold what hm wrote), `44cc606` (keep the lists when a failed switch activated a generation), `f36a676` (run lock for switch and sync), `148e089` (dry-run tool preview against the proposed list), `d657c9c` (provenance from store paths), `2d18c73` (fixtures skipped as pin consumers), `8370229` and `259d4bd` (staticcheck in the check phase from the go-tools pin), `d2ab9fe` (package-level variables replaced with constructors, enforced by a test in `main_test.go`).
Deviations: `hm` gained `--build-only` on `add`, `rm`, `up` and `sync` (`38e4b3d` describes it) so agent sessions build and commit without activating and the user activates once at the end.
`hm add --go` requires an explicit version and refuses `@latest`.
`hm list --generation PATH` reads a built but unactivated generation.
The flake exports `packages.<system>.mvs` because `hm up` runs the refreshed mvs through `nix run "$NH_FLAKE#mvs"` after `nix flake update mvs`.
The failure handling in the plan states when a restore is skipped and when a file is left as found.

### Phase 3, packages

Delivered: 86 `home: add` commits produced by `hm add --build-only --commit`: 65 nixpkgs attributes from actionlint (`b6be331`) to zsh-completions, 16 go tools, 2 uv tools and 3 cargo tools, plus three hand-written `home: add` commits for the modules and the darwin-only packages named below; `gh.nix` and `yt-dlp.nix` modules with their pins (`56bcd43`, `d137441`, `c73f841`); sagent passed to Home Manager (`000221d`) so `home-manager/darwin/default.nix` adds `darwin.trash` from nixpkgs and `ast-bro` from the sagent subflake (`5d231c7`); completions regenerated from the Nix hugo, minikube and nfpm (`bb6561c`); three `hm` fixes (`6c4457d`, `9e6a274`, `3316c02`); termshot, bpm-tools and opus-tools (`4aab224`, `366dc7a`, `a48dc47`).
The lists now hold 87 nixpkgs attributes, 16 go entries, 2 uv entries and 3 cargo entries.
Commits: `b6be331..4882d50`.
Review (`phase-3b-packages-codex.md`): 6 findings, 6 accepted, 0 rejected.
Deviations: `hm add` reports and commits the version the target system resolves rather than the index version, after the openjdk commit carried `21.0.12.1+1` while aarch64-darwin resolves `zulu-ca-jdk 21.0.11` (`9e6a274`; the commit `19a6562` now reads `home: add openjdk 21.0.11` with both versions in its body).
`hm sync --force` reinstalls matching entries, because the inventories record versions and not the compiler that built a binary (`3316c02`).
Tool commit subjects name the executable and carry the full `module@version` in the body (`6c4457d`); the ten subjects the previous helper had truncated (the eight kubetest2 subcommands, benchstat and html2markdown) were reworded by replaying the in-session commits.
isocule is not a `go-tools.nix` entry: it is a private module built from a local checkout with `vcs.modified` set, so it stays a local `go install` build that `hm doctor` reports as the one known undeclared binary.
termshot, bpm-tools and opus-tools moved to pins; borders is `services.jankyborders`; llvm and lld stay in `homebrew.brews`; html2markdown lives only in `go-tools.nix`.
The user-side commands of this phase (`rustup self uninstall`, `hm sync --force`, `cargo uninstall`, `brew uninstall pipx`, the `~/go/bin` cleanup, porting `~/.config/gh/config.yml`) are user steps in the gated list or its pre-gate section.

### Phase 3b: nix-darwin

Delivered: nix-darwin from the omniflake index (`677a18b`); `darwinConfigurations."bob-mac"` and `darwin/default.nix` with `nix.enable = false`, `system.primaryUser = "bobby"` and `system.stateVersion = 7` (`e34bb15`); `darwin/homebrew/{default,casks,brews}.nix` with `onActivation.cleanup = "none"`, `global.brewfile = true` and the trusted taps `peonping/tap` and `stacktower-io/tap` (`2b424ee`, `52cf0e3`); 11 casks and 9 formulae, one `darwin: add` commit each through `hm add --cask` and `--brew`; `darwin/services.nix` running yabai, skhd and jankyborders as launchd agents from the rc files in `darwin/skhd/` and `darwin/yabai/` (`25e0bc8`); `hm add --cask`, `--brew` and `hm brew cleanup` with a preview (`e26f7a5`, `aa45195`); `checks.aarch64-darwin.darwin-bob-mac` builds the system.
Commits: `e34bb15..eb90a1d`; the first run ended at `52cf0e3` on 2026-09-28 and the five review-fix commits `65f8b2b..eb90a1d` landed on 2026-10-03.
Review: 5 findings, 5 accepted, 0 rejected.
Findings 1, 2 and 4 were fixed in `65f8b2b`, `d546c93` and `18f4bf4`.
Findings 3 and 5 were resolved as recorded dispositions: the ten library formulae are left for Homebrew cleanup, the four conditional formulae (numpy, poppler, tesseract, python-requests) are the user's decision before the first forced cleanup, and omlx is not declared because it was never installed here.
Deviations: `hm brew cleanup` names the `brew trust` prerequisite, because `brew bundle cleanup` loads the declared formulae before anything has applied the Brewfile's trust flags, which only the install step of a switch does.
A system profile that cannot be read after a successful `nh darwin switch` returns `activatedError` and keeps the list (`d546c93`).
The window-manager bindings that ran scripts under `/Users/jesseskelton/CustomScripts` were removed, five active skhd bindings with three commented-out ones and the `window_destroyed` signal, and the three display shortcuts separate their two yabai commands with `&&` (`18f4bf4`).
`services.nix` installs `pinned.jq` for the skhd bindings instead of `pkgs.jq` (`f057d29`).
borders runs through `services.jankyborders` rather than the Homebrew formula.
Homebrew cleanup stays manual and previewed; activation never removes anything.

### Phase 4: repo side of the account rename

Delivered: `modules/common/users.nix` declares `bobby` inline with uid 1000, the wheel, networkmanager, media and render groups, zsh from the lock and the SSH key, and `users/bdhill.nix` is deleted (`4767b24`); `flake.nix` sets `home-manager.users.bobby = import ./home-manager/users/bobby.nix` with `pinned`, `mvs`, `rust-overlay` and `sagent` as special arguments; `hosts/ser8/samba.nix` names `bobby` in `valid users` and the smbpasswd block while the secret keeps its key name; the two provisioning scripts and `scripts/validation/check-ser8-media-parity.sh` follow; `linux-tools.nix`, `shell/bash.nix` and the Linux-only parts of `zsh.nix` (`f81e42b`); the `gpg-import-signing-subkey` user service (`9e37358`); `scripts/smoketests/pi/{all,test-login,test-sudo,test-builder}.sh` and the `smoketests` paths for pi4 and pi5 in `deploy.yaml` (`124d057`); three fixes (`0282512`, `518a7d4`, `581ce4e`).
Commits: `4767b24..44b3042`.
Review: 1 finding, 1 accepted, 0 rejected; two further findings from the orchestrator were fixed in the same series.
Deviations: the sops key names are unchanged this phase, so `samba_bdhill_password` stays until `make sops-edit-ser8` renames it, because the encrypted file cannot be edited from the sandbox.
`modules/common/signing-key.nix` is a snippet rather than a commit, because sops-nix validates key presence at build time and `gpg_signing_subkey` does not exist in `secrets/shared.yaml` yet.
The import service carries `ConditionPathExists = "/run/secrets/gpg_signing_subkey"` so a host activates before the secret exists.
`deploy.yaml` `targetUser` and `etc/nix/machines` are unchanged until the cutover.
The host-only bits are gated on the platform inside the shared modules instead of a `hosts/<host>/home.nix`.
Inside the agent's scope: the completion zstyles were dropped because Home Manager never emitted `completionInit` with oh-my-zsh enabled, fastfetch is called by name from the hosts' system packages, bash is Linux-only, and the ls and grep aliases replace oh-my-zsh's on the Mac too.
Sharing the config grows every host's home from 5 to 121 packages (the Mac has 113), including the Rust toolchain, openjdk, zig, ffmpeg, minikube, go, node and python, and the Pis build on target, so their first activation downloads several gigabytes and compiles `tools/hm` locally; a host that should stay lean gets a `hosts/<host>/home.nix` that excludes the toolchains.
The Phase 4 runbook was corrected in the plan through `44b3042`: step 7 ends the old account's sessions one by one, step 8 drops `NIXBUILD_USER` and notes that pi5 deploys as `nixos`, step 10 relies on the `samba-password-sync` oneshot and changes the host's `targetUser` right away, step 11 keeps only `etc/nix/machines` for after all four hosts, step 12 adds pi5 as a sops recipient first, and the Verify paragraph states that the smoketests connect as the `deploy.yaml` user while the Pi suite honours `NIXBUILD_USER=bobby`.

### Phase 5: docs

Delivered: the `CLAUDE.md` section on Home Manager, nix-darwin and `hm`, the `bob-mac` workstation in the overview, the repository layout with `darwin/` and `tools/hm`, the Go conventions, the signing paragraph in the secrets section, and the prompt behaviour of `make test-HOST` (`d897bc3`, `1008d19`); the README without the subflake note, with the lock sentence naming the Mac configurations and `hm`, and with the gateway routes the Caddyfile defines (`eb7d9ba`, `751ab5b`); the Makefile comment on the Pi bootstrap image without planning references (`3e5abdc`).
Commits: `d897bc3..15a54f6`.
Review: 16 findings, 15 accepted, 1 rejected.
Finding 16 is rejected because the README introduction is the owner's narrative about the repository's origins and outside the migration documentation.
Two items from the docs agent were applied alongside: the Makefile comment that cited the Phase 9 planning notes, and the README lock sentence that omitted the nix-darwin configuration.
Deviations: only step 4 of the plan's Phase 5 is done.
Steps 1 to 3 (archive the dotfiles repository, trash `~/.oh-my-zsh` and the leftovers) and step 5 (rollback exercise, `keep-gen19` removal, `programs.nh.clean.enable = true`) are item 5 of the gated list.

## The hm helper

`hm` is a Go program in `tools/hm/`, standard library only, module `github.com/catgrep/nixos-config/tools/hm` with `go 1.27`, built by `buildGoModule` on the pinned toolchain with `vendorHash = null` and installed through `home-manager/modules/nh.nix`.
It wraps `mvs lock`, `nh home`, `nh darwin` and the six list files it owns: `home-manager/packages.nix`, `go-tools.nix`, `uv-tools.nix`, `cargo-tools.nix`, `darwin/homebrew/casks.nix` and `brews.nix`, each a bracketed Nix list of double-quoted strings, one per line, with `#` comments allowed between entries.
The source is 6332 lines with 3049 lines of tests.

Subcommands, from `hm --help`:

- `add NAME[@VERSION]` pins a package and installs it; `--cask`, `--brew`, `--go`, `--uv` and `--cargo` select the other lists.
- `rm NAME` removes a package from the list that holds it; `--prune` also drops an unreferenced pin.
- `up [ATTR]` moves pins to the newest indexed revision; `--repo` is required for a pin that `packages.nix` does not list.
- `sync [go|uv|cargo]` installs the tools the lists declare; `--force` reinstalls every entry.
- `switch [home|darwin|all]` runs `nh home switch`, `nh darwin switch` or both.
- `brew cleanup [--force] [--zap]` previews or removes what Homebrew has beyond the lists.
- `list [--source TAG] [--generation PATH]` shows every installed package with its provenance (`pinned`, `nixpkgs`, `custom`, `cask`, `brew`, `go`, `cargo`, `uv`, `native`).
- `status` reports pin drift, lock minimality, uncommitted flake files and the last run.
- `doctor` finds binaries that shadow Nix ones and tools no list declares.
- `try ATTR [-- COMMAND...]` runs a nixpkgs package once without installing it.
- `clean [--keep N]` runs `nh clean user --keep N`, 5 by default, and refuses while `~/.local/state/home-manager/keep-gen19` exists.
- `help [COMMAND]` prints the manual or one command's help; `completion zsh|bash|fish` prints the completion script.

Global flags are `--flake PATH` (default `$NH_FLAKE`), `--dry-run` and `--no-pager`; `add`, `rm` and `up` also take `--build-only` and `--commit`, `sync` takes `--build-only` and `--force`, and `add` alone takes `--keep-on-failure`.
Exit codes: 0 success, 1 failed, 2 usage error, 3 refused (dirty owned file, held lock, unresolved run, different version for a shared pin), 4 the build or switch succeeded but the commit did not.

Shared-lock rules: `multiverse.lock` is shared with the hosts and the dev shell, so `hm add` reuses an existing pin and refuses a different version for an attribute that is already pinned; `hm rm` leaves the pin unless `--prune` is given and no other Nix file in the repository names the attribute, with `testdata` directories and `tools/hm` skipped in that search; `hm up` moves only the pins that `packages.nix` lists unless `--repo` names one, switches only Home Manager, and never passes `--all`; after `nix flake update mvs` it runs the refreshed index through `nix run "$NH_FLAKE#mvs"` rather than the `mvs` on PATH.

Transaction and journal: every run that edits files or changes the machine takes an exclusive lock at `.git/hm.lock`, and a second invocation reports the first's pid and exits 3.
It captures each owned file it may touch and `multiverse.lock` with a content hash, re-reads and compares before every write, writes through a temporary file renamed into place, and runs `nix eval --json` on an edited list before `nh` sees it.
A failure before a generation exists restores every captured file that still holds what `hm` wrote; a file something else changed meanwhile is left as found and named, and the run stays unresolved.
Once a generation exists nothing is reverted: `hm` reads the profile link and the `current-home` root before the switch and again after a failure or an unreadable result, and when they moved or cannot be read it keeps the edited files as the source of the active generation and records the outcome as activated and unresolved.
`--keep-on-failure` skips the restore.
Before an optional commit it hashes the files again and prints the command instead of committing if any differ.
Each run writes one JSON file under `.git/hm/` with the command, the captured hashes, the step reached and the outcome; `hm status` reports the last run, and every later run refuses to start on an unresolved journal until that file has been looked at and removed.
`switch` and a standalone `sync` begin a flow with no captured files, so they take the same lock and honour the same journal.

Tests live next to the code: `tools/hm/internal/cli/{cli,diff,e2e,homebrew}_test.go` (47 test functions, with fake `mvs`, `nix`, `nix-store`, `nh`, `nvd`, `brew`, `go`, `uv` and `cargo` programs run against a throwaway real git repository), `completion/completion_test.go`, `doc/doc_test.go`, `nixlist/nixlist_test.go` with 12 golden fixtures under `nixlist/testdata/`, `run/run_test.go`, `sources/sources_test.go`, `txn/txn_test.go` and `main_test.go`, 104 test functions in all.
The package's check phase runs `go test ./...` and then `staticcheck` from the pinned go-tools, so `nix build .#hm` is the test command and `make check` covers it.
`man hm` is the reference; `hm help` prints the same text, and both are generated from the `internal/doc` structs that render `--help`.

## The host side

`modules/common/users.nix` declares the one interactive account, `bobby`, with uid 1000, `isNormalUser`, the groups wheel, networkmanager, media and render, `shell = config.multiverse.locked.zsh`, and the Mac's SSH public key; `users/bdhill.nix` is gone and `flake.nix` imports `home-manager/users/bobby.nix` for `home-manager.users.bobby` on every host.
The shared user file sets `home.username = "bobby"`, `home.homeDirectory` to `/Users/bobby` or `/home/bobby`, `home.stateVersion = "26.05"`, and imports `../modules` and `../darwin`.
The Linux-only gates add fastfetch on login and the sudo, docker and systemd oh-my-zsh plugins in `shell/zsh.nix`, bash as the fallback shell with the zsh aliases in `shell/bash.nix`, tree, whois, iotop and iftop in `linux-tools.nix`, `services.gpg-agent` with pinentry-curses in `gpg.nix`, and the `gpg-import-signing-subkey` user service.
That service is a oneshot wanted by `default.target` that runs `gpg --batch --import /run/secrets/gpg_signing_subkey` with `ConditionPathExists` on that path, so a host activates before the secret exists and imports the subkey at every session start once it does.
The Pi smoketests in `scripts/smoketests/pi/` check an ssh login with zsh and a present home directory, wheel membership and `sudo -n`, and a Nix store that answers `nix store info --store ssh://...` and reports `aarch64-linux` from `nix config show system`; they read the account from `deploy.yaml` and honour `NIXBUILD_USER`, and `deploy.yaml` points pi4 and pi5 at `./scripts/smoketests/pi/all.sh`.
`deploy.yaml` still names `bdhill` for ser8, firebat and pi4 and `nixos` for pi5, and `etc/nix/machines` still uses `bdhill`.

Two snippets wait for the gated sops edits, quoted from the run record:

> Snippets for after gated secret edits: sed samba_bdhill_password->samba_bobby_password in hosts/ser8/samba.nix (commit `secrets: rename the samba password key to bobby` with the encrypted file); modules/common/signing-key.nix (sops.secrets.gpg_signing_subkey, sopsFile shared.yaml, owner bobby, mode 0400) + import line (commit `secrets: add the git signing subkey for hosts`).

`hosts/ser8/samba.nix` reads the secret as `config.sops.secrets.samba_bdhill_password.path` in two places and declares the key once, so the sed touches three lines.
The import line goes into the `imports` list of `modules/common/default.nix`.

## Found and fixed along the way

These defects were not in the plan.

- `gsk` ignored its branch and base arguments because the argument loop stopped at the first positional, so the rebase acted on the current branch; each positional is now consumed in turn and a fourth is rejected (`c18ea14`).
- The tmux `bind v` piped the buffer into the paste command, which discarded it; it now pipes into the copy command (`5f32751`).
- The iTerm integration loaded under Ghostty because the guard only checked that the file exists; it now requires `TERM_PROGRAM == iTerm.app` (`0496e2b`).
- Eight kubetest2 additions produced one identical truncated subject and benchstat and html2markdown lost their names; tool commits now name the executable (`6c4457d`) and the ten subjects were reworded.
- The openjdk commit carried the index version `21.0.12.1+1` while aarch64-darwin resolves `zulu-ca-jdk 21.0.11`; `hm add` now reports the resolved version and records both in the body when they differ (`9e6a274`, `19a6562`).
- After the first switch the tmux shell had system > `~/.cargo/bin` > Homebrew > nix-profile: `path_helper` from `/etc/zprofile` reorders what `.zshenv` prepended in every login shell, and a shell that inherits `__ETC_PROFILE_NIX_SOURCED` never gets the Nix profiles prepended by the `/etc/zshrc` hook.
  A darwin-only `programs.zsh.initContent` entry at order 515, just after Home Manager's `typeset -U path`, rebuilds `path` as the Nix profiles, the `home.sessionPath` entries without Homebrew, the inherited rest, and `/opt/homebrew/bin` and `/opt/homebrew/opt/llvm/bin` last (`47acd25`, plan note `d10a244`).
- The Makefile's `sops-update-keys` target named `secrets/secrets.yaml`, which does not exist; it now re-encrypts `secrets/shared.yaml` (`581ce4e`).
- The Pi builder probe ran `nix store info` without `BatchMode` or `ConnectTimeout`, so it could sit on a password prompt after a failed login; it now passes `NIX_SSHOPTS` and runs under `timeout 60` (`0282512`).
- `hm` transaction findings: the restore overwrote foreign edits (`27af3e6`), a failed switch that had activated a generation was rolled back (`44cc606`), `switch` and standalone `sync` ran outside the lock (`f36a676`), and an unreadable profile after a successful darwin or home switch restored lists that an active generation was built from (`d546c93`, `518a7d4`).

## What remains

Live state as of 2026-10-05: Home Manager generation 21 is active on the Mac, switched on 2026-10-03 from `15a54f6`; the PATH-order fix `47acd25` is committed but not activated; nix-darwin has never been activated; no host has been touched; the gated list has not started.
Generation 21 is `/nix/store/sgniymiphqdpnrbb0ikgj3rc3qfya1j8-home-manager-generation` and the switch added 8.18 GiB to the store; that path is the reference point for the rollback exercise in gated item 5, where `nvd diff` compares it with `keep-gen19`.
Pre-gate steps A to E from `gated-list.md` are done; `hm doctor` reports 15 duplicate Go binaries, isocule and 5 cargo binaries as undeclared, which step F clears.
The run record logs the switch of step D but not its `cp ~/.zsh_history ~/.config/zsh/.zsh_history` and `gpgconf --kill gpg-agent` commands, so those two are unconfirmed.
The first `nh home switch . -b bak` left five `.bak` files; step E compared `~/.gnupg/gpg-agent.conf.bak` and `~/.npmrc.bak` with the managed files, and the backups can be trashed once the checks are accepted.
The post-switch checks measured `time zsh -ilc exit` at 0.29s, above the plan's Phase 2 Verify target of under 0.25s, so that target is missed; `hm status` reported ok with 203 pins, `gpg-agent.conf` differed from its backup only in the pinentry path with matching TTLs, and `.npmrc` was identical.

User steps still open on the Mac, in order:

1. Activate the PATH fix and re-check the order:

```
cd ~/github/catgrep/nixos-config && nh home switch .
command -v rg fd git jq vim gpg go node cargo rust-analyzer
```

2. Tool cleanup, step F of `gated-list.md`:

```
trash ~/go/bin/{buf,diffoci,dlv,go-arch-lint,go-licenses,goda,gopls,gotests,gotestsum,hclfmt,mani,nfpm,protoc-gen-go,protoc-gen-go-grpc,staticcheck}
hm sync go --force && hm sync uv && hm sync cargo --force
brew uninstall pipx && trash ~/.local/pipx
cargo uninstall cargo-audit cargo-careful cargo-deny cargo-watch prek
git branch -D backup-before-reword
```

`git branch -D backup-before-reword` removes the one branch this run created; the branch `fix/frigate-coco-labelmap` is pre-existing and stays, and the six pre-existing stashes, all dated 2025 and counted as three in the run record, are not touched.

Two decisions pending:

- `~/.config/gh/config.yml.pre-hm` and `~/.ssh/config`: paste their settings into `programs.gh.settings` and a new `ssh.nix` using `programs.ssh.settings` with `enableDefaultConfig = false`, or leave both files unmanaged.
  `~/.ssh/config` holds three host blocks and a Colima include, per finding 2 of `phase-2-codex.md`, which is what an `ssh.nix` module would carry.
- Whether to trim the Pis with a `hosts/<host>/home.nix` that excludes the toolchains, since the shared home grows each host from 5 to 121 packages and the Pis build on target.

The gated list, in section 11 order, with the commands from `gated-list.md`.
Each runs from a non-sandboxed shell, and the output of each is reported back before the next one.

1. nix-darwin (Phase 3b):

```
brew services stop yabai
cd ~/github/catgrep/nixos-config && nh darwin switch .      # first activation: sudo; moves /etc/{bashrc,zprofile,zshenv,zshrc} to *.before-nix-darwin and links them; creates ssh/sshd/sudoers/pam/ssl files
launchctl list | grep -E 'yabai|skhd|borders'
brew trust peonping/tap stacktower-io/tap                 # one-time, lets brew bundle cleanup compute candidates
hm brew cleanup                                           # preview; decide numpy, poppler, tesseract, python-requests first (cleanup removes them)
hm brew cleanup --force                                   # gated; --zap only if cask data should go too
hm add --cask --commit <name> round trip (plan verify)
```

The first switch also creates `pam.d/sudo_local`, `skhdrc`, `ssh/ssh_config.d/100-nix-darwin.conf`, `ssh/sshd_config.d/{099-host-keys,100-nix-darwin,101-authorized-keys}.conf`, `ssl/certs/ca-certificates.crt` and `sudoers.d/10-nix-darwin-extra-config` under `/etc`.
The untracked taps `aeroxy/tap` and `asmvik/formulae` are left to the cleanup preview.

2. rustup (Phase 3), after `cargo --version` resolves under `/nix/store`:

```
rustup self uninstall
```

3. Signing subkey (Phase 4 prep):

```
gpg --export-secret-subkeys --armor <subkey-id>!   -> paste into `make sops-edit-shared` as gpg_signing_subkey
make sops-add-host-keys (pi5)   then   make sops-update-keys   (re-encrypt shared.yaml for pi5)
then commit modules/common/signing-key.nix + import line: `secrets: add the git signing subkey for hosts`
optional: make sops-edit-ser8 rename samba_bdhill_password -> samba_bobby_password; sed in hosts/ser8/samba.nix; commit `secrets: rename the samba password key to bobby`
```

4. Account rename, ser8 -> firebat -> pi4 -> pi5, each in one open root session (plan Phase 4 steps 5 to 13 as corrected):

```
ssh bdhill@HOST; sudo -i
snapshot: ser8 `zfs snapshot rpool/safe/home@pre-rename`; firebat tar /home into /persist; pis tarball
loginctl list-sessions; loginctl terminate-session <id> for every bdhill session except the current (loginctl session-status shows it)
mv /home/bdhill /home/bobby        (pi5: nothing to move; deploys as nixos)
from the Mac: make test-HOST      (deploy.yaml still bdhill; pi5 as nixos)
new terminal: ssh bobby@HOST sudo true   (fail -> switch-to-configuration test on the previous generation, mv back, stop)
make switch-HOST; ser8: sudo smbpasswd -x bdhill
edit deploy.yaml targetUser for that host -> bobby; make smoketests-HOST
after all four: etc/nix/machines -> bobby; make update-nix-conf; nix build --builders @/etc/nix/machines on an x86_64-linux derivation
systemctl --user start gpg-import-signing-subkey on each host; git commit --allow-empty -m test signs
commit `deploy: connect to hosts as bobby`
```

The runbook corrections folded into that item: `loginctl terminate-user bdhill` is not used because it would end the root shell's own session scope, so sessions are terminated one by one; each host's `targetUser` in `deploy.yaml` changes right after its switch, because the ser8 and gateway smoketests connect as that user, while the Pi suite can run earlier with `NIXBUILD_USER=bobby`; pi5 becomes a recipient of `secrets/shared.yaml` (`make sops-add-host-keys`, `make sops-update-keys`) before the subkey can reach it, since `.sops.yaml` lists only pi4, firebat and ser8; `smbpasswd -a bobby` runs through the `samba-password-sync` oneshot on activation, so `sudo smbpasswd -x bdhill` is the one manual Samba step; `NIXBUILD_USER=bdhill` is redundant, and pi5 has no `/home/bdhill` to move.
The one interactive moment in that item is the subkey import: a passphrase-protected subkey prompts once through pinentry-curses over the ssh tty, and the 400-day cache then holds.

5. Rollback exercise and nh clean (Phase 5):

```
activate gen 19 from its GC root (`~/.local/state/home-manager/keep-gen19/activate`), then `nh home switch .` forward
trash ~/.local/state/home-manager/keep-gen19
commit `home: enable nh clean after the rollback test` (programs.nh.clean.enable = true, --keep 5); nh home switch .
archive dotfiles repo (tag, push, remove checkout); trash ~/.oh-my-zsh ~/.zshrc.pre-oh-my-zsh ~/.zcompdump* ~/Brewfile
```

After the gated list the user re-signs the unsigned commits since `4a2f7c9` (192 at `d10a244`, plus the ones the gated list adds) with a date-preserving rebase and pushes; no agent does either.

## Review files

| Phase | File | Findings | Accepted | Rejected | Record commit |
|---|---|---|---|---|---|
| 0 | `.planning/reviews/phase-0-codex.md` | 2 | 2 | 0 | `373ed84` |
| 1 | `.planning/reviews/phase-1-codex.md` | 2 | 2 | 0 | `8f055b2` |
| 2 | `.planning/reviews/phase-2-codex.md` | 4 | 4 (1 deferred: ssh module) | 0 | `b041496` |
| 3 first half | `.planning/reviews/phase-3a-codex.md` | 8 | 8 | 0 | `92445d1` |
| 3 packages | `.planning/reviews/phase-3b-packages-codex.md` | 6 | 6 | 0 | `4882d50` |
| 3b | `.planning/reviews/phase-3b-codex.md` | 5 | 5 (2 as recorded dispositions) | 0 | `eb90a1d` |
| 4 | `.planning/reviews/phase-4-codex.md` | 1 | 1 | 0 | `44b3042` |
| 5 | `.planning/reviews/phase-5-codex.md` | 16 | 15 | 1 | `15a54f6` |
| Total | 8 files | 44 | 43 | 1 | |
