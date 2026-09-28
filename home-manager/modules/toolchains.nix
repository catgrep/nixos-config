# SPDX-License-Identifier: GPL-3.0-or-later

# Language toolchains from multiverse.lock, so every machine compiles with
# the same Go, Python and Node. GOPATH and GOBIN are written to Go's own
# env file, which `go env` reads, and ~/go/bin joins PATH here so tools
# installed with `go install` resolve everywhere.
{ config, pinned, ... }:
let
  home = config.home.homeDirectory;
in
{
  programs.go = {
    enable = true;
    package = pinned.go_1_27;
    env = {
      GOPATH = "${home}/go";
      GOBIN = "${home}/go/bin";
    };
  };

  programs.uv = {
    enable = true;
    package = pinned.uv;
  };

  home.sessionPath = [ "${home}/go/bin" ];

  home.packages = [
    pinned.python3
    pinned.nodejs_24
    pinned.pnpm
  ];
}
