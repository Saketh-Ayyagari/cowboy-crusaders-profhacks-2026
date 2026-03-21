#!/usr/bin/env python3
"""
Pose runtime for Space Yeehaw.

Reads webcam frames, runs MediaPipe Face Landmarker, and sends a compact control
packet to Godot via localhost UDP as newline-free JSON.
"""

from __future__ import annotations

import json
import math
import os
import platform
import signal
import socket
import sys
import time
from dataclasses import dataclass
from typing import Optional


def _project_root_dir() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _boot_append(message: str) -> None:
    log_path = os.path.join(_project_root_dir(), "pose", "pose_runtime_boot.log")
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(message.rstrip() + "\n")
    except OSError:
        pass


try:
    import cv2 as cv
except Exception as exc:  # pragma: no cover
    _boot_append(f"[fatal] opencv import failed: {exc!r}")
    print(f"[pose_runtime] opencv import failed: {exc}", file=sys.stderr, flush=True)
    sys.exit(2)

try:
    import mediapipe as mp
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision
except Exception as exc:  # pragma: no cover
    _boot_append(f"[fatal] mediapipe import failed: {exc!r}")
    print(f"[pose_runtime] mediapipe import failed: {exc}", file=sys.stderr, flush=True)
    sys.exit(2)


FOREHEAD_LANDMARK_INDEX = 10


@dataclass
class RuntimeConfig:
    udp_host: str = os.getenv("POSE_UDP_HOST", "127.0.0.1")
    udp_port: int = int(os.getenv("POSE_UDP_PORT", "42424"))
    camera_index: int = int(os.getenv("POSE_CAMERA_INDEX", "0"))
    # Normalized horizontal displacement where lean reaches full scale.
    lean_full_scale: float = float(os.getenv("POSE_LEAN_FULL_SCALE", "0.18"))
    lean_deadzone: float = float(os.getenv("POSE_LEAN_DEADZONE", "0.030"))
    smooth_alpha: float = float(os.getenv("POSE_SMOOTH_ALPHA", "0.28"))
    jump_velocity_threshold: float = float(os.getenv("POSE_JUMP_VELOCITY_THRESHOLD", "-0.060"))
    jump_cooldown_s: float = float(os.getenv("POSE_JUMP_COOLDOWN_S", "0.62"))
    anchor_hold_frames: int = int(os.getenv("POSE_ANCHOR_HOLD_FRAMES", "8"))
    fps_target: float = float(os.getenv("POSE_FPS_TARGET", "30.0"))
    heartbeat_interval_s: float = float(os.getenv("POSE_HEARTBEAT_S", "2.0"))
    model_path: str = os.getenv(
        "POSE_MODEL_PATH",
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "face_landmarker_v2_with_blendshapes.task"),
    )
    # Second UDP port for tiny JPEG preview frames (Godot TextureRect). 0 = disabled.
    preview_udp_port: int = int(os.getenv("POSE_PREVIEW_UDP_PORT", "42425"))
    # Send a preview JPEG every N processed frames (1 = every frame, smoothest).
    preview_every_n_frames: int = max(1, int(os.getenv("POSE_PREVIEW_EVERY_N", "1")))
    preview_max_width: int = max(80, int(os.getenv("POSE_PREVIEW_MAX_W", "1280")))
    # Fixed JPEG dimensions so Godot TextureRect does not reflow every frame (reduces glitching).
    preview_out_w: int = max(64, int(os.getenv("POSE_PREVIEW_OUT_W", "1280")))
    preview_out_h: int = max(48, int(os.getenv("POSE_PREVIEW_OUT_H", "720")))
    # Requested webcam capture resolution (actual delivered size depends on camera/driver support).
    camera_out_w: int = max(64, int(os.getenv("POSE_CAMERA_OUT_W", "1280")))
    camera_out_h: int = max(48, int(os.getenv("POSE_CAMERA_OUT_H", "720")))


