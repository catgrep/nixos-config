# SPDX-License-Identifier: GPL-3.0-or-later

# ROCm-enabled onnxruntime for Frigate object detection on AMD GPUs
#
# nixos-25.05's onnxruntime (1.22.0) lacks rocmSupport, so we pull
# onnxruntime AND frigate from nixpkgs-unstable to keep the entire
# dependency tree consistent (protobuf, abseil-cpp, tensorflow, etc.).
#
# The frigate package is patched to make TFLite imports non-fatal,
# allowing tensorflow to be removed from PYTHONPATH at runtime.
# This prevents a protobuf symbol collision: tensorflow statically
# links protobuf into libtensorflow_framework.so.2, which conflicts
# with onnxruntime's dynamically-linked libprotobuf.so in forked
# detector subprocesses.
#
# Usage: import ./overlays/frigate-rocm.nix nixpkgs-unstable-input
nixpkgs-unstable: final: prev:
let
  unstable = import nixpkgs-unstable {
    inherit (prev) system;
    config.allowUnfree = true;
  };
in
{
  onnxruntime = unstable.onnxruntime.override {
    rocmSupport = true;
  };

  # Use frigate from unstable for consistent deps with ROCm onnxruntime.
  # Skip installCheck: ROCm onnxruntime segfaults in the build sandbox
  # (no GPU/HSA runtime). Runtime works fine with actual hardware.
  frigate = unstable.frigate.overrideAttrs (prev: {
    doInstallCheck = false;

    # Make TFLite imports non-fatal so tensorflow can be removed from
    # PYTHONPATH (prevents protobuf symbol collision with onnxruntime).
    # Each file tries tflite_runtime first, then tensorflow.lite; we
    # add a third fallback that sets Interpreter = None.
    # Uses sed because substituteInPlace mangles multi-line indentation
    # inside Nix's '' ... '' strings.
    postPatch =
      (prev.postPatch or "")
      + ''
        for f in \
          frigate/data_processing/real_time/bird.py \
          frigate/embeddings/onnx/face_embedding.py \
          frigate/events/audio.py \
          frigate/detectors/plugins/cpu_tfl.py; do
          sed -i 's|    from tensorflow\.lite\.python\.interpreter import Interpreter|    try:\n        from tensorflow.lite.python.interpreter import Interpreter\n    except ModuleNotFoundError:\n        Interpreter = None|' "$f"
        done

        sed -i 's|    from tensorflow\.lite\.python\.interpreter import Interpreter, load_delegate|    try:\n        from tensorflow.lite.python.interpreter import Interpreter, load_delegate\n    except ModuleNotFoundError:\n        Interpreter = None; load_delegate = None|' \
          frigate/detectors/plugins/edgetpu_tfl.py
      '';
  });
}
