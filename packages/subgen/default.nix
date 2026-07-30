# SPDX-License-Identifier: GPL-3.0-or-later

{
  lib,
  fetchFromGitHub,
  ffmpeg,
  makeWrapper,
  python312Packages,
  stable-ts-whisperless,
}:

let
  pythonDependencies = with python312Packages; [
    av
    faster-whisper
    fastapi
    ffmpeg-python
    numpy
    python-multipart
    requests
    stable-ts-whisperless
    torch
    uvicorn
    watchdog
  ];
  pythonEnvironment = python312Packages.python.withPackages (_: pythonDependencies);
in
python312Packages.buildPythonApplication {
  pname = "subgen";
  version = "2026.07.3";
  format = "other";

  src = fetchFromGitHub {
    owner = "McCloudS";
    repo = "subgen";
    rev = "f38dcaa8cd287556faaa2f7ea45e708096f19e67";
    hash = "sha256-4ZhwuARN4WbRcIyZ0K98gmnoHcSvKKPmAlKySQI2x5s=";
  };

  dontBuild = true;
  dontWrapPythonPrograms = true;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ pythonEnvironment ];
  dependencies = pythonDependencies;

  postPatch = ''
    substituteInPlace subgen.py \
      --replace-fail \
        'host="0.0.0.0"' \
        'host=os.getenv("WEBHOOK_HOST", "127.0.0.1")'
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 subgen.py language_code.py -t "$out/libexec/subgen"
    makeWrapper ${pythonEnvironment}/bin/python "$out/bin/subgen" \
      --add-flags "-u $out/libexec/subgen/subgen.py" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}

    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    ${pythonEnvironment}/bin/python -m py_compile subgen.py language_code.py
    ${pythonEnvironment}/bin/python - <<'PY'
    import av
    import faster_whisper
    import fastapi
    import ffmpeg
    import multipart
    import numpy
    import requests
    import stable_whisper
    import torch
    import uvicorn
    import watchdog
    PY

    runHook postCheck
  '';

  meta = {
    description = "Automatic subtitle generation backend for Bazarr";
    homepage = "https://github.com/McCloudS/subgen";
    license = lib.licenses.mit;
    mainProgram = "subgen";
    platforms = lib.platforms.linux;
  };
}
