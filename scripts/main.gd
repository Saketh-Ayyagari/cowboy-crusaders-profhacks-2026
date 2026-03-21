extends Node2D

## Subtle downward scroll speed for the starfield (pixels per second).
const BG_SCROLL_SPEED: float = 38.0

## Ship fly-in after start: begin Y (local to Player node) below the play area.
@export var intro_ship_start_y: float = 1100.0
@export var intro_ship_fly_duration: float = 1.75

## Score: passive points per second while the run is active (not game over).
@export var score_passive_per_second: float = 12.0
## Bonus when a laser destroys a normal asteroid.
@export var score_normal_destroy: int = 25
## Bonus when a laser destroys an orange (fast) asteroid.
@export var score_orange_destroy: int = 65

const _SFX_LASER_SHOOT: Array[AudioStream] = [
	preload("res://assets/audio/sfx_laser_shoot1.wav"),
	preload("res://assets/audio/sfx_laser_shoot2.wav"),
	preload("res://assets/audio/sfx_laser_shoot3.wav"),
]

const _SFX_ASTEROID_DESTROY: Array[AudioStream] = [
	preload("res://assets/audio/sfx_asteroid_destroy1.wav"),
	preload("res://assets/audio/sfx_asteroid_destroy2.wav"),
	preload("res://assets/audio/sfx_asteroid_destroy3.wav"),
]

const _SFX_PLAYER_HIT: AudioStream = preload("res://assets/audio/sfx_player_hit.wav")
const _SFX_GAME_OVER_CRASH: AudioStream = preload("res://assets/audio/sfx_game_over_crash.wav")
const _SFX_UI_START: AudioStream = preload("res://assets/audio/sfx_ui_start.wav")
const _BGM_GAMEPLAY: AudioStream = preload("res://assets/audio/bgm_gameplay_loop.wav")
const _SFX_ENGINE_LOOP: AudioStream = preload("res://assets/audio/sfx_ship_engine_loop.wav")

const _HEART_FULL := preload("res://assets/art/heart_full.png")
const _HEART_2_3 := preload("res://assets/art/heart_2_3.png")
const _HEART_1_3 := preload("res://assets/art/heart_1_3.png")
const _HEART_EMPTY := preload("res://assets/art/heart_empty.png")

## If >= 0, use this CameraServer index (Inspector override). -1 = auto: skip virtual cams, prefer built-in (e.g. FaceTime HD).
@export var force_camera_feed_index: int = -1

## Prefer capture formats that usually decode to clean full-color in Godot (order matters).
const _WEBCAM_FORMAT_PRIORITY: PackedStringArray = [
	"MJPEG", "JPEG", "RGB", "BGR", "BGRA", "ARGB", "RGBA",
	"yuvs", "420v", "420f", "YUY2", "NV12", "UYVY",
]

const _WEBCAM_VIRTUAL_NAME_HINTS: PackedStringArray = [
	"OBS", "VIRTUAL CAMERA", "CAMO", "ECAMM", "MMHMM", "SNAP",
]

const _WEBCAM_BUILTIN_NAME_HINTS: PackedStringArray = [
	"FACETIME", "BUILT-IN", "ISIGHT", "MACBOOK", "INTEGRATED",
]

## Right-panel debug webcam (TextureRect under CameraPlaceholder).
@onready var _camera_feed: TextureRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraFeed
@onready var _camera_placeholder: Control = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder
@onready var _camera_placeholder_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraPlaceholderLabel

@onready var _bg1: Sprite2D = $GameRoot/World/Background
@onready var _bg2: Sprite2D = $GameRoot/World/Background2

@onready var _heart1: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart1
@onready var _heart2: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart2
@onready var _heart3: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart3
@onready var _player_ship: Node = $GameRoot/Player/PlayerShip

