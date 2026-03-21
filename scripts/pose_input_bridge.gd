extends Node
class_name PoseInputBridge

signal packet_updated(data: Dictionary)

@export var udp_port: int = 42424
@export var preview_udp_port: int = 42425
@export var enable_camera_preview: bool = true
## Bind on all interfaces so localhost UDP is reliably delivered (some macOS setups are picky with 127.0.0.1-only binds).
@export var udp_bind_host: String = "0.0.0.0"
@export var stale_timeout_sec: float = 0.35
@export var auto_launch_runtime: bool = true
## Use your Terminal `which python3` path here if auto-detect picks the wrong Python (e.g. Homebrew without mediapipe while pyenv has it).
@export var python_executable: String = "python3"
@export var runtime_script_path: String = "res://pose/pose_runtime.py"
## When true (default on macOS/Linux), runs: cd project && exec python -u script (fixes empty PATH when Godot is launched from Finder).
@export var use_shell_launch: bool = true

var lean_x: float = 0.0
var is_centered: bool = true
var jump_triggered: bool = false
var tracking_confidence: float = 0.0
var head_anchor_x: float = 0.5

var _udp: PacketPeerUDP
var _runtime_pid: int = -1
var _last_packet_ms: int = 0
var _jump_latch: bool = false
var _packet_count: int = 0
var _runtime_launch_ok: bool = false
var _preview_udp: PacketPeerUDP
var _preview_texture: ImageTexture
## Datagrams received on control port (includes bad JSON).
var _raw_datagram_count: int = 0
var _json_parse_fail_count: int = 0
var _python_used: String = ""
var _last_launch_shell_cmd: String = ""


func _ready() -> void:
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(udp_port, udp_bind_host)
	if err != OK:
		push_warning("PoseInputBridge: UDP bind failed on %s:%d" % [udp_bind_host, udp_port])
		return
	if enable_camera_preview and preview_udp_port > 0:
		_preview_udp = PacketPeerUDP.new()
		var perr := _preview_udp.bind(preview_udp_port, udp_bind_host)
		if perr != OK:
			push_warning("PoseInputBridge: preview UDP bind failed on %s:%d" % [udp_bind_host, preview_udp_port])
			_preview_udp = null
	if auto_launch_runtime:
		_launch_runtime()


func _exit_tree() -> void:
	if _runtime_pid > 0:
		OS.kill(_runtime_pid)
		_runtime_pid = -1
	if _udp != null:
		_udp.close()
	if _preview_udp != null:
		_preview_udp.close()


func _sh_single_quote(s: String) -> String:
	return "'" + s.replace("'", "'\"'\"'") + "'"


func _resolve_python_path() -> String:
	var custom := python_executable.strip_edges()
	if custom.is_empty():
		custom = "python3"
	# Optional: force interpreter from environment (launch Godot from a configured shell).
	var env_py := OS.get_environment("POSE_PYTHON").strip_edges()
	if not env_py.is_empty() and FileAccess.file_exists(env_py):
		return env_py
	# Expand ~/ for Inspector paths pasted from Terminal.
	if custom.begins_with("~/"):
		var h := OS.get_environment("HOME").strip_edges()
		if not h.is_empty():
			custom = h.path_join(custom.substr(2))
	# Absolute or explicit path from Inspector (e.g. pyenv shim).
	if custom.begins_with("/") or custom.contains(":\\"):
		if FileAccess.file_exists(custom):
			return custom
	# Prefer pyenv shim when present — matches `which python3` for many dev setups; Homebrew may lack mediapipe.
	var candidates: PackedStringArray = PackedStringArray()
	var home := OS.get_environment("HOME").strip_edges()
	if not home.is_empty():
		candidates.append(home.path_join(".pyenv/shims/python3"))
	var pyenv_root := OS.get_environment("PYENV_ROOT").strip_edges()
	if not pyenv_root.is_empty():
		candidates.append(pyenv_root.path_join("shims/python3"))
	candidates.append_array(
		PackedStringArray(
			[
				"/opt/homebrew/bin/python3",
				"/usr/local/bin/python3",
				"/usr/bin/python3",
			]
		)
	)
	for path in candidates:
		if not path.is_empty() and FileAccess.file_exists(path):
			return path
	return custom


