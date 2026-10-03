Reviewed `4882d50..52cf0e3`. Ranked findings:

1. **P2: Cleanup preview fails on this machine before showing removals.**  
   [tools/hm/internal/cli/homebrew.go:227](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/homebrew.go:227)  
   **Evidence:** `hm --dry-run brew cleanup` exits 1, requesting `brew trust peonping/tap`. The generated Brewfile includes `trusted: true`, but installed Homebrew calculates cleanup candidates before applying Brewfile trust. This breaks the documented preview-before-first-switch behavior.  
   **Fix:** Add explicit trust prerequisite detection and instructions, or evaluate the preview using an isolated temporary trust configuration derived from the declared taps. Preserve the preview’s non-mutating behavior and test against an initially untrusted tap.

2. **P2: A successful Darwin switch can trigger restoration of its source files.**  
   [tools/hm/internal/cli/homebrew.go:160](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/homebrew.go:160)  
   **Evidence:** After `nh darwin switch` succeeds, a failure reading the system profile returns an ordinary error. `addHomebrew`/`rmHomebrew` pass that to `f.fail`, which restores the edited list. The failed-switch branch correctly treats unreadable state as `activatedError`; the successful-switch branch does not. Consequently, deployed state and committed configuration can diverge.  
   **Fix:** Return `activatedError` when the post-success state cannot be read, retaining the configuration and recording an unresolved outcome. Add a test where the mocked switch succeeds but leaves an unreadable profile.

3. **P2: Explicitly requested Homebrew packages remain unaccounted for.**  
   [darwin/homebrew/brews.nix:2](/Users/bobby/github/catgrep/nixos-config/darwin/homebrew/brews.nix:2), [migration plan:811](/Users/bobby/github/catgrep/nixos-config/.planning/home-manager-migration-plan.md:811)  
   **Evidence:** `brew info --json=v2 --installed` marks these ten formulae `installed_on_request: true`, but neither the plan nor the Home Manager/Homebrew declarations gives them a disposition:  
   `aom`, `flac`, `glib`, `harfbuzz`, `jpeg-xl`, `libass`, `libffi`, `libsoxr`, `opus`, `pango`.  
   Four additional requested formulae remain deferred choices without declarations: `numpy`, `poppler`, `tesseract`, `python-requests`. Being libraries or potential transitive dependencies does not establish an intentional disposition.  
   **Fix:** Record retain, replace, or remove decisions for all fourteen before approving forced cleanup. Declare retained functionality in the appropriate package list.

4. **P2: Newly managed window-manager configuration contains broken commands.**  
   [darwin/skhd/skhdrc:27](/Users/bobby/github/catgrep/nixos-config/darwin/skhd/skhdrc:27), [darwin/skhd/skhdrc:31](/Users/bobby/github/catgrep/nixos-config/darwin/skhd/skhdrc:31), [darwin/yabai/yabairc:110](/Users/bobby/github/catgrep/nixos-config/darwin/yabai/yabairc:110)  
   **Evidence:** Five active shortcuts and the window-destroyed callback reference `/Users/jesseskelton/CustomScripts/...`; `/Users/jesseskelton` does not exist. The three display shortcuts also omit a command separator: a harmless shell stub confirmed they invoke one `yabai` command containing the second command’s arguments.  
   **Fix:** Package the required scripts and reference their store paths, or replace the bindings with self-contained commands. Separate display movement and focus with `&&`. Validate command construction without contacting the running yabai service.

5. **P2: The planned `omlx` installation is missing.**  
   [darwin/homebrew/brews.nix:9](/Users/bobby/github/catgrep/nixos-config/darwin/homebrew/brews.nix:9), [darwin/homebrew/default.nix:18](/Users/bobby/github/catgrep/nixos-config/darwin/homebrew/default.nix:18)  
   **Evidence:** The plan explicitly retains `omlx` through `jundot/omlx`. Neither is declared, and `/opt/homebrew/Cellar/omlx` is absent. The tap checkout exists, but that does not install the application.  
   **Fix:** Declare the trusted `jundot/omlx` tap and its formula, or record an explicit decision to drop it.

Verification: all hm tests and `go vet ./...` passed. Exercised dry-run cask/brew additions, removals, build-only operations, Darwin/all switches, and forced/zapped cleanup. The actual cleanup preview failed as described above.

Checked option definitions against locked Home Manager `09ae1b85…` and omniflake-selected nix-darwin `4cff07de…`; both configuration derivations evaluate successfully. The service options, launchd labels, `stateVersion = 7`, and trusted-tap options are valid. All eleven installed cask receipts are represented; the extra `brew list --cask` entry `syncthing` is a symlink to `syncthing-app`.

Environment warnings affected Nix/Homebrew; formatting checks also flagged trailing blank lines in the copied rc files. No generations were activated, no launchd agents were changed, and the worktree remains clean.