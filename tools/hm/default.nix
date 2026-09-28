# SPDX-License-Identifier: GPL-3.0-or-later

# hm adds, removes and updates the packages of the Home Manager
# configuration. It uses the Go standard library only, so there is nothing
# to vendor and vendorHash stays null. The man page and the completion
# scripts are rendered from the same source as --help: the page in
# postBuild, the scripts by the built binary in postInstall. nh and git are
# on the wrapper's PATH; nix and mvs are resolved from the caller's PATH.
# The check phase runs go test and then staticcheck from the go-tools pin.
{
  lib,
  buildGoModule,
  makeWrapper,
  installShellFiles,
  nh,
  git,
  go-tools,
}:
let
  # An analyzer reads the export data of the compiler that built the code,
  # so staticcheck must be built with the same Go as hm. The pinned
  # go-tools comes from nixpkgs' default Go; rebuilding it with the
  # buildGoModule hm uses keeps the two toolchains identical.
  staticcheck = go-tools.override { inherit buildGoModule; };
in
buildGoModule (finalAttrs: {
  pname = "hm";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  vendorHash = null;
  # gendoc is a build-time tool: run in postBuild, never installed. The
  # check phase still covers every other package with go test.
  excludedPackages = [ "internal/gendoc" ];
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];
  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];
  nativeCheckInputs = [
    git
    staticcheck
  ];
  # staticcheck caches under the user cache directory, which the sandbox
  # has no writable home for. It is silent on success, so the version line
  # is the log's evidence that it ran.
  postCheck = ''
    export STATICCHECK_CACHE="$TMPDIR/staticcheck-cache"
    staticcheck -version
    staticcheck ./...
  '';
  postBuild = ''
    go run ./internal/gendoc \
      -version ${finalAttrs.version} \
      -date "$(date -u -d "@''${SOURCE_DATE_EPOCH:-0}" +%F)" \
      -o hm.1
  '';
  postInstall = ''
    installManPage hm.1
    installShellCompletion --cmd hm \
      --zsh <($out/bin/hm completion zsh) \
      --fish <($out/bin/hm completion fish)
    installShellCompletion --bash --name hm <($out/bin/hm completion bash)
    wrapProgram $out/bin/hm --prefix PATH : ${
      lib.makeBinPath [
        nh
        git
      ]
    }
  '';
  meta = {
    description = "Add, remove and update Home Manager packages through multiverse.lock and nh";
    license = lib.licenses.gpl3Plus;
    mainProgram = "hm";
  };
})
