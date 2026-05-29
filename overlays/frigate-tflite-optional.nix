# SPDX-License-Identifier: GPL-3.0-or-later

# Frigate imports several TFLite-backed modules during startup even when the
# active detector is ONNX. The ser8 service deliberately removes tensorflow from
# PYTHONPATH to avoid protobuf symbol collisions with onnxruntime, so these
# imports must remain optional.
final: prev: {
  frigate = prev.frigate.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      for f in \
        frigate/data_processing/real_time/bird.py \
        frigate/embeddings/onnx/face_embedding.py \
        frigate/events/audio.py \
        frigate/detectors/plugins/cpu_tfl.py; do
        grep -q '    from tensorflow\.lite\.python\.interpreter import Interpreter' "$f" \
          || { echo "Frigate TFLite import pattern changed in $f" >&2; exit 1; }
        sed -i 's|    from tensorflow\.lite\.python\.interpreter import Interpreter|    try:\n        from tensorflow.lite.python.interpreter import Interpreter\n    except ModuleNotFoundError:\n        Interpreter = None|' "$f"
      done

      f=frigate/detectors/plugins/edgetpu_tfl.py
      grep -q '    from tensorflow\.lite\.python\.interpreter import Interpreter, load_delegate' "$f" \
        || { echo "Frigate EdgeTPU import pattern changed in $f" >&2; exit 1; }
      sed -i 's|    from tensorflow\.lite\.python\.interpreter import Interpreter, load_delegate|    try:\n        from tensorflow.lite.python.interpreter import Interpreter, load_delegate\n    except ModuleNotFoundError:\n        Interpreter = None; load_delegate = None|' "$f"
    '';
  });
}
