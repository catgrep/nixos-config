# Codex review of the Home Manager migration plan

Run 2026-09-28 against commit 914f188 with `codex exec --dangerously-bypass-approvals-and-sandbox`, model gpt-6-astra, read-only.

No repository files were modified.

Source abbreviations: **H** = [locked Home Manager](/nix/store/s14kfq13km82w650jynvl12is74m20ps-source), **N** = [root nixpkgs](/nix/store/5nkggxpr2qy7v4z4b7x2056a4wsgrgy3-source), **D** = [nix-darwin selected by the locked omniflake](/nix/store/8ggr67sci43hlp8ba6rhjrdhhj5490am-source), **B** = [/opt/homebrew/Library/Homebrew](/opt/homebrew/Library/Homebrew).

1. **Blocker: duplicate UID prevents the transition configuration building.**  
   **Plan §7, lines 647–648.** Both accounts would have UID 1000. NixOS enforces unique IDs by default and rejects this configuration. Evidence: `users/bdhill.nix:21`; **N** `nixos/modules/config/users-groups.nix:706,1071`.  
   **Fix:** establish a temporary recovery administrator with a distinct UID, verify its SSH/sudo access, then replace the old account with the new account in one configuration. Preserve UID 1000 for the renamed account.

2. **Blocker: deployment credentials change before the account exists.**  
   **Plan §7, lines 649–650.** Updating `targetUser` first makes the initial deployment connect as nonexistent `bobby`. Host resolution also uses that username before applying `NIXBUILD_USER`. Evidence: `scripts/nixos-rebuild.sh:44–49`; `scripts/lib/ssh.sh:17,30`. Pi5 currently targets `nixos`, not `bdhill` (`deploy.yaml:34`).  
   **Fix:** retain each host’s working deployment identity through account creation, verify a fresh `bobby` login and sudo, then update deployment metadata and the installed builder configuration per host.

3. **Major: the home move occurs after activation creates its destination.**  
   **Plan §7, line 650; §9, line 686.** Normal users default to `createHome = true`; integrated Home Manager then populates `/home/bobby`. The proposed `mv` can therefore produce `/home/bobby/bdhill`. Reverting the configuration does not reverse this filesystem move or Samba’s persisted database. Evidence: **N** `nixos/modules/config/users-groups.nix:480–484`; `hosts/ser8/samba.nix:32`.  
   **Fix:** stop user sessions, back up/snapshot the actual home storage, migrate into an absent destination before Home Manager activation, and document the reverse migration. Verify mounts per host: ser8 has `rpool/safe/home` (`disko-config.nix:204`), whereas firebat declares ext4 (`disko-config.nix:33–38`). Test login, Samba, builders and reboot recovery.

4. **Major: `hm` treats a repository-wide lock as a private package list.**  
   **Plan §4, lines 332–337.** Reversing `hm add` by removing a pin can break host or development-shell consumers. Unqualified `hm up` updates every pin, including server applications, while only switching Home Manager. Re-adding an existing attribute without its version can replace its constraint. Evidence: `dev.nix:15–40`; `modules/common/multiverse.nix:3–11`; multiverse `mvs/src/lock.rs:137–140,162–168`.  
   **Fix:** reuse existing pins; make removal detach the Home Manager selection only; restrict ordinary updates to explicitly selected home packages. Require an explicit repository-wide operation for shared-pin changes and validate affected consumers.

5. **Major: refreshing `mvs` does not refresh the running executable’s index.**  
   **Plan §4, line 337.** The subsequent PATH-resolved `mvs` still comes from the previous shell/generation. Existing version constraints also remain effective. Evidence: `CLAUDE.md:121–123`; `dev.nix:46`; `multiverse.lock:256`.  
   **Fix:** invoke the refreshed flake’s `mvs` executable explicitly, preserve/report constraints, and include both lock files in the operation’s recorded changes.

6. **Major: the module wiring is incomplete.**  
   **Plan §2, lines 109,160; §4, lines 384–429.** `nh.nix` requires `mvs`, but neither proposed standalone arguments nor existing integrated arguments supply it. Also, `packages.nix` becomes a string list, so “imports every file below” cannot include it as a module. Deleting `users/bdhill.nix` leaves the existing root import unless explicitly replaced. Evidence: `flake.nix:156–166`; plan line 429.  
   **Fix:** pass `mvs` to both Home Manager entry points, consume package data from a separate module, and replace the old root user wiring.