@onready var _game_panel: Panel = $UILayer/HUD/RootLayout/MainSplit/GamePanel
@onready var _game_over_ui: Control = $UILayer/HUD/RootLayout/MainSplit/GamePanel/GameOverUI
@onready var _play_again_button: Button = $UILayer/HUD/RootLayout/MainSplit/GamePanel/GameOverUI/MarginLayer/CenterContent/VBox/PlayAgainButton
@onready var _game_root: Node2D = $GameRoot
@onready var _spawn_manager: Node = $Managers/SpawnManager
@onready var _intro_ui: Control = $UILayer/HUD/RootLayout/MainSplit/GamePanel/IntroUI
@onready var _score_hud: Label = $UILayer/HUD/RootLayout/MainSplit/GamePanel/ScoreHud
@onready var _game_over_score_label: Label = $UILayer/HUD/RootLayout/MainSplit/GamePanel/GameOverUI/MarginLayer/CenterContent/VBox/ScoreLabel

@onready var _bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var _engine_player: AudioStreamPlayer = $EnginePlayer
@onready var _ui_player: AudioStreamPlayer = $UIPlayer
@onready var _sfx_player: AudioStreamPlayer = $SFXPlayer
@onready var _hit_player: AudioStreamPlayer = $HitPlayer
@onready var _crash_player: AudioStreamPlayer = $CrashPlayer

var score: int = 0
## Bumped in start_game(); asteroids only award if their meta matches (avoids stray points on reload).
var score_session_id: int = 0

var _run_started: bool = false
var _is_game_over: bool = false
var _intro_ship_rest_pos: Vector2 = Vector2.ZERO
var _intro_ship_tween: Tween
var _passive_score_carry: float = 0.0
var _logged_no_feed_yet: bool = false
var _webcam_setup_in_progress: bool = false
var _bg_tile_height: float = 0.0
var _bg_scroll: float = 0.0
var _bg_base_x: float = 400.0
var _bg_base_y: float = 450.0

## Hit feedback shake. (Game side = move GameRoot; Webcam side = move CameraPlaceholder.)
const _HIT_SHAKE_DURATION: float = 0.28
const _HIT_SHAKE_GAME_PIXELS: float = 18.0
const _HIT_SHAKE_WEBCAM_PIXELS: float = 14.0
var _game_root_base_pos: Vector2 = Vector2.ZERO
var _camera_placeholder_base_pos: Vector2 = Vector2.ZERO
var _last_player_health: int = -1
var _hit_shake_game_tween: Tween
var _hit_shake_webcam_tween: Tween


func _ready() -> void:
	_setup_background_parallax()
	_setup_hearts_ui()
	_setup_game_over_ui()
	_setup_intro()
	_setup_audio()
	_start_debug_webcam_if_available()
	_game_root_base_pos = _game_root.position
	_camera_placeholder_base_pos = _camera_placeholder.position

func _setup_audio() -> void:
	# Assign streams in code (minimal and beginner-friendly).
	if is_instance_valid(_bgm_player):
		_bgm_player.stream = _BGM_GAMEPLAY
		_bgm_player.volume_db = -14.0
		_bgm_player.autoplay = false
		if not _bgm_player.finished.is_connected(_on_bgm_finished):
			_bgm_player.finished.connect(_on_bgm_finished)

	if is_instance_valid(_engine_player):
		_engine_player.stream = _SFX_ENGINE_LOOP
		_engine_player.volume_db = -8.0
		_engine_player.autoplay = false
		if not _engine_player.finished.is_connected(_on_engine_finished):
			_engine_player.finished.connect(_on_engine_finished)

	if is_instance_valid(_ui_player):
		_ui_player.stream = _SFX_UI_START
		_ui_player.volume_db = -6.0
		_ui_player.autoplay = false

	if is_instance_valid(_sfx_player):
		_sfx_player.stream = _SFX_LASER_SHOOT[0]
		_sfx_player.volume_db = -3.0
		_sfx_player.autoplay = false

	if is_instance_valid(_hit_player):
		_hit_player.stream = _SFX_PLAYER_HIT
		_hit_player.volume_db = -1.0
		_hit_player.autoplay = false

	if is_instance_valid(_crash_player):
		_crash_player.stream = _SFX_GAME_OVER_CRASH
		_crash_player.volume_db = -3.0
		_crash_player.autoplay = false


