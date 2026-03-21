extends Node2D

## Subtle downward scroll speed for the starfield (pixels per second).
const BG_SCROLL_SPEED: float = 38.0

## Ship fly-in after start: begin Y (local to Player node) below the play area.
@export var intro_ship_start_y: float = 1100.0
@export var intro_ship_fly_duration: float = 1.75

## Score: passive points per second while the run is active (not game over).
@export var score_passive_per_second: float = 12.0
## Bonus when a laser destroys a normal asteroid.
@export var score_normal_destroy: int = 90
## Bonus when a laser destroys an orange (fast) asteroid.
@export var score_orange_destroy: int = 220

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

## Right-panel camera placeholder (kept for layout; MediaPipe integration will attach later).
@onready var _camera_feed: TextureRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraFeed
@onready var _camera_placeholder: Control = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder
@onready var _camera_hit_flash_overlay: ColorRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/HitFlashOverlay
@onready var _camera_debug_guides_overlay: Control = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/WebcamDebugGuidesOverlay
@onready var _camera_placeholder_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraPlaceholderLabel
@onready var _camera_debug_toggle: CheckButton = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/WebcamDebugToggle/DebugToggleButton
@onready var _hat_instruction_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/HatInstructionLabel
@onready var _webcam_death_quip_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/WebcamDeathQuip
@onready var _webcam_hat: Node2D = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/HatOverlay
@onready var _webcam_hat_brown: Node2D = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/HatOverlay/BrownHat
@onready var _webcam_hat_pink: Node2D = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/HatOverlay/PinkHat

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
@onready var _pose_bridge: PoseInputBridge = $Managers/PoseInputBridge
@onready var _intro_ui: Control = $UILayer/HUD/RootLayout/MainSplit/GamePanel/IntroUI
@onready var _score_hud: Label = $UILayer/HUD/RootLayout/MainSplit/GamePanel/ScoreHud
@onready var _weapon_energy_hud: Control = $UILayer/HUD/RootLayout/MainSplit/GamePanel/WeaponEnergyHud
@onready var _weapon_energy_label: Label = $UILayer/HUD/RootLayout/MainSplit/GamePanel/WeaponEnergyHud/WeaponEnergyLabel
@onready var _weapon_energy_bar: ProgressBar = $UILayer/HUD/RootLayout/MainSplit/GamePanel/WeaponEnergyHud/WeaponEnergyBar
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
var _bg_tile_height: float = 0.0
var _bg_scroll: float = 0.0
var _bg_base_x: float = 400.0
var _bg_base_y: float = 450.0

## Hit feedback shake. (Game side = move GameRoot; Webcam side = move CameraPlaceholder.)
const _HIT_SHAKE_DURATION: float = 0.34
const _HIT_SHAKE_GAME_PIXELS: float = 24.0
const _HIT_SHAKE_WEBCAM_PIXELS: float = 18.0
const _HIT_FLASH_MAX_ALPHA: float = 0.6
const _HIT_FLASH_FADE_IN_DURATION: float = 0.08
const _HIT_FLASH_FADE_OUT_DURATION: float = 0.18
@export var show_webcam_debug_overlay: bool = false
@export var mirror_webcam_preview: bool = true
var _game_root_base_pos: Vector2 = Vector2.ZERO
var _camera_placeholder_base_pos: Vector2 = Vector2.ZERO
var _last_player_health: int = -1
var _hit_shake_game_tween: Tween
var _hit_shake_webcam_tween: Tween
var _camera_hit_flash_tween: Tween
var _pose_anchor_offset_x: float = 0.0
const _HAT_HEAD_OFFSET_Y_PX: float = 8.0
const _HAT_UI_SCALE: float = 1.28
const _HAT_COLOR_SELECT_DEADZONE: float = 0.2
const _HAT_PROMPT_TEXT: String = "Move your head LEFT for pink cowboy hat\nMove your head RIGHT for brown cowboy hat"
const _CONTROLS_PROMPT_TEXT: String = "Controls: move LEFT and RIGHT.\nPress Enter and steering-wheel Back to shoot."
const _WEBCAM_DEATH_QUIPS: PackedStringArray = [
	"look at this guy",
	"get a load of this guy",
	"I guess you didn't yeehaw",
	"space cowboy status: revoked",
	"that asteroid had your number",
]
const _POSE_CALIBRATION_CENTER_WINDOW: float = 0.12
const _POSE_CALIBRATION_LERP_SPEED: float = 3.2
const _POSE_INPUT_DEADZONE: float = 0.06
const _POSE_LEFT_GAIN: float = 1.0
const _POSE_RIGHT_GAIN: float = 1.18
var _hat_use_pink: bool = false
var _hat_color_locked: bool = false


