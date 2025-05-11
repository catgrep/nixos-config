# nixos-config

## Home-Manager

Run
``` sh
nix run home-manager -- switch --flake ./home-manager
```

## Development

This repo uses Determinate System and the flake was bootstrapped with:
``` sh
nix run "https://flakehub.com/f/DeterminateSystems/fh/*" -- init
```

### Prerequisites

You will need:
1) `nix` package manager for installing `nix` packages.
2) `nixfmt` for formatting `nix` files.

Install nix:
``` sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Test with:
``` sh
echo "Hello Nix" | nix run "https://flakehub.com/f/NixOS/nixpkgs/*#charasay" say
```

Install `nixfmt`:

``` sh
nix-env -i -f https://github.com/NixOS/nixfmt/archive/master.tar.gz
```


## ZFS RAID 10