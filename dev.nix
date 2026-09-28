# SPDX-License-Identifier: GPL-3.0-or-later

# Development shells - platform agnostic
{
  pkgs,
  pinned,
  system,
  sagent,
  sagentFor,
  mvs,
}:

pkgs.mkShell {
  packages =
    with pinned;
    [
      nixfmt
      nixos-rebuild
      git
      jq
      yq-go
      sops
      age
      ssh-to-age
      openssl
      sshpass
      mkpasswd
      inetutils
      shellcheck
      shfmt
      nixos-anywhere
      mkcert
      addlicense
      dhcping
      caddy
      python3
      statix
      nurl
      prek
      wireguard-tools
      # ast-bro and treehouse (with the ast-bro source override)
      # are owned and exported by the sagent subflake.
      sagent.packages.${system}.ast-bro
      sagent.packages.${system}.treehouse
      # nixpkgs version-history queries and pinning (nixmultiverse.com)
      mvs.packages.${system}.mvs
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      (sagentFor system)
    ];
}