func _ready() -> void:
	_setup_background_parallax()
	_setup_hearts_ui()
	_setup_game_over_ui()
	_setup_intro()
	_setup_audio()
	_setup_camera_panel_placeholder()
	_setup_pose_bridge()
	_game_root_base_pos = _game_root.position
	_camera_placeholder_base_pos = _camera_placeholder.position


func _setup_pose_bridge() -> void:
	if not is_instance_valid(_pose_bridge):
		return
	_pose_bridge.poll_pose()

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
	_hat_color_locked = false
	_hat_use_pink = false
	if is_instance_valid(_webcam_death_quip_label):
		_webcam_death_quip_label.visible = false
		_webcam_death_quip_label.text = ""
	if is_instance_valid(_hat_instruction_label):
		_hat_instruction_label.visible = true
		_hat_instruction_label.text = _HAT_PROMPT_TEXT
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
	if is_instance_valid(_weapon_energy_hud):
		_weapon_energy_hud.visible = false
	if not is_instance_valid(_player_ship):
		return
	_intro_ship_rest_pos = _player_ship.position
	_pose_anchor_offset_x = 0.0


## Call when the player is ready to play (Space / ui_accept now; jump later).
func start_game() -> void:
	if _run_started or _is_game_over:
		return
	_hat_color_locked = true
	if is_instance_valid(_webcam_death_quip_label):
		_webcam_death_quip_label.visible = false
		_webcam_death_quip_label.text = ""
	if is_instance_valid(_hat_instruction_label):
		_hat_instruction_label.visible = true
		_hat_instruction_label.text = _CONTROLS_PROMPT_TEXT
	_run_started = true
	score_session_id += 1
	if is_instance_valid(_pose_bridge) and _pose_bridge.has_fresh_tracking():
		# Treat current posture as the gameplay reference anchor.
		_pose_anchor_offset_x = _pose_bridge.lean_x
	if _intro_ship_tween != null and is_instance_valid(_intro_ship_tween):
		_intro_ship_tween.kill()
	if is_instance_valid(_intro_ui):
		_intro_ui.visible = false
	if is_instance_valid(_score_hud):
		_score_hud.visible = true
	if is_instance_valid(_weapon_energy_hud):
		_weapon_energy_hud.visible = true
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
	if _player_ship.has_method("reset_weapon_energy"):
		_player_ship.reset_weapon_energy()
	_refresh_weapon_energy_hud()
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
		_trigger_camera_hit_flash()
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

	var steps := 12
	var step_duration := _HIT_SHAKE_DURATION / float(steps)

	# Game-side shake (video half).
	var game_tween := create_tween()
	game_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hit_shake_game_tween = game_tween
	for i in range(steps):
		var decay := float(i) / float(steps)
		var amt := _HIT_SHAKE_GAME_PIXELS * (1.0 - decay)
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		game_tween.tween_property(_game_root, "position", _game_root_base_pos + off, step_duration)
	game_tween.tween_property(_game_root, "position", _game_root_base_pos, 0.01)

	# Webcam-side shake (webcam half).
	var webcam_tween := create_tween()
	webcam_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hit_shake_webcam_tween = webcam_tween
	for i in range(steps):
		var decay := float(i) / float(steps)
		var amt := _HIT_SHAKE_WEBCAM_PIXELS * (1.0 - decay)
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
	if is_instance_valid(_hat_instruction_label):
		_hat_instruction_label.visible = false
	if is_instance_valid(_webcam_death_quip_label) and not _WEBCAM_DEATH_QUIPS.is_empty():
		_webcam_death_quip_label.text = _WEBCAM_DEATH_QUIPS[randi() % _WEBCAM_DEATH_QUIPS.size()]
		_webcam_death_quip_label.visible = true
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
	if is_instance_valid(_weapon_energy_hud):
		_weapon_energy_hud.visible = false
	# GamePanel uses MOUSE_FILTER_IGNORE during play so clicks reach the ship; enable hits for the overlay.
	if is_instance_valid(_game_panel):
		_game_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(_game_root):
		_game_root.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	if is_instance_valid(_spawn_manager):
		_spawn_manager.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
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
	if _run_started and not _is_game_over:
		_refresh_weapon_energy_hud()
	if _is_game_over:
		return
	_scroll_backgrounds(delta)
	_update_pose_controls()
	if _run_started:
		_tick_passive_score(delta)


