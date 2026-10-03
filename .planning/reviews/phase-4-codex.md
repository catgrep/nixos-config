1. **P2 · [scripts/smoketests/pi/test-builder.sh:54](/Users/bobby/github/catgrep/nixos-config/scripts/smoketests/pi/test-builder.sh:54) · Builder probe can stall the smoketest suite.**  
   The `nix store info` invocation bypasses `remote()`, so it receives neither `BatchMode=yes` nor `ConnectTimeout=10`. Because the suite continues after failed login checks, this probe can subsequently wait for an SSH prompt or an extended connection timeout instead of reporting failure. Nix’s SSH implementation accepts these settings through `NIX_SSHOPTS` but does not supply them automatically. [Source](https://raw.githubusercontent.com/NixOS/nix/2.34.8/src/libstore/ssh.cc)  
   **Concrete fix:** pass `NIX_SSHOPTS="-oBatchMode=yes -oConnectTimeout=10 ${NIX_SSHOPTS:-}"` to this invocation. Add an overall command timeout if the probe must also terminate when the remote protocol stalls.

No additional findings in the requested scope.

Validation completed:

- Evaluated relevant options and Home Manager activation derivations for **ser8, firebat, pi4, and pi5**.
- Confirmed `bobby`, UID 1000, preserved groups, `/home/bobby`, passwordless sudo, and `/home/bobby/.config/zsh`.
- Verified option definitions against locked Home Manager **09ae1b85** and the hosts’ actual nixpkgs **0dd31db7** in the Nix store.
- Confirmed ser8’s evaluated Samba share and password-sync script reference `bobby`.
- New Pi scripts pass `shellcheck -x` and `shfmt -d`.

The deliberately deferred secret wiring and unchanged deployment usernames were excluded. No files were modified, no hosts were contacted, and no files under `secrets/` were read. Runtime activation, signing, and Samba authentication remain unverified.