func _on_bgm_finished() -> void:
	# We fake looping by restarting when the track ends.
	if _run_started and not _is_game_over and is_instance_valid(_bgm_player):
		_bgm_player.play()


func _on_engine_finished() -> void:
	if _run_started and not _is_game_over and is_instance_valid(_engine_player):
		_engine_player.play()


func _play_random_from_list(list: Array[AudioStream], player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if list.is_empty():
		return
	var pick := list[randi() % list.size()]
	player.stream = pick
	player.play()


func play_laser_shoot_sfx() -> void:
	_play_random_from_list(_SFX_LASER_SHOOT, _sfx_player)


func play_asteroid_destroy_sfx() -> void:
	_play_random_from_list(_SFX_ASTEROID_DESTROY, _sfx_player)


func play_player_hit_sfx() -> void:
	if is_instance_valid(_hit_player):
		_hit_player.play()


func play_game_over_crash_sfx() -> void:
	if is_instance_valid(_crash_player):
		_crash_player.play()


func _setup_hearts_ui() -> void:
	if _heart1 == null or _heart2 == null or _heart3 == null:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if not _player_ship.has_signal("health_changed"):
		return
	if not _player_ship.health_changed.is_connected(_on_player_health_changed):
		_player_ship.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(_player_ship.current_health, _player_ship.max_health)


func _setup_game_over_ui() -> void:
	if is_instance_valid(_play_again_button) and not _play_again_button.pressed.is_connected(_on_play_again_pressed):
		_play_again_button.pressed.connect(_on_play_again_pressed)


func _setup_intro() -> void:
	_run_started = false
	score = 0
	_passive_score_carry = 0.0
	if is_instance_valid(_spawn_manager):
		_spawn_manager.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_player_ship):
		_player_ship.controls_enabled = false
		_player_ship.visible = false
	if is_instance_valid(_intro_ui):
		_intro_ui.visible = true
	if is_instance_valid(_score_hud):
		_score_hud.visible = false
		_refresh_score_hud()
	if not is_instance_valid(_player_ship):
		return
	_intro_ship_rest_pos = _player_ship.position


## Call when the player is ready to play (Space / ui_accept now; jump later).
func start_game() -> void:
	if _run_started or _is_game_over:
		return
	_run_started = true
	score_session_id += 1
	if _intro_ship_tween != null and is_instance_valid(_intro_ship_tween):
		_intro_ship_tween.kill()
	if is_instance_valid(_intro_ui):
		_intro_ui.visible = false
	if is_instance_valid(_score_hud):
		_score_hud.visible = true
	if is_instance_valid(_spawn_manager):
		if _spawn_manager.has_method("reset_for_run"):
			_spawn_manager.reset_for_run()
		_spawn_manager.process_mode = Node.PROCESS_MODE_INHERIT
	# Audio starts when gameplay begins.
	if is_instance_valid(_ui_player):
		_ui_player.play()
	if is_instance_valid(_bgm_player):
		_bgm_player.play()
	if is_instance_valid(_engine_player):
		_engine_player.play()
	if not is_instance_valid(_player_ship):
		return
	_player_ship.visible = true
	_player_ship.controls_enabled = false
	_player_ship.position = Vector2(_intro_ship_rest_pos.x, intro_ship_start_y)
	_intro_ship_tween = create_tween()
	_intro_ship_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_ship_tween.tween_property(
		_player_ship, "position", _intro_ship_rest_pos, intro_ship_fly_duration
	)
	_intro_ship_tween.tween_callback(_enable_player_after_intro_fly)


func _enable_player_after_intro_fly() -> void:
	if is_instance_valid(_player_ship):
		_player_ship.controls_enabled = true


func on_asteroid_destroyed(fast_orange: bool, asteroid_session_id: int) -> void:
	if not _run_started or _is_game_over:
		return
	if asteroid_session_id != score_session_id:
		return
	var bonus := score_orange_destroy if fast_orange else score_normal_destroy
	score += bonus
	_refresh_score_hud()
	play_asteroid_destroy_sfx()