def open_cv_camera(preferred_index: int) -> tuple[cv.VideoCapture, int]:
    """
    Open a working webcam. On macOS, default backend often fails; AVFoundation is reliable.
    Tries several indices so Continuity Camera / virtual cams don't steal index 0.
    """
    system = platform.system().lower()
    indices_to_try: list[int] = []
    if preferred_index >= 0:
        indices_to_try.append(preferred_index)
    for i in range(4):
        if i not in indices_to_try:
            indices_to_try.append(i)

    backends: list[Optional[int]] = [None]
    if system == "darwin":
        # CAP_AVFOUNDATION is the stable backend for MacBook / macOS cameras.
        backends.insert(0, cv.CAP_AVFOUNDATION)

    for index in indices_to_try:
        for backend in backends:
            cap = cv.VideoCapture(index) if backend is None else cv.VideoCapture(index, backend)
            if not cap.isOpened():
                cap.release()
                continue
            ok, _ = cap.read()
            if ok:
                print(
                    f"[pose_runtime] camera opened: index={index} backend={backend}",
                    file=sys.stderr,
                    flush=True,
                )
                return cap, index
            cap.release()

    print("[pose_runtime] camera: all open attempts failed", file=sys.stderr, flush=True)
    fallback = (
        cv.VideoCapture(preferred_index, cv.CAP_AVFOUNDATION)
        if system == "darwin"
        else cv.VideoCapture(preferred_index)
    )
    return fallback, preferred_index


