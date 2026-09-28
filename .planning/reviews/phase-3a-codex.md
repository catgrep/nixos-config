Reviewed `b041496..38e4b3d`, limited to phase 3 steps 1–2. Found eight issues, ranked below.

1. **P1: Rollback destroys concurrent edits.** [txn.go:293](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/txn/txn.go:293)  
   `Restore` overwrites captured files without checking their current contents against the last hash written by hm. This violates section 4’s compare-and-swap requirement. A temporary test overlay simulated an external edit during a failing switch; rollback deleted that edit.  
   **Fix:** Verify ownership before every restoration or deletion, preserve conflicting files, and leave an unresolved journal requiring reconciliation.

2. **P1: A failed switch can roll configuration back after activation changes.** [flow.go:221](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/flow.go:221)  
   Any nonzero `nh` exit returns immediately, without checking whether the active generation changed. Callers then restore the lists and lock. A simulated switch that changed `current-home` before failing reproduced this inconsistency. Section 4 explicitly forbids reverting files once the new generation becomes authoritative.  
   **Fix:** Check generation state after both successful and failed switch commands. Preserve configuration when activation occurred or its outcome is uncertain, and record that state explicitly.

3. **P1: Standalone switches bypass transaction exclusion.** [simple.go:16](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/simple.go:16), [sync.go:12](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/sync.go:12)  
   `switch` and standalone `sync` never acquire the transaction lock or check unresolved journals. An overlay test held a valid lock while invoking `switch`; the simulated switch succeeded instead of returning refusal code 3. This permits activation of another invocation’s intermediate configuration.  
   **Fix:** Apply the shared lock and unresolved-run guard to all machine-changing commands. Keep internal sync calls within their existing transaction to avoid nested locking.

4. **P2: Tool-add dry runs preview the old list.** [add.go:239](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/add.go:239)  
   During dry runs, `writeList` prints the proposed change, but `syncKind` rereads the unchanged file. Running `hm --dry-run add --go example.com/tool@v1.2.3` printed the addition followed by `0 current, 0 installed`, with no installation command. Updating an existing entry likewise previews its old version.  
   **Fix:** Pass the proposed in-memory list into reconciliation so dry-run installation commands correspond to the displayed diff.

5. **P2: Package provenance ignores store hashes.** [list.go:146](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/list.go:146)  
   Classification and deduplication use package name/version rather than store-path identity. Two builds with identical versions but different recipes or dependencies are treated as the same pinned package. An overlay test supplied different store hashes for installed and resolved `ripgrep-15.1.0`; `hm list` falsely reported it as pinned.  
   **Fix:** Match complete resolved output paths, including explicitly resolved additional outputs. Deduplicate by derivation/output identity rather than name/version.

6. **P2: Test fixtures prevent legitimate pin pruning.** [repo.go:131](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/sources/repo.go:131)  
   Consumer discovery scans every `.nix` file, including hm’s parser fixtures. On this repository, `hm --dry-run rm --prune zizmor` returned code 3 solely because six files under `tools/hm/internal/nixlist/testdata/` mention `zizmor`. Those files do not consume the pin.  
   **Fix:** Exclude fixture directories from consumer discovery while retaining checks of actual flake, development-shell, module, and host configuration.

7. **P2: The required staticcheck validation is not reproducible.** [default.nix:35](/Users/bobby/github/catgrep/nixos-config/tools/hm/default.nix:35)  
   Section 11 requires staticcheck from the `go-tools` pin. That pin is absent, and the package check supplies only Git beyond the standard Go check environment. The available staticcheck v0.6.0 cannot decode Go 1.27 export data, so this requirement could not be verified.  
   **Fix:** Pin a compatible `go-tools`, expose it to development checks, and run staticcheck in the hm check derivation.

8. **P3: Package-level mutable state violates the explicit Go rule.** [context.go:35](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/cli/context.go:35), [completion.go:16](/Users/bobby/github/catgrep/nixos-config/tools/hm/internal/completion/completion.go:16)  
   `ownedLists`, `toolKinds`, `outputSuffixes`, documentation flags, and exported `completion.Shells` are mutable package variables. Section 11 prohibits this; exported slices additionally allow callers to mutate shared backing storage.  
   **Fix:** Return fresh values from functions or construct these values within invocation state.

Validation: existing tests and `go vet` passed with pinned Go 1.27.1; `gofmt`, focused `nixfmt`/`statix`, and `checks.aarch64-darwin.hm` passed. Five temporary overlay probes reproduced findings 1–5 without editing repository sources. Exercised dry-run add, remove, update, switch, sync, try, clean, list, status, and doctor paths. Cargo/uv inventory reads encountered environment permission errors.

Verified `programs.go.env`, `programs.uv`, and `programs.nh` against locked Home Manager revision `09ae1b85`; configuration evaluation returned no module warnings. Inspected locked nix-darwin revision `4cff07de` in the Nix store; no nix-darwin options are introduced in this scope. No real generation was activated, and the repository remains unchanged.