func _on_player_health_changed(current: int, maximum: int) -> void:
	_refresh_hearts_display(current, maximum)
	# Only shake on damage (health decreased), not on initial setup.
	if _last_player_health >= 0 and current < _last_player_health:
		_trigger_hit_shake()
	_last_player_health = current
	if current <= 0 and not _is_game_over:
		_trigger_game_over()


func _trigger_hit_shake() -> void:
	if not is_instance_valid(_game_root) or not is_instance_valid(_camera_placeholder):
		return

	# Reset to the baseline before starting a new shake.
	_game_root.position = _game_root_base_pos
	_camera_placeholder.position = _camera_placeholder_base_pos

	if _hit_shake_game_tween != null:
		_hit_shake_game_tween.kill()
	_hit_shake_game_tween = null
	if _hit_shake_webcam_tween != null:
		_hit_shake_webcam_tween.kill()
	_hit_shake_webcam_tween = null

	var steps := 10
	var step_duration := _HIT_SHAKE_DURATION / float(steps)

	# Game-side shake (video half).
	var game_tween := create_tween()
	game_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hit_shake_game_tween = game_tween
	for i in range(steps):
		var t := float(i) / float(steps)
		var amt := _HIT_SHAKE_GAME_PIXELS * (1.0 - t)
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		game_tween.tween_property(_game_root, "position", _game_root_base_pos + off, step_duration)
	game_tween.tween_property(_game_root, "position", _game_root_base_pos, 0.01)

	# Webcam-side shake (webcam half).
	var webcam_tween := create_tween()
	webcam_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hit_shake_webcam_tween = webcam_tween
	for i in range(steps):
		var t := float(i) / float(steps)
		var amt := _HIT_SHAKE_WEBCAM_PIXELS * (1.0 - t)
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		webcam_tween.tween_property(_camera_placeholder, "position", _camera_placeholder_base_pos + off, step_duration)
	webcam_tween.tween_property(_camera_placeholder, "position", _camera_placeholder_base_pos, 0.01)


func _restore_hit_shake_state() -> void:
	# Called after a short delay when the player dies, so we don't cancel the hit feedback.
	if _hit_shake_game_tween != null:
		_hit_shake_game_tween.kill()
		_hit_shake_game_tween = null
	if _hit_shake_webcam_tween != null:
		_hit_shake_webcam_tween.kill()
		_hit_shake_webcam_tween = null
	if is_instance_valid(_game_root):
		_game_root.position = _game_root_base_pos
	if is_instance_valid(_camera_placeholder):
		_camera_placeholder.position = _camera_placeholder_base_pos


func _trigger_game_over() -> void:
	_is_game_over = true
	# Allow any hit shake to play out, then restore baseline so the overlay isn't offset.
	if _hit_shake_game_tween != null or _hit_shake_webcam_tween != null:
		var restore_timer := get_tree().create_timer(_HIT_SHAKE_DURATION + 0.05)
		restore_timer.timeout.connect(_restore_hit_shake_state)
	else:
		_restore_hit_shake_state()
	# Stop gameplay loops and play a crash once.
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
	if is_instance_valid(_engine_player):
		_engine_player.stop()
	play_game_over_crash_sfx()
	if is_instance_valid(_game_over_score_label):
		_game_over_score_label.text = "Score: %d" % score
	if is_instance_valid(_game_over_ui):
		_game_over_ui.visible = true
	# GamePanel uses MOUSE_FILTER_IGNORE during play so clicks reach the ship; enable hits for the overlay.
	if is_instance_valid(_game_panel):
		_game_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(_game_root):
		_game_root.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_spawn_manager):
		_spawn_manager.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_play_again_button):
		_play_again_button.grab_focus()


func _on_play_again_pressed() -> void:
	get_tree().reload_current_scene()