class PoseRuntime:
    def __init__(self, cfg: RuntimeConfig) -> None:
        self.cfg = cfg
        # Ensure cwd is project root so model path and assets resolve when launched from Godot.
        try:
            os.chdir(_project_root_dir())
        except OSError:
            pass

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.preview_sock: Optional[socket.socket] = None
        if self.cfg.preview_udp_port > 0:
            self.preview_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        self.camera, self._camera_index_used = open_cv_camera(self.cfg.camera_index)
        self._apply_capture_resolution()
        self.detector = self._build_detector(self.cfg.model_path)
        self.face_mesh = self._build_face_mesh() if self.detector is None else None

        self.anchor_x: Optional[float] = None
        self._anchor_samples = 0
        self.smooth_lean_x = 0.0
        self.prev_head_y: Optional[float] = None
        self.last_jump_s = 0.0
        self.last_send_s = 0.0
        self.last_heartbeat_s = 0.0
        self.packet_count = 0
        self._preview_frame_counter = 0
        self._running = True

        signal.signal(signal.SIGINT, self._handle_stop_signal)
        signal.signal(signal.SIGTERM, self._handle_stop_signal)

        self._log_startup_state()

    def _handle_stop_signal(self, _signum, _frame) -> None:
        self._running = False

    def _log(self, msg: str) -> None:
        print(f"[pose_runtime] {msg}", file=sys.stderr, flush=True)

    def _log_startup_state(self) -> None:
        detector_state = "tasks-face-landmarker" if self.detector is not None else ("face-mesh-fallback" if self.face_mesh is not None else "none")
        self._log(
            "startup: camera_open=%s cam_index=%d detector=%s model_path=%s udp=%s:%d preview_port=%s fps_target=%.1f"
            % (
                str(self.camera.isOpened()).lower(),
                self._camera_index_used,
                detector_state,
                self.cfg.model_path,
                self.cfg.udp_host,
                self.cfg.udp_port,
                str(self.cfg.preview_udp_port) if self.cfg.preview_udp_port > 0 else "off",
                self.cfg.fps_target,
            )
        )

    def _apply_capture_resolution(self) -> None:
        if self.camera is None or not self.camera.isOpened():
            return
        try:
            self.camera.set(cv.CAP_PROP_FRAME_WIDTH, float(self.cfg.camera_out_w))
            self.camera.set(cv.CAP_PROP_FRAME_HEIGHT, float(self.cfg.camera_out_h))
        except Exception as exc:
            self._log(f"capture resolution request failed: {exc}")

    def _build_detector(self, model_path: str):
        if not os.path.exists(model_path):
            print(f"[pose_runtime] model file missing: {model_path}", file=sys.stderr, flush=True)
            return None
        try:
            base_options = python.BaseOptions(
                model_asset_path=model_path,
                delegate=python.BaseOptions.Delegate.CPU,
            )
            options = vision.FaceLandmarkerOptions(
                base_options=base_options,
                output_face_blendshapes=False,
                output_facial_transformation_matrixes=False,
                num_faces=1,
            )
            return vision.FaceLandmarker.create_from_options(options)
        except Exception as exc:
            print(f"[pose_runtime] detector setup failed: {exc}", file=sys.stderr, flush=True)
            return None

    def _emit(self, payload: dict) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.sock.sendto(data, (self.cfg.udp_host, self.cfg.udp_port))
        self.packet_count += 1

    def _send_preview_jpeg_from_rgb(self, rgb_frame) -> None:
        if self.preview_sock is None or self.cfg.preview_udp_port <= 0:
            return
        self._preview_frame_counter += 1
        if (self._preview_frame_counter % self.cfg.preview_every_n_frames) != 0:
            return
        try:
            # OpenCV JPEG encoder expects BGR; rgb_frame already matches what MediaPipe sees (no second flip).
            src = cv.cvtColor(rgb_frame, cv.COLOR_RGB2BGR)
            h, w = src.shape[:2]
            tw, th = self.cfg.preview_out_w, self.cfg.preview_out_h
            max_w = self.cfg.preview_max_width
            if w > max_w:
                scale = max_w / float(w)
                mid_w = max_w
                mid_h = max(1, int(h * scale))
                mid = cv.resize(src, (mid_w, mid_h), interpolation=cv.INTER_AREA)
            else:
                mid = src
            interp = cv.INTER_AREA if mid.shape[1] > tw or mid.shape[0] > th else cv.INTER_LINEAR
            small = cv.resize(mid, (tw, th), interpolation=interp)
            ok, buf = cv.imencode(".jpg", small, [int(cv.IMWRITE_JPEG_QUALITY), 48])
            if not ok or buf is None:
                return
            payload = buf.tobytes()
            if len(payload) > 60000:
                return
            self.preview_sock.sendto(payload, (self.cfg.udp_host, self.cfg.preview_udp_port))
        except Exception as exc:
            self._log(f"preview encode/send failed: {exc}")

    def _maybe_heartbeat(self, now_s: float) -> None:
        if (now_s - self.last_heartbeat_s) < self.cfg.heartbeat_interval_s:
            return
        self.last_heartbeat_s = now_s
        self._log("heartbeat: packets=%d tracking=%s lean=%.3f" % (self.packet_count, str(self.anchor_x is not None).lower(), self.smooth_lean_x))

    def _build_face_mesh(self):
        try:
            return mp.solutions.face_mesh.FaceMesh(
                static_image_mode=False,
                max_num_faces=1,
                refine_landmarks=False,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            )
        except Exception as exc:
            print(f"[pose_runtime] face mesh fallback setup failed: {exc}", file=sys.stderr, flush=True)
            return None

    def _calc_lean(self, head_x: float) -> float:
        if self.anchor_x is None:
            self.anchor_x = head_x
            self._anchor_samples = 1
            return 0.0

        # Keep a stable anchor for the first short window before gameplay.
        if self._anchor_samples < self.cfg.anchor_hold_frames:
            self.anchor_x = (self.anchor_x * float(self._anchor_samples) + head_x) / float(self._anchor_samples + 1)
            self._anchor_samples += 1

        dx = head_x - self.anchor_x
        if abs(dx) <= self.cfg.lean_deadzone:
            raw = 0.0
        else:
            signed = math.copysign(1.0, dx)
            raw = signed * min(1.0, max(0.0, (abs(dx) - self.cfg.lean_deadzone) / self.cfg.lean_full_scale))

        self.smooth_lean_x = self.smooth_lean_x + self.cfg.smooth_alpha * (raw - self.smooth_lean_x)
        return max(-1.0, min(1.0, self.smooth_lean_x))

    def _detect_jump(self, head_y: float, now_s: float) -> bool:
        if self.prev_head_y is None:
            self.prev_head_y = head_y
            return False

        vy = head_y - self.prev_head_y
        self.prev_head_y = head_y
        if vy < self.cfg.jump_velocity_threshold and (now_s - self.last_jump_s) >= self.cfg.jump_cooldown_s:
            self.last_jump_s = now_s
            return True
        return False

    def _emit_no_tracking(self, now_s: float) -> None:
        payload = {
            "ts": now_s,
            "tracking_confidence": 0.0,
            "lean_x": 0.0,
            "is_centered": True,
            "jump_triggered": False,
        }
        if self.anchor_x is not None:
            payload["head_anchor_x"] = self.anchor_x
        self._emit(payload)

    def run(self) -> None:
        frame_dt = 1.0 / max(1.0, self.cfg.fps_target)
        if not self.camera.isOpened() or (self.detector is None and self.face_mesh is None):
            self._log("degraded mode: camera or detector unavailable; emitting neutral packets")
            while self._running:
                now_s = time.time()
                self._emit_no_tracking(now_s)
                self._maybe_heartbeat(now_s)
                time.sleep(max(0.01, frame_dt))
            self._cleanup()
            return

        while self._running:
            loop_start_s = time.time()
            ok, frame = self.camera.read()
            now_s = loop_start_s
            if not ok:
                self._emit_no_tracking(now_s)
                self._maybe_heartbeat(now_s)
                time.sleep(max(0.01, frame_dt))
                continue

            # One shared RGB frame for detection + preview.
            rgb = cv.cvtColor(frame, cv.COLOR_BGR2RGB)
            self._send_preview_jpeg_from_rgb(rgb)

            head_x: Optional[float] = None
            head_y: Optional[float] = None
            if self.detector is not None:
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                result = self.detector.detect(image)
                if result.face_landmarks:
                    landmarks = result.face_landmarks[0]
                    forehead = landmarks[FOREHEAD_LANDMARK_INDEX]
                    head_x = float(forehead.x)
                    head_y = float(forehead.y)
            elif self.face_mesh is not None:
                result = self.face_mesh.process(rgb)
                if result.multi_face_landmarks:
                    forehead = result.multi_face_landmarks[0].landmark[FOREHEAD_LANDMARK_INDEX]
                    head_x = float(forehead.x)
                    head_y = float(forehead.y)

            if head_x is None or head_y is None:
                self._emit_no_tracking(now_s)
                self._maybe_heartbeat(now_s)
                elapsed_s = time.time() - loop_start_s
                if elapsed_s < frame_dt:
                    time.sleep(frame_dt - elapsed_s)
                continue

            lean_x = self._calc_lean(head_x)
            is_centered = abs(lean_x) < 0.08
            jump = self._detect_jump(head_y, now_s)

            payload = {
                "ts": now_s,
                "tracking_confidence": 1.0,
                "lean_x": lean_x,
                "is_centered": is_centered,
                "jump_triggered": jump,
                "head_x": head_x,
                "head_y": head_y,
            }
            if self.anchor_x is not None:
                payload["head_anchor_x"] = self.anchor_x
            self._emit(payload)
            self._maybe_heartbeat(now_s)
            self.last_send_s = now_s
            elapsed_s = time.time() - loop_start_s
            if elapsed_s < frame_dt:
                time.sleep(frame_dt - elapsed_s)

        self._cleanup()

    def _cleanup(self) -> None:
        if self.camera is not None:
            self.camera.release()
        if self.face_mesh is not None:
            self.face_mesh.close()
        self.sock.close()
        if self.preview_sock is not None:
            self.preview_sock.close()
        self._log("shutdown complete")


def _fatal_boot_log(exc: BaseException) -> None:
    log_path = os.path.join(_project_root_dir(), "pose", "pose_runtime_boot.log")
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(f"[fatal] {time.time():.3f} {type(exc).__name__}: {exc}\n")
    except OSError:
        pass


def main() -> int:
    try:
        cfg = RuntimeConfig()
        runtime = PoseRuntime(cfg)
        runtime.run()
        return 0
    except Exception as exc:
        _fatal_boot_log(exc)
        raise


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as exc:
        _fatal_boot_log(exc)
        print(f"[pose_runtime] fatal: {exc}", file=sys.stderr, flush=True)
        raise SystemExit(1) from exc
