# Local Pose Runtime (macOS)

This project runs pose input locally:

- Webcam + OpenCV in Python
- MediaPipe face tracking for head movement
- UDP packets to Godot (`127.0.0.1:42424`)

## 1) Python setup

From project root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install opencv-python mediapipe
```

## 2) Model file

Expected path:

- `face_landmarker_v2_with_blendshapes.task` in project root

If missing, download:

```bash
curl -L "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task" -o "face_landmarker_v2_with_blendshapes.task"
```

## 3) Runtime environment knobs

Optional env vars before launching Godot:

- `POSE_UDP_HOST` (default `127.0.0.1`)
- `POSE_UDP_PORT` (default `42424`)
- `POSE_PREVIEW_UDP_PORT` (default `42425`, set `0` to disable JPEG preview)
- `POSE_PREVIEW_EVERY_N` (default `1` — send 1 preview JPEG every N processed frames; use `2` to save CPU/bandwidth)
- `POSE_PREVIEW_MAX_W` (default `280` — intermediate downscale before fixed output size)
- `POSE_PREVIEW_OUT_W` / `POSE_PREVIEW_OUT_H` (default `320`×`180` — **fixed** JPEG size sent to Godot; keeps UI stable)
- `POSE_CAMERA_INDEX` (default `0`)
- `POSE_FPS_TARGET` (default `30`)
- `POSE_LEAN_FULL_SCALE` (default `0.18`)
- `POSE_LEAN_DEADZONE` (default `0.030`)
- `POSE_JUMP_VELOCITY_THRESHOLD` (default `-0.060`)
- `POSE_JUMP_COOLDOWN_S` (default `0.62`)

## 4) Quick verification (under 1 minute)

1. Start the game scene.
2. Look at right panel text:
   - `runtime ON` means python process launched.
   - `pkts` should keep increasing.
   - `age` should stay low (usually <200ms).
3. Move left/right:
   - `lean` should change.
4. Jump once:
   - Intro: starts game.
   - In run: fires laser.

## 5) Common macOS issues

- **No webcam frames / no tracking**
  - The runtime uses **AVFoundation** (`CAP_AVFOUNDATION`) and tries camera indices `0–3` automatically.
  - If you use Continuity Camera or virtual cameras, set `POSE_CAMERA_INDEX=1` (or `2`) in the environment.
  - **BGR vs RGB:** frames are converted to RGB before MediaPipe; if you fork the script, keep that conversion.
  - Check camera permissions for **Godot** and **Python** in macOS **System Settings → Privacy & Security → Camera**.
  - Ensure no other app is locking the camera.
- **Preview panel stays black but pose text updates**
  - Confirm `PoseInputBridge` has `enable_camera_preview` on and port `42425` is not blocked.
  - Set `POSE_PREVIEW_UDP_PORT=0` in the environment if you only want control packets (no video).

- **`runtime ON` but `udp_rx 0` / `json_ok 0` (no packets in Godot)**
  - Godot launched from **Finder** often has an empty `PATH`, so `python3` was never found or the wrong binary ran and exited immediately.
  - The bridge now uses **`/bin/sh -c`** with `cd` to the project and prefers **`/opt/homebrew/bin/python3`** (then `/usr/local`, then `/usr/bin`).
  - The bridge auto-prefers **`$HOME/.pyenv/shims/python3`** when that file exists (same as your `which python3` when using pyenv).
  - Or set **Inspector → PoseInputBridge → Python Executable** to that full path, or set env **`POSE_PYTHON`** to it before starting Godot.
  - Open **`pose/pose_runtime_stderr.log`** and **`pose/pose_runtime_boot.log`** in the project folder for the real error (missing `mediapipe`, missing model file, camera permission, etc.).
  - UDP bind defaults to **`0.0.0.0`** so loopback delivery is reliable on macOS.
- **Runtime launches but no packets**
  - Verify python path in `PoseInputBridge` (`python3` by default).
  - Confirm UDP port (`42424`) is not in use.
- **Tracking too jittery**
  - Increase `POSE_LEAN_DEADZONE`.
  - Lower `POSE_FPS_TARGET` to 24-30 for steadier thermal behavior.
- **Jump triggers too often**
  - Increase `POSE_JUMP_COOLDOWN_S` and/or make threshold more negative.