func _refresh_hearts_display(current_health: int, max_health: int) -> void:
	if not is_instance_valid(_heart1) or not is_instance_valid(_heart2) or not is_instance_valid(_heart3):
		return
	var hp := clampi(current_health, 0, max_health)
	var mx := maxi(1, max_health)
	# Map any max_health onto 0–3 heart steps, then same art as max 3.
	var steps := 3
	var filled := int(round((float(hp) / float(mx)) * float(steps)))
	filled = clampi(filled, 0, steps)
	match filled:
		3:
			_apply_heart_row(_HEART_FULL, _HEART_FULL, _HEART_FULL)
		2:
			_apply_heart_row(_HEART_FULL, _HEART_FULL, _HEART_2_3)
		1:
			_apply_heart_row(_HEART_FULL, _HEART_1_3, _HEART_EMPTY)
		_:
			_apply_heart_row(_HEART_EMPTY, _HEART_EMPTY, _HEART_EMPTY)


func _apply_heart_row(t1: Texture2D, t2: Texture2D, t3: Texture2D) -> void:
	_heart1.texture = t1
	_heart2.texture = t2
	_heart3.texture = t3


func _setup_background_parallax() -> void:
	if _bg1 == null or _bg2 == null:
		return
	var tex_h := float(_bg1.texture.get_height()) * _bg1.scale.y
	_bg_tile_height = tex_h
	_bg_base_x = _bg1.position.x
	_bg_base_y = _bg1.position.y
	_bg_scroll = 0.0
	_bg2.texture = _bg1.texture
	_bg2.scale = _bg1.scale
	_bg2.z_index = _bg1.z_index
	_apply_background_positions()


func _apply_background_positions() -> void:
	var h := _bg_tile_height
	if h <= 0.0:
		return
	var o := fposmod(_bg_scroll, h)
	_bg1.position = Vector2(_bg_base_x, _bg_base_y + o)
	_bg2.position = Vector2(_bg_base_x, _bg_base_y - h + o)


func _process(delta: float) -> void:
	if _is_game_over:
		return
	_scroll_backgrounds(delta)
	if _run_started:
		_tick_passive_score(delta)


func _tick_passive_score(delta: float) -> void:
	_passive_score_carry += score_passive_per_second * delta
	while _passive_score_carry >= 1.0:
		_passive_score_carry -= 1.0
		score += 1
	_refresh_score_hud()


func _refresh_score_hud() -> void:
	if is_instance_valid(_score_hud):
		_score_hud.text = "Score: %d" % score


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _is_game_over:
		if event.is_action_pressed("ui_accept"):
			_on_play_again_pressed()
		return
	if not _run_started and _wants_start_input(event):
		start_game()


func _wants_start_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode == KEY_SPACE
	return false


func _scroll_backgrounds(delta: float) -> void:
	if _bg1 == null or _bg2 == null:
		return
	if _bg_tile_height <= 0.0:
		return
	_bg_scroll += BG_SCROLL_SPEED * delta
	_apply_background_positions()


func _start_debug_webcam_if_available() -> void:
	if _camera_feed == null:
		print("Webcam debug: CameraFeed node not found.")
		return

	# Fill the webcam panel more aggressively so shakes feel "full frame".
	_camera_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_camera_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_feed.modulate = Color.WHITE
	_camera_feed.self_modulate = Color.WHITE
	_camera_feed.material = null
	_camera_feed.use_parent_material = false

	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)

	CameraServer.monitoring_feeds = true
	print("Webcam debug: Monitoring enabled; looking for a camera…")

	call_deferred("_try_assign_first_camera_feed")


func _on_camera_feeds_updated() -> void:
	_try_assign_first_camera_feed()


func _datatype_to_string(dt: int) -> String:
	match dt:
		CameraFeed.FEED_NOIMAGE:
			return "FEED_NOIMAGE"
		CameraFeed.FEED_RGB:
			return "FEED_RGB"
		CameraFeed.FEED_YCBCR:
			return "FEED_YCBCR"
		CameraFeed.FEED_YCBCR_SEP:
			return "FEED_YCBCR_SEP"
		CameraFeed.FEED_EXTERNAL:
			return "FEED_EXTERNAL"
		_:
			return "unknown(%d)" % dt


