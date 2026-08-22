# SPDX-License-Identifier: GPL-3.0-or-later
{
  lib,
  buildGoModule,
  callPackage,
  fetchFromGitHub,
}:

let
  frontend = callPackage ./frontend.nix { };
in
buildGoModule {
  pname = "donetick";
  version = "0.1.79";

  src = fetchFromGitHub {
    owner = "donetick";
    repo = "donetick";
    rev = "v0.1.79";
    hash = "sha256-I8jInhpcCtJfiIlLOktzznNRVJkz84nwFm72hQyrHUY=";
  };

  vendorHash = "sha256-abI5330bLKF+eBqgPcIadhOp5xDfqL+LmCb4oqn0qgw=";

  subPackages = [ "." ];

  # donetick.com/core's own frontend/dist is committed only as an 88-byte
  # placeholder; the real UI is built from the separate donetick/frontend
  # repo (see frontend.nix) and copied in here, matching what upstream's own
  # release workflow does before `go build` runs `//go:embed dist`.
  postPatch = ''
    rm -rf frontend/dist
    cp -r ${frontend}/dist frontend/dist
  '';

  # buildGoModule's default checkPhase scopes `go test` to `subPackages` when
  # that attribute is set (nixpkgs pkgs/build-support/go/module.nix's
  # getGoDirs), so leaving it at the default here would silently run `go
  # test ./.` against the root package only (which has no test files) and
  # skip all 14 real *_test.go files under internal/. Override checkPhase to
  # run the real, unscoped suite, matching upstream's own CI
  # (.github/workflows/go-build.yml: `go test ./...`) -- doCheck stays at
  # its buildGoModule default of true.
  checkPhase = ''
    runHook preCheck
    go test ./...
    runHook postCheck
  '';

  postInstall = ''
    if [ ! -f "$out/bin/donetick" ]; then
      bin=$(find "$out/bin" -maxdepth 1 -type f -executable | head -n1)
      mv "$bin" "$out/bin/donetick"
    fi
  '';

  meta = {
    description = "Self-hosted chore and task tracker for households";
    homepage = "https://donetick.com";
    license = lib.licenses.agpl3Only;
    mainProgram = "donetick";
    platforms = lib.platforms.linux;
  };
}