func _launch_runtime() -> void:
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var runtime_abs := ProjectSettings.globalize_path(runtime_script_path)
	if not FileAccess.file_exists(runtime_abs):
		push_warning("PoseInputBridge: runtime script missing: %s" % runtime_abs)
		return

	var py := _resolve_python_path()
	_python_used = py
	var err_log := project_dir.path_join("pose/pose_runtime_stderr.log")

	if use_shell_launch and OS.get_name() != "Windows":
		# cd to project + unbuffered python; log stderr/stdout for debugging pkts=0 cases.
		var qd := _sh_single_quote(project_dir)
		var qp := _sh_single_quote(py)
		var qs := _sh_single_quote(runtime_abs)
		var ql := _sh_single_quote(err_log)
		var inner := "cd %s && exec %s -u %s >> %s 2>&1" % [qd, qp, qs, ql]
		_last_launch_shell_cmd = inner
		_runtime_pid = OS.create_process("/bin/sh", PackedStringArray(["-c", inner]), false)
		if _runtime_pid <= 0:
			_runtime_launch_ok = false
			push_warning("PoseInputBridge: shell launch failed (sh -c). Tried python: %s" % py)
		else:
			_runtime_launch_ok = true
			print("PoseInputBridge: shell-launched pose runtime pid=%d python=%s" % [_runtime_pid, py])
		return

	if OS.get_name() == "Windows":
		# cmd.exe: cd project, run python -u, append logs
		var cmd := 'cd /d "%s" && "%s" -u "%s" >> "%s" 2>&1' % [project_dir, py, runtime_abs, err_log]
		_last_launch_shell_cmd = cmd
		_runtime_pid = OS.create_process("cmd.exe", PackedStringArray(["/c", cmd]), false)
		if _runtime_pid <= 0:
			_runtime_launch_ok = false
			push_warning("PoseInputBridge: Windows cmd launch failed. python=%s" % py)
		else:
			_runtime_launch_ok = true
			print("PoseInputBridge: cmd-launched pose runtime pid=%d python=%s" % [_runtime_pid, py])
		return

	# Direct create_process fallback
	var args := PackedStringArray(["-u", runtime_abs])
	_runtime_pid = OS.create_process(py, args, false)
	_last_launch_shell_cmd = "%s -u %s" % [py, runtime_abs]
	if _runtime_pid <= 0:
		_runtime_launch_ok = false
		push_warning("PoseInputBridge: failed to launch runtime process (%s)" % py)
	else:
		_runtime_launch_ok = true
		print("PoseInputBridge: launched runtime pid=%d python=%s script=%s" % [_runtime_pid, py, runtime_abs])


func poll_pose() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var raw := _udp.get_packet()
		_raw_datagram_count += 1
		var text := raw.get_string_from_utf8()
		_parse_packet(text)
	_last_stale_guard()
	poll_preview()


func poll_preview() -> void:
	if _preview_udp == null:
		return
	while _preview_udp.get_available_packet_count() > 0:
		var jpeg_bytes := _preview_udp.get_packet()
		var img := Image.new()
		if img.load_jpg_from_buffer(jpeg_bytes) != OK:
			continue
		_preview_texture = ImageTexture.create_from_image(img)


func _parse_packet(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_json_parse_fail_count += 1
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		_json_parse_fail_count += 1
		return
	var packet: Dictionary = data
	lean_x = clampf(float(packet.get("lean_x", 0.0)), -1.0, 1.0)
	is_centered = bool(packet.get("is_centered", true))
	tracking_confidence = clampf(float(packet.get("tracking_confidence", 0.0)), 0.0, 1.0)
	var hax: Variant = packet.get("head_anchor_x", head_anchor_x)
	if hax != null:
		head_anchor_x = float(hax)
	if bool(packet.get("jump_triggered", false)):
		_jump_latch = true
	jump_triggered = _jump_latch
	_last_packet_ms = Time.get_ticks_msec()
	_packet_count += 1
	packet_updated.emit(packet)


func _last_stale_guard() -> void:
	if _last_packet_ms <= 0:
		return
	var elapsed := float(Time.get_ticks_msec() - _last_packet_ms) / 1000.0
	if elapsed <= stale_timeout_sec:
		return
	# Stale stream: drop to neutral so gameplay falls back safely.
	lean_x = 0.0
	is_centered = true
	tracking_confidence = 0.0
	jump_triggered = false


func has_fresh_tracking() -> bool:
	if _last_packet_ms <= 0:
		return false
	var elapsed := float(Time.get_ticks_msec() - _last_packet_ms) / 1000.0
	return elapsed <= stale_timeout_sec and tracking_confidence >= 0.5


func consume_jump_trigger() -> bool:
	if not _jump_latch:
		return false
	_jump_latch = false
	jump_triggered = false
	return true


func get_packet_age_ms() -> int:
	if _last_packet_ms <= 0:
		return -1
	return Time.get_ticks_msec() - _last_packet_ms


func get_packet_count() -> int:
	return _packet_count


func get_raw_datagram_count() -> int:
	return _raw_datagram_count


func get_json_parse_fail_count() -> int:
	return _json_parse_fail_count


func get_python_used() -> String:
	return _python_used


func is_runtime_launched() -> bool:
	return _runtime_launch_ok and _runtime_pid > 0


func get_camera_preview_texture() -> ImageTexture:
	return _preview_texture


func get_debug_hint() -> String:
	if _raw_datagram_count == 0 and is_runtime_launched():
		return "see pose/pose_runtime_stderr.log + pose_runtime_boot.log"
	if _json_parse_fail_count > 0 and _packet_count == 0:
		return "UDP ok but JSON parse failed"
	return ""
