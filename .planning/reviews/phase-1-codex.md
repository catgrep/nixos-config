Reviewed `373ed84..6bcc018` against phase 1. **Two completion gaps; no configuration-code defects found.** No repository files changed.

1. **Medium (P2): Generation 19 lacks the required independent rollback root.**  
   **Location:** [.planning/home-manager-migration-plan.md:742](/Users/bobby/github/catgrep/nixos-config/.planning/home-manager-migration-plan.md:742)  
   **What is wrong:** The migration’s designated rollback generation remains protected only by its ordinary generation link, which generation cleanup can remove.  
   **Evidence:** `~/.local/state/home-manager/keep-gen19` does not exist. Querying roots for `/nix/store/pa2s5qbgbncw97vky87nznmqgxqf3ik7-home-manager-generation` reports only `~/.local/state/nix/profiles/home-manager-19-link`.  
   **Concrete fix:** Run the phase’s prescribed command before further migration:
   ```sh
   nix build --out-link ~/.local/state/home-manager/keep-gen19 \
     /nix/store/pa2s5qbgbncw97vky87nznmqgxqf3ik7-home-manager-generation
   ```
   Verify the link resolves and retain it until the planned rollback exercise.

2. **Medium (P2): The new configuration has not been activated.**  
   **Location:** [home-manager/users/bobby.nix:14](/Users/bobby/github/catgrep/nixos-config/home-manager/users/bobby.nix:14), implementing [.planning/home-manager-migration-plan.md:747](/Users/bobby/github/catgrep/nixos-config/.planning/home-manager-migration-plan.md:747)  
   **What is wrong:** The committed state-version change builds successfully, but phase 1’s switch and runtime acceptance remain incomplete.  
   **Evidence:** Both the current profile and `gcroots/current-home` point to `k5pzyqy34j6r0jjc8fl3zkj6yrxxag35-home-manager-generation`, generation 20 from 01:16. The reviewed configuration builds `rwfi9fqylyii3j0zqxxlr2zhk95jjp02-home-manager-generation`. Its activation includes the newly enabled `copyApps` behavior absent from the current generation.  
   **Concrete fix:** After protecting generation 19, run:
   ```sh
   nh home switch . -c bobby@bob-mac -b bak
   ```
   Then verify the current generation resolves to the newly built output. Correct the plan’s command too: installed `nh` 4.4.2 accepts `-b` directly; arguments after `--` are passed to `nix build`, so `nh home switch -- -b bak` is incorrect. Generation 20 already belongs to the bootstrap; verify the output path rather than expecting that generation number.

All changed Home Manager options are valid against locked revision `09ae1b85a6db412d841d60f924b23f881f0d0a38`, including `home-manager.extraSpecialArgs` and both direnv package overrides. The locked [copyApps implementation](/nix/store/s14kfq13km82w650jynvl12is74m20ps-source/modules/targets/darwin/copyapps.nix:12) confirms the state-version-dependent default.

I also verified the corresponding [nix-darwin direnv options](/nix/store/8ggr67sci43hlp8ba6rhjrdhhj5490am-source/modules/programs/direnv.nix:20) at revision `4cff07de74b50e64bdd68cd4e722ab5b6b35ee48`, selected through locked omniflake. These commits introduce no nix-darwin configuration.

Validation passed: activation-package build, native-system flake check, focused formatting and statix checks, and diff whitespace checks. All 22 package-list entries are preserved; Home Manager reports no warnings or failed assertions. Nix emitted existing configuration warnings and unknown-output/platform notices. No activation was performed during this review.