func _webcam_name_matches_any_hint(name_upper: String, hints: PackedStringArray) -> bool:
	for hint in hints:
		if hint in name_upper:
			return true
	return false


func _resolve_webcam_feed_index() -> int:
	var count := CameraServer.get_feed_count()
	if count <= 0:
		return 0
	if force_camera_feed_index >= 0:
		if force_camera_feed_index < count:
			var forced := CameraServer.get_feed(force_camera_feed_index)
			var forced_name := forced.get_name() if forced else "?"
			print("Webcam debug: Using force_camera_feed_index = %d ('%s')" % [force_camera_feed_index, forced_name])
			return force_camera_feed_index
		push_warning(
			"Webcam debug: force_camera_feed_index=%d out of range (count=%d); falling back to auto."
			% [force_camera_feed_index, count]
		)
	var first_non_virtual := -1
	for i in range(count):
		var f := CameraServer.get_feed(i)
		if f == null:
			continue
		var name_u := f.get_name().to_upper()
		if _webcam_name_matches_any_hint(name_u, _WEBCAM_VIRTUAL_NAME_HINTS):
			continue
		if first_non_virtual < 0:
			first_non_virtual = i
		if _webcam_name_matches_any_hint(name_u, _WEBCAM_BUILTIN_NAME_HINTS):
			print("Webcam debug: Using built-in camera — index %d, '%s'" % [i, f.get_name()])
			return i
	if first_non_virtual >= 0:
		var pick := CameraServer.get_feed(first_non_virtual)
		var pick_name := pick.get_name() if pick else "?"
		print(
			"Webcam debug: Using first non-virtual camera — index %d, '%s'"
			% [first_non_virtual, pick_name]
		)
		return first_non_virtual
	push_warning("Webcam debug: All camera feeds look virtual; falling back to index 0.")
	var fb := CameraServer.get_feed(0)
	print("Webcam debug: Fallback index 0 — '%s'" % (fb.get_name() if fb else "?"))
	return 0


func _pick_preferred_format_index(formats: Array) -> int:
	if formats.is_empty():
		return 0
	for key in _WEBCAM_FORMAT_PRIORITY:
		var ku := key.to_upper()
		for i in range(formats.size()):
			var entry: Variant = formats[i]
			var haystack := str(entry).to_upper()
			if ku in haystack:
				return i
	return 0


func _ordered_format_indices(n: int, preferred: int) -> Array[int]:
	var out: Array[int] = []
	var used: Dictionary = {}
	if preferred >= 0 and preferred < n:
		out.append(preferred)
		used[preferred] = true
	for i in range(n):
		if not used.has(i):
			out.append(i)
	return out


func _await_feed_datatype(feed: CameraFeed) -> int:
	# macOS / some drivers update get_datatype() a frame or two after set_format.
	await get_tree().process_frame
	await get_tree().process_frame
	return feed.get_datatype()


func _try_set_format_and_probe(feed: CameraFeed, index: int, params: Dictionary) -> int:
	feed.feed_is_active = false
	var ok: bool = feed.set_format(index, params)
	if not ok:
		print("Webcam debug: set_format(%d, %s) returned false" % [index, params])
	feed.feed_is_active = true
	await get_tree().process_frame
	var dt: int = await _await_feed_datatype(feed)
	print(
		"Webcam debug: probe format index=%d params=%s -> datatype=%s"
		% [index, params, _datatype_to_string(dt)]
	)
	return dt


