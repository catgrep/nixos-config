# SPDX-License-Identifier: GPL-3.0-or-later
#
# Donetick's UI lives in a separate repository (donetick/frontend), not in
# donetick/donetick alongside the Go backend. donetick.com/core's own
# frontend/dist is committed only as an 88-byte placeholder
# ("This file will be replaced by the frontend build process") -- the real
# UI is built by upstream's release workflow (.github/workflows/go-release.yml
# in donetick/donetick) by checking out donetick/frontend's default branch,
# running `npm run build-selfhosted`, and copying the result into
# ./frontend/dist before the Go build embeds it via //go:embed dist.
#
# This derivation reproduces that step: `rev` below is the commit that was
# HEAD of donetick/frontend's `develop` branch at the moment the real
# v0.1.79 release workflow ran (traced via the GitHub API: the only commit
# on `develop` between the prior commit at 2026-08-18T12:50:46Z and the next
# one at 2026-08-18T19:18:43Z, bracketing the release workflow's run start
# at 2026-08-18T13:25:52Z).
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage {
  pname = "donetick-frontend";
  version = "1.2.49"; # frontend package.json version at the pinned commit

  src = fetchFromGitHub {
    owner = "donetick";
    repo = "frontend";
    rev = "b3b3a0e5a8f4cb1b150f1d5472cda30d526bb976";
    hash = "sha256-9u+mw9ShklBLgjkr1oP5de5yMuFYoqTRVfSsYgBcqQU=";
  };

  # Upstream's committed package-lock.json is missing "resolved"/"integrity"
  # for 909 of 1382 packages (npm/cli#6301) -- a real upstream bug, not a Nix
  # quirk: `npm install --package-lock-only` against the unmodified lockfile
  # leaves those entries untouched, and upstream's own release workflow never
  # actually installs from the committed lockfile at all -- it deletes it and
  # runs a fresh `npm install` every time (see build-selfhosted in
  # package.json). This vendored lockfile is the output of that same
  # `rm -rf package-lock.json && npm install` against the pinned commit's
  # unchanged package.json, so it resolves identical version ranges (spot
  # checked: react/react-dom/@vitejs/plugin-react-swc unchanged; vite drifted
  # 5.4.19 -> 5.4.21, an in-range patch release) but with every entry fully
  # resolved and content-addressed, which a sandboxed Nix build requires.
  postPatch = ''
    cp ${./frontend-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-beKPy0736afXRf4SFqCe1x7UzoracU2+QJwJIV3dOg4=";

  # `sharp` (a transitive dependency of the unused @capacitor/assets tooling,
  # not a direct dependency and not needed by `vite build`) has a postinstall
  # step that tries to download/compile libvips over the network, which fails
  # in Nix's sandboxed build. vite/esbuild/@swc/core/rollup all ship their
  # platform-specific native binaries as plain optionalDependencies (resolved
  # directly from the now-complete lockfile), not via postinstall scripts, so
  # skipping all lifecycle scripts is safe for what `vite build` actually needs.
  npmFlags = [ "--ignore-scripts" ];

  # Upstream's own `build-selfhosted` script (`rm -rf package-lock.json &&
  # npm install && npm install --force @rollup/rollup-linux-x64-gnu@... &&
  # vite build --mode selfhosted`) exists to work around npm's optional-
  # dependency resolution flakiness in third-party CI runners. A Nix build
  # targets exactly one deterministic platform via the prefetched
  # package-lock.json-derived npmDeps, so that workaround is unnecessary
  # and would also require network access this sandboxed build doesn't have.
  buildPhase = ''
    runHook preBuild
    npx vite build --mode selfhosted
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r dist "$out/dist"
    runHook postInstall
  '';

  meta = {
    description = "Donetick web UI (Vite/React), built for self-hosted deployments";
    homepage = "https://github.com/donetick/frontend";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
  };
}
