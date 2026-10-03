Reviewed `44b3042..eb7d9ba` against HEAD, hm’s actual `--help`, `help`, installed man page, and nh’s help. No files changed, generations activated, or secret files inspected. Findings include pre-existing statements within the requested documents.

1. **High | [CLAUDE.md:134](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:134): Exit codes do not guarantee restoration or activation.**  
   “1 failed and restored” is false when activation changed, its state is unreadable, another process edited files, or `--keep-on-failure` applies (`tools/hm/internal/cli/flow.go:136`). Code 4 also occurs after `--build-only`, without switching. **Fix:** describe failure without restoration guarantees; document `.git/hm/*.json`, reviewing/reconciling retained files, and acknowledging the specific unresolved journal before retrying.

2. **High | [CLAUDE.md:161](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:161): Deployment commands do not uniformly prompt.**  
   `scripts/nixos-rebuild.sh:162` runs `test` immediately; only `switch` and `reboot` call `nixos_confirm`. Consequently, `apply` activates its test configuration before its first prompt. **Fix:** explicitly require intent for `test-HOST` and identify exactly which commands prompt.

3. **Medium | [CLAUDE.md:29](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:29): Declared and operational accounts are conflated.**  
   HEAD declares `bobby`, but `deploy.yaml:13,20,27,34` still selects `bdhill` or `nixos`; `etc/nix/machines` uses `bdhill` throughout. Repository state cannot establish live account migration. **Fix:** say “the configuration declares `bobby`” and explain that SSH/deployment and remote-builder identities follow their respective metadata.

4. **Medium | [CLAUDE.md:127](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:127): Cleanup scope and guard are omitted.**  
   `simple.go:72` defaults to five generations and refuses while `$XDG_STATE_HOME/home-manager/keep-gen19` exists, falling back to `~/.local/state`. `nh clean user --help` includes user profiles, gcroots, direnv roots, and store GC. Automatic cleaning is disabled in `home-manager/modules/nh.nix:19`. **Fix:** document these facts and the rollback procedure before removing protection.

5. **Medium | [CLAUDE.md:108](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:108): Worktree selection and a nonmutating preview are missing.**  
   `nh.nix:18` hardcodes the main checkout; hm uses `NH_FLAKE`, not the current directory (`cli.go:124`). **Fix:** document `hm --flake "$PWD" ...` for alternate checkouts, global `--dry-run`, and nh’s explicit installable argument. Clarify that `--build-only` still edits tracked lists/locks.

6. **Medium | [CLAUDE.md:120](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:120): Update scope and activation boundaries need clarification.**  
   `up.go:79` excludes module-managed pins such as `nh`, `git`, and Go unless explicitly named with `--repo`; `--repo` without an attribute still selects only `packages.nix`. It switches only Home Manager, only when pins move. **Fix:** document these rules and separate nix-darwin/host activation. Hosts use integrated Home Manager (`flake.nix:174`); only the Mac has a standalone home output.

7. **Medium | [CLAUDE.md:119](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:119): Removal does not always switch.**  
   `rm.go:114` directly uninstalls Go/uv/cargo tools; Homebrew removal switches Darwin but leaves software installed (`homebrew.go:135`). `--prune` refuses the whole operation when consumers remain. Tool removal with `--build-only` prints an uninstall instruction, contradicting line 131’s “hm sync command.” **Fix:** document each removal branch and correct the preview description.

8. **Medium | [CLAUDE.md:123](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:123): `hm list` is not an exhaustive installed-package inventory.**  
   `homebrew.go:371` iterates declared Homebrew entries, includes missing ones as “not installed,” and omits undeclared installations. **Fix:** describe this limitation and direct users to `hm brew cleanup` for Homebrew extras. Mention `--generation PATH` for inspecting a built home generation.

9. **Medium | [CLAUDE.md:230](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:230): Signing configuration is presented as working key delivery.**  
   Git requests signing, but no Nix module declares `sops.secrets.gpg_signing_subkey`. `gpg.nix:53` merely skips import when the runtime file is absent. **Fix:** distinguish configured signing from provisioned keys, and state that secret declaration/provisioning is required before host signing works.

10. **Medium | [CLAUDE.md:142](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:142): Manual trust is incorrectly made a prerequisite for switching.**  
    Locked nix-darwin’s `modules/homebrew.nix:290` explicitly applies `trusted = true` during activation. hm’s diagnostic (`homebrew.go:311`) concerns cleanup before activation. **Fix:** require `brew trust TAP` only when a pre-activation cleanup preview reports untrusted taps.

11. **Medium | [README.md:26](/Users/bobby/github/catgrep/nixos-config/README.md:26): The gateway service list overstates available routes.**  
    `modules/gateway/Caddyfile` has no AdGuard route; Home Assistant uses `hass`, and Tailscale Prometheus uses `prom` (lines 172, 202). **Fix:** provide actual URLs and distinguish direct AdGuard access from gateway routes.

12. **Low | [CLAUDE.md:183](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:183): Same-version additions are allowed.**  
    `add.go:73` refuses an explicit version only when it differs from the existing pin. The manual shares this overstatement. **Fix:** say “refuses a different version for an already pinned attribute.”

13. **Low | [CLAUDE.md:136](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:136): Several listed paths are incomplete.**  
    `context.go:25` locates all three tool lists under `home-manager/`; `brews.nix` is under `darwin/homebrew/`. **Fix:** write all six repository-relative paths explicitly.

14. **Low | [README.md:64](/Users/bobby/github/catgrep/nixos-config/README.md:64): Lock-editing guidance contradicts the documented helper.**  
    “Only … through `mvs lock`” excludes hm, which line 76 recommends and `CLAUDE.md:174` permits. **Fix:** say “through `mvs lock` commands or `hm`.”

15. **Low | [CLAUDE.md:202](/Users/bobby/github/catgrep/nixos-config/CLAUDE.md:202): Golden-test coverage is overstated.**  
    Nix lists have golden fixtures; transaction JSON has behavioral tests in `txn_test.go`, not golden files. **Fix:** narrow the claim to owned Nix-list formats.

16. **Low | [README.md:13](/Users/bobby/github/catgrep/nixos-config/README.md:13), [README.md:42](/Users/bobby/github/catgrep/nixos-config/README.md:42): Historical narration remains.**  
    “This was my first experience…” and “the flake was bootstrapped with…” narrate history; “will eventually be migrated” describes an unimplemented future. **Fix:** remove these passages and the historical `fh init` command, retaining present setup instructions. No numbered planning-phase references appear in either document.