func _configure_camera_feed_for_display(feed: CameraFeed) -> String:
	var formats: Array = feed.get_formats()
	var n: int = formats.size()
	print("Webcam debug: %d format(s) reported for this device." % n)
	for i in range(n):
		print("Webcam debug:   format[%d] = %s" % [i, formats[i]])

	if n == 0:
		print("Webcam debug: No format list — using engine default (no set_format).")
		return "no_formats_default"

	var preferred: int = _pick_preferred_format_index(formats)
	var order: Array[int] = _ordered_format_indices(n, preferred)

	# Pass 1: normal set_format — look for true RGB pipeline (best for correct color).
	for idx in order:
		var dt := await _try_set_format_and_probe(feed, idx, {})
		if dt == CameraFeed.FEED_RGB:
			print("Webcam debug: COLOR PATH = native_rgb (format index %d)" % idx)
			return "native_rgb"

	# Pass 2: Godot docs — "grayscale" output forces a decoded FEED_RGB path (fixes YUV shown as wrong RGB / red cast).
	print("Webcam debug: No native FEED_RGB found; trying grayscale decode pass…")
	for idx in order:
		var dt2 := await _try_set_format_and_probe(feed, idx, {"output": "grayscale"})
		if dt2 == CameraFeed.FEED_RGB:
			print(
				"Webcam debug: COLOR PATH = grayscale_decode (format index %d) — grayscale image, but no false color tint."
				% idx
			)
			return "grayscale_decode"

	# Last resort: preferred index, default params
	print("Webcam debug: COLOR PATH = fallback_preferred_empty — tint may be driver/YUV related.")
	feed.feed_is_active = false
	feed.set_format(preferred, {})
	feed.feed_is_active = true
	await get_tree().process_frame
	return "fallback_preferred_empty"


func _finish_webcam_texture_bind(feed: CameraFeed, color_path: String) -> void:
	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = feed.get_id()
	cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	cam_tex.camera_is_active = true

	_camera_feed.material = null
	_camera_feed.modulate = Color.WHITE
	_camera_feed.self_modulate = Color.WHITE
	_camera_feed.texture = cam_tex

	if is_instance_valid(_camera_placeholder_label):
		_camera_placeholder_label.visible = false

	var dt: int = feed.get_datatype()
	print("Webcam debug: feed_is_active = %s" % feed.feed_is_active)
	print("Webcam debug: cam_tex.camera_is_active = %s" % cam_tex.camera_is_active)
	print(
		"Webcam debug: Assigned %s (camera_feed_id=%d, which_feed=FEED_RGBA_IMAGE/0)"
		% [cam_tex, cam_tex.camera_feed_id]
	)
	print("Webcam debug: final get_datatype() = %s" % _datatype_to_string(dt))
	print("Webcam debug: color_path = %s" % color_path)

	if color_path == "grayscale_decode":
		print(
			"Webcam debug: NOTE — Using grayscale decode so YUV is not mis-read as RGB (removes red cast; no chroma)."
		)
	elif color_path == "fallback_preferred_empty" or dt != CameraFeed.FEED_RGB:
		print(
			"Webcam debug: NOTE — If the feed is still tinted, the OS is likely handing Godot a YUV layout this build mishandles; try another camera app or a Godot engine update."
		)


func _run_webcam_setup_async(feed: CameraFeed) -> void:
	var path := await _configure_camera_feed_for_display(feed)
	_finish_webcam_texture_bind(feed, path)
	_webcam_setup_in_progress = false


func _try_assign_first_camera_feed() -> void:
	if _camera_feed == null:
		return
	if _camera_feed.texture != null:
		return
	if _webcam_setup_in_progress:
		return

	var count := CameraServer.get_feed_count()
	print("Webcam debug: CameraServer.get_feed_count() = %d" % count)

	if count == 0:
		if not _logged_no_feed_yet:
			print("Webcam debug: No camera feed found (not supported or permission denied).")
			_logged_no_feed_yet = true
		return

	var feed_index := _resolve_webcam_feed_index()
	var feed := CameraServer.get_feed(feed_index)
	if feed == null:
		print("Webcam debug: get_feed(%d) returned null." % feed_index)
		return

	print(
		"Webcam debug: Using feed index %d — name '%s', id=%d"
		% [feed_index, feed.get_name(), feed.get_id()]
	)

	_webcam_setup_in_progress = true
	_run_webcam_setup_async(feed)