func _update_pose_controls() -> void:
	if not is_instance_valid(_pose_bridge):
		return
	_pose_bridge.poll_pose()
	var cam_tex := _pose_bridge.get_camera_preview_texture()
	if _camera_feed != null and cam_tex != null and _camera_feed.texture != cam_tex:
		_camera_feed.texture = cam_tex
	if not is_instance_valid(_player_ship):
		return

	var has_pose := _pose_bridge.has_fresh_tracking()
	_player_ship.use_external_input = has_pose
	if has_pose:
		var lean_raw := (_pose_bridge.lean_x - _pose_anchor_offset_x) * -1.0
		var frame_dt := get_process_delta_time()
		# Small adaptive re-centering improves feel when neutral posture drifts.
		if absf(lean_raw) <= _POSE_CALIBRATION_CENTER_WINDOW:
			_pose_anchor_offset_x = lerpf(
				_pose_anchor_offset_x,
				_pose_bridge.lean_x,
				clampf(frame_dt * _POSE_CALIBRATION_LERP_SPEED, 0.0, 1.0)
			)
		var lean_adjusted := 0.0
		if absf(lean_raw) > _POSE_INPUT_DEADZONE:
			var magnitude := (absf(lean_raw) - _POSE_INPUT_DEADZONE) / (1.0 - _POSE_INPUT_DEADZONE)
			var gain := _POSE_RIGHT_GAIN if lean_raw > 0.0 else _POSE_LEFT_GAIN
			lean_adjusted = signf(lean_raw) * magnitude * gain
		lean_adjusted = clampf(lean_adjusted, -1.0, 1.0)
		_player_ship.set_external_lean(lean_adjusted)
	else:
		_player_ship.set_external_lean(0.0)
	_update_webcam_hat(has_pose)

	if _pose_bridge.consume_jump_trigger():
		if not _run_started:
			start_game()
		elif _run_started and not _is_game_over and _player_ship.controls_enabled:
			_player_ship.request_fire_once()

	if is_instance_valid(_camera_placeholder_label):
		var status := "TRACKING" if has_pose else "NO TRACKING"
		var live_lean := 0.0 if not has_pose else clampf(_pose_bridge.lean_x - _pose_anchor_offset_x, -1.0, 1.0)
		var packet_age_ms := _pose_bridge.get_packet_age_ms()
		var age_text := "n/a" if packet_age_ms < 0 else ("%dms" % packet_age_ms)
		var runtime_text := "ON" if _pose_bridge.is_runtime_launched() else "OFF"
		var py_hint := _pose_bridge.get_python_used()
		if py_hint.length() > 28:
			py_hint = "…" + py_hint.substr(py_hint.length() - 26, 26)
		var hint := _pose_bridge.get_debug_hint()
		var line1 := "POSE %s | lean %.2f | conf %.2f | age %s" % [status, live_lean, _pose_bridge.tracking_confidence, age_text]
		var line2 := "runtime %s | json_ok %d | udp_rx %d | py %s" % [
			runtime_text,
			_pose_bridge.get_packet_count(),
			_pose_bridge.get_raw_datagram_count(),
			py_hint,
		]
		if hint != "":
			line2 += "\n%s" % hint
		_camera_placeholder_label.text = line1 + "\n" + line2