7. **Major: Go paths are relative and invalid.**  
   **Plan §2, lines 251–252.** `programs.go.env` writes values verbatim into Go’s environment file; it does not apply the old `goPath`/`goBin` home-relative conversion. Evidence: **H** `modules/programs/go.nix:26–36,168–176`.  
   **Fix:** use `"${config.home.homeDirectory}/go"` and `"${config.home.homeDirectory}/go/bin"`. Explicitly add the binary directory to PATH and verify `go env` plus an installation from another working directory.

8. **Major: Homebrew Go declarations violate both syntax and toolchain assumptions.**  
   **Plan §3, lines 273–280; §4, line 335.** Installed Homebrew appends `@latest` itself, producing `@latest@latest` for these entries. It inventories concrete package paths, making `/...` unsuitable for reliable reconciliation. nix-darwin also documents automatic installation of Homebrew’s Go formula. Evidence: **B** `bundle/extensions/go.rb:51–66,87`; **D** `modules/homebrew.nix:909–917`.  
   **Fix:** use concrete unversioned paths and accept Brew-managed Go, or use an explicit installer driven by `pinned.go_1_27` if pinned toolchains/versioned targets remain requirements.

9. **Major: the cleanup gate cannot establish that deletion is safe.**  
   **Plan §7, lines 638–641.** `brew bundle check` only checks declared dependencies; undeclared applications can still be removed, with cask data deleted by `zap`. `brew leaves` also need not equal declarations because declared formulas can depend on one another. Evidence: **B** `bundle/subcommand/check.rb:13–16`; **D** `modules/homebrew.nix:102–106`.  
   **Fix:** review the generated Brewfile and a non-forced cleanup preview, including Go binaries and cask data. Compare declarations against the complete installed inventory before enabling cleanup.

10. **Major: file-scoped commits can capture unrelated edits.**  
    **Plan §4, lines 369–379.** `git commit -- <paths>` commits each selected file’s current contents, including pre-existing changes. It does not isolate the helper’s edits and fails for untracked files. Evidence: the exact command at plan line 374.  
    **Fix:** reject dirty owned files before mutation or isolate the operation’s patch with a temporary index. Define atomic writes, concurrent-edit detection, and recoverable behavior after build, activation or signing failure.

11. **Major: parser ownership and inventory provenance are underspecified.**  
    **Plan §4, lines 293–294,333–335,347–429.** The helper alternately owns an entire Nix module and standalone string lists. Go’s standard library has no TOML decoder. A generation’s `home-path` also does not encode source tags such as `pinned` versus `custom`. Evidence: **H** `modules/home-environment.nix:914–925`; plan line 357.  
    **Fix:** define dedicated data files and a restricted grammar, use a real TOML parser or Cargo output, and embed package provenance metadata in each generation. Keep installed inventory separate from declarations.

12. **Major: bootstrap and verification have gaps.**  
    **Plan §7, lines 606–609,627,653.** Phase 1 requires `nh` before Phase 3 installs it. A generic flake check does not replace explicitly building the custom Home Manager output. Pi smoketests are currently literal `test` commands, not useful checks (`deploy.yaml:30,37`; `Makefile:271–272`).  
    **Fix:** bootstrap `nh` explicitly; build the home activation package, Darwin system and all four host configurations; add real Pi login/sudo/builder tests.

13. **Major: keeping five generations does not preserve generation 19.**  
    **Plan §4, line 390; §9, line 683.** The plan performs dozens of individual switches and enables automatic cleanup. Generation 19 will fall outside the retained five. Evidence: plan line 628; **H** `modules/programs/nh.nix:134–160`.  
    **Fix:** preserve the known-good generation with an explicit GC root and defer cleanup until rollback testing finishes.

14. **Minor: package migration instructions contradict their own exceptions.**  
    **Plan §5, lines 470,481,505; §7, line 628.** Not every survey row can pass through `hm add`: `darwin.trash` is nested, ast-bro is a subflake export, and `pinentry_mac` must stay Darwin-only. Merely retaining ast-bro in the development shell does not provide it elsewhere. Evidence: `dev.nix:43`; **N** `pkgs/tools/security/pinentry/mac.nix:101`.  
    **Fix:** separate module-managed, platform-specific, nested and custom selections before the bulk migration.

Things to retain:

- Root-flake consolidation and preserved omniflake dependencies are sound. Standalone Home Manager uses `extraSpecialArgs`; nix-darwin correctly uses `specialArgs`.
- The `buildGoModule.override { go = pinned.go_1_27; }` pattern is valid.
- Absolute `zsh.dotDir`, `oh-my-zsh.custom`, `gpg-agent.pinentry.package`, and `nh.flake` are valid.
- `26.05` also enables Darwin `copyApps`, including permission checks; `.gnupg` does **not** automatically move to XDG. Account for those behaviors without abandoning the chosen state version.