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

Add `/etc/nix/nix.custom.conf` and:
1) add builder machines to `/etc/nix/machines`
2) add any `extra-substituters`

See `./etc/nix` for examples.

After updating config files, restart the nix daemon with:
```
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

# Accessing Media Drive over SMB

## MacOS

Go to `Finder` > `Go` > `Connect to Server` (or `Command + K`)

Type in:
```
smb://media@beelink-homelab.local
```

And login as the `media` user.


# Testing DHCP + DNS AdGuard

```
Client → DHCP Request → AdGuard
AdGuard → "Here's IP 192.168.68.100, use 192.168.68.96 for DNS" → Client
Client → DNS Query → AdGuard (192.168.68.96)
AdGuard → DNS Response → Client
```

Verify after configuring your router:
```
ipconfig getpacket en0 | grep domain_name_server
```

You may need to clear out DNS entries:
```
# Check if you have manual DNS servers
networksetup -getdnsservers Wi-Fi

# If it shows anything other than "There aren't any DNS Servers set":
sudo networksetup -setdnsservers Wi-Fi empty
```