func _update_webcam_hat(has_pose: bool) -> void:
	if not is_instance_valid(_webcam_hat):
		return
	if not has_pose:
		_webcam_hat.visible = false
		return
	var panel_size := _camera_placeholder.size
	if panel_size.x <= 1.0 or panel_size.y <= 1.0:
		_webcam_hat.visible = false
		return
	# Use live head position so the hat follows left/right movement in real time.
	var head_x := clampf(_pose_bridge.head_x, 0.0, 1.0)
	if mirror_webcam_preview:
		head_x = 1.0 - head_x
	var head_y := clampf(_pose_bridge.head_y, 0.0, 1.0)
	_webcam_hat.visible = true
	var hat_y := clampf(head_y * panel_size.y - _HAT_HEAD_OFFSET_Y_PX, 0.0, panel_size.y)
	_webcam_hat.position = Vector2(head_x * panel_size.x, hat_y)
	var lean_for_style := clampf(_pose_bridge.lean_x - _pose_anchor_offset_x, -1.0, 1.0)
	if not _hat_color_locked:
		if lean_for_style > _HAT_COLOR_SELECT_DEADZONE:
			_hat_use_pink = true
		elif lean_for_style < -_HAT_COLOR_SELECT_DEADZONE:
			_hat_use_pink = false
	if is_instance_valid(_webcam_hat_brown):
		_webcam_hat_brown.visible = not _hat_use_pink
	if is_instance_valid(_webcam_hat_pink):
		_webcam_hat_pink.visible = _hat_use_pink


func _tick_passive_score(delta: float) -> void:
	_passive_score_carry += score_passive_per_second * delta
	while _passive_score_carry >= 1.0:
		_passive_score_carry -= 1.0
		score += 1
	_refresh_score_hud()


func _refresh_score_hud() -> void:
	if is_instance_valid(_score_hud):
		_score_hud.text = "Score: %d" % score


func _refresh_weapon_energy_hud() -> void:
	if not is_instance_valid(_player_ship) or not is_instance_valid(_weapon_energy_bar):
		return
	if not _player_ship.has_method("get_weapon_energy_ratio"):
		return
	_weapon_energy_bar.value = _player_ship.get_weapon_energy_ratio()
	var recharging: bool = _player_ship.is_weapon_recharging() if _player_ship.has_method("is_weapon_recharging") else false
	var ch: int = _player_ship.get_weapon_charges_remaining() if _player_ship.has_method("get_weapon_charges_remaining") else 0
	var mx: int = _player_ship.get_weapon_max_shots() if _player_ship.has_method("get_weapon_max_shots") else 3
	if is_instance_valid(_weapon_energy_label):
		if recharging:
			_weapon_energy_label.text = "Blaster — recharging…"
		else:
			_weapon_energy_label.text = "Blaster — %d / %d" % [ch, mx]
	# Warm tint while refilling (energy / heat read).
	_weapon_energy_bar.modulate = Color(1.0, 0.82, 0.62, 1.0) if recharging else Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _is_game_over:
		if _wants_start_input(event):
			_on_play_again_pressed()
		return
	if not _run_started and _wants_start_input(event):
		start_game()


func _wants_start_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			var k: Key = key_ev.keycode
			# Space + wireless numpad Enter / Back (Backspace), same as shoot keys.
			return k == KEY_SPACE or k == KEY_KP_ENTER or k == KEY_BACKSPACE
	return false


func _scroll_backgrounds(delta: float) -> void:
	if _bg1 == null or _bg2 == null:
		return
	if _bg_tile_height <= 0.0:
		return
	_bg_scroll += BG_SCROLL_SPEED * delta
	_apply_background_positions()


func _setup_camera_panel_placeholder() -> void:
	# Webcam preview comes from pose runtime JPEG over UDP; keep layout and hit flash overlay.
	if _camera_feed != null:
		_camera_feed.texture = null
		_camera_feed.material = null
		_camera_feed.flip_h = mirror_webcam_preview
		_camera_feed.visible = true
	if is_instance_valid(_webcam_hat):
		_webcam_hat.visible = false
		_webcam_hat.position = Vector2(_camera_placeholder.size.x * 0.5, _camera_placeholder.size.y * 0.28)
		_webcam_hat.scale = Vector2(_HAT_UI_SCALE, _HAT_UI_SCALE)
	if is_instance_valid(_webcam_hat_brown):
		_webcam_hat_brown.visible = true
	if is_instance_valid(_webcam_hat_pink):
		_webcam_hat_pink.visible = false
	if is_instance_valid(_camera_hit_flash_overlay):
		_camera_hit_flash_overlay.visible = true
		_camera_hit_flash_overlay.color = Color(1.0, 0.12, 0.12, 0.0)
	if is_instance_valid(_camera_placeholder_label):
		# Bottom strip so it does not cover the whole preview.
		_camera_placeholder_label.anchor_left = 0.0
		_camera_placeholder_label.anchor_top = 1.0
		_camera_placeholder_label.anchor_right = 1.0
		_camera_placeholder_label.anchor_bottom = 1.0
		_camera_placeholder_label.offset_left = 8.0
		_camera_placeholder_label.offset_top = -76.0
		_camera_placeholder_label.offset_right = -8.0
		_camera_placeholder_label.offset_bottom = -6.0
		_camera_placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_camera_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_camera_placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_camera_placeholder_label.add_theme_font_size_override("font_size", 16)
		_camera_placeholder_label.text = "CAMERA: waiting for preview…"
	_setup_webcam_debug_toggle()


func _setup_webcam_debug_toggle() -> void:
	_apply_webcam_debug_overlay(show_webcam_debug_overlay)
	if is_instance_valid(_camera_debug_toggle):
		_camera_debug_toggle.button_pressed = show_webcam_debug_overlay
		if not _camera_debug_toggle.toggled.is_connected(_on_camera_debug_toggle_toggled):
			_camera_debug_toggle.toggled.connect(_on_camera_debug_toggle_toggled)


func _on_camera_debug_toggle_toggled(enabled: bool) -> void:
	_apply_webcam_debug_overlay(enabled)


func _apply_webcam_debug_overlay(enabled: bool) -> void:
	show_webcam_debug_overlay = enabled
	if is_instance_valid(_camera_debug_guides_overlay):
		_camera_debug_guides_overlay.set("show_pose_calibration_guides", enabled)
	if is_instance_valid(_camera_placeholder_label):
		_camera_placeholder_label.visible = enabled


func _trigger_camera_hit_flash() -> void:
	if not is_instance_valid(_camera_hit_flash_overlay):
		return

	if _camera_hit_flash_tween != null:
		_camera_hit_flash_tween.kill()
		_camera_hit_flash_tween = null

	var flash_color := _camera_hit_flash_overlay.color
	flash_color.a = 0.0
	_camera_hit_flash_overlay.color = flash_color

	var peak_color := flash_color
	peak_color.a = _HIT_FLASH_MAX_ALPHA

	_camera_hit_flash_tween = create_tween()
	_camera_hit_flash_tween.set_trans(Tween.TRANS_SINE)
	_camera_hit_flash_tween.set_ease(Tween.EASE_OUT)
	_camera_hit_flash_tween.tween_property(
		_camera_hit_flash_overlay, "color", peak_color, _HIT_FLASH_FADE_IN_DURATION
	)
	_camera_hit_flash_tween.set_ease(Tween.EASE_IN)
	_camera_hit_flash_tween.tween_property(
		_camera_hit_flash_overlay, "color", flash_color, _HIT_FLASH_FADE_OUT_DURATION
	)
