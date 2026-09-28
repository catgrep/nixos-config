# SPDX-License-Identifier: GPL-3.0-or-later

# hm adds, removes and updates the packages of the Home Manager
# configuration. It uses the Go standard library only, so there is nothing
# to vendor and vendorHash stays null. The man page and the completion
# scripts are rendered from the same source as --help: the page in
# postBuild, the scripts by the built binary in postInstall. nh and git are
# on the wrapper's PATH; nix and mvs are resolved from the caller's PATH.
{
  lib,
  buildGoModule,
  makeWrapper,
  installShellFiles,
  nh,
  git,
}:
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
  nativeCheckInputs = [ git ];
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
