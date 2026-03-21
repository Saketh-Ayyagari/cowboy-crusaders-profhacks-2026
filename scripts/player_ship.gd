extends CharacterBody2D

signal health_changed(current: int, maximum: int)

## Horizontal movement speed in pixels per second.
@export var horizontal_speed: float = 400.0

## World X where the portrait playfield starts (viewport uses 1:1 world pixels by default).
@export var playfield_x_min: float = 0.0
## World X where the playfield ends (left half of a 1600-wide window = 800; ship stays left of this).
@export var playfield_x_max: float = 800.0

## Assign the laser scene in the Inspector (e.g. `res://scenes/laser.tscn`). Leave empty to disable firing.
@export var laser_scene: PackedScene

## Seconds to wait after each shot before another shot is allowed.
@export var fire_cooldown: float = 0.25

## Burst capacity: each successful shot consumes one charge; at 0 the weapon exhausts until the bar refills.
@export_range(1, 8) var weapon_max_shots: int = 3
## Seconds for the energy bar to refill from empty after exhaustion (restores full `weapon_max_shots`).
@export var weapon_full_recharge_seconds: float = 1.65

## Maximum hit points before game-over logic (not wired yet).
@export var max_health: int = 3
@export var external_max_speed: float = 560.0
@export var external_base_accel: float = 820.0
@export var external_recenter_accel: float = 2600.0

var current_health: int = 0
var _fire_cooldown_remaining: float = 0.0

var _weapon_charges: int = 3
var _weapon_recharging: bool = false
## 0..1 while recharging; unused when not recharging.
var _weapon_recharge_progress: float = 0.0

## Cached half-width so the sprite/collision edges stay inside the playfield.
var _ship_half_width_world: float = 16.0

## When false, movement and shooting are ignored (e.g. intro). Main enables this when the run starts.
var controls_enabled: bool = false
var use_external_input: bool = false
var external_lean_x: float = 0.0
var _external_velocity_x: float = 0.0
var _fire_request_once: bool = false

@onready var _main: Node = get_node_or_null("/root/Main")


func _ready() -> void:
	current_health = max_health
	add_to_group("player")
	_ship_half_width_world = _compute_ship_half_width()
	reset_weapon_energy()
	health_changed.emit(current_health, max_health)


func _compute_ship_half_width() -> float:
	var hw := 16.0
	var cs := $CollisionShape2D as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		hw = maxf(hw, cs.shape.size.x * 0.5 * abs(cs.scale.x))
	var spr := $ShipSprite as Sprite2D
	if spr != null and spr.texture != null:
		var sw: float = float(spr.texture.get_width()) * abs(spr.scale.x) * 0.5
		hw = maxf(hw, sw)
	return hw


func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	if _main != null and _main.has_method("play_player_hit_sfx"):
		_main.play_player_hit_sfx()
	current_health = maxi(0, current_health - amount)
	print("PlayerShip: damage %d — health now %d / %d" % [amount, current_health, max_health])
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	if current_health <= 0:
		return
	if not controls_enabled:
		return
	_reduce_fire_cooldown(delta)
	_update_weapon_recharge(delta)
	_handle_input()
	_update_position()
	_try_fire()


func _reduce_fire_cooldown(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)


func reset_weapon_energy() -> void:
	_weapon_charges = maxi(1, weapon_max_shots)
	_weapon_recharging = false
	_weapon_recharge_progress = 0.0


func get_weapon_max_shots() -> int:
	return maxi(1, weapon_max_shots)


func get_weapon_charges_remaining() -> int:
	return _weapon_charges


func is_weapon_recharging() -> bool:
	return _weapon_recharging


## HUD fill: discrete charges as a fraction of max when armed; smooth 0→1 while recharging.
func get_weapon_energy_ratio() -> float:
	if _weapon_recharging:
		return clampf(_weapon_recharge_progress, 0.0, 1.0)
	var m := float(get_weapon_max_shots())
	return clampf(float(_weapon_charges) / m, 0.0, 1.0)


func _can_fire_weapon() -> bool:
	return not _weapon_recharging and _weapon_charges > 0


func _update_weapon_recharge(delta: float) -> void:
	if not _weapon_recharging:
		return
	var dur := maxf(0.05, weapon_full_recharge_seconds)
	_weapon_recharge_progress += delta / dur
	if _weapon_recharge_progress >= 1.0:
		_weapon_recharging = false
		_weapon_charges = get_weapon_max_shots()
		_weapon_recharge_progress = 0.0


func _handle_input() -> void:
	if use_external_input:
		var lean := clampf(external_lean_x, -1.0, 1.0)
		var dir := signf(lean)
		var mag := pow(absf(lean), 1.85)
		var target_speed := dir * external_max_speed * mag
		var accel := external_recenter_accel if absf(lean) < 0.06 else external_base_accel * (1.0 + absf(lean) * 1.25)
		_external_velocity_x = move_toward(_external_velocity_x, target_speed, accel * get_physics_process_delta_time())
		velocity.x = _external_velocity_x
	else:
		velocity.x = 0.0
		_external_velocity_x = move_toward(_external_velocity_x, 0.0, external_recenter_accel * get_physics_process_delta_time())
		# Temporary keyboard fallback input
		if Input.is_action_pressed("ui_left"):
			velocity.x = -horizontal_speed
		elif Input.is_action_pressed("ui_right"):
			velocity.x = horizontal_speed
	move_and_slide()


func _update_position() -> void:
	var lo := playfield_x_min + _ship_half_width_world
	var hi := playfield_x_max - _ship_half_width_world
	global_position.x = clampf(global_position.x, lo, hi)


func _wants_shoot_held() -> bool:
	if Input.is_action_pressed("ui_accept"):
		return true
	# Wireless numpad: Enter + Back (usually Backspace) match shoot like ui_accept.
	return Input.is_key_pressed(KEY_KP_ENTER) or Input.is_key_pressed(KEY_BACKSPACE)


func _try_fire() -> void:
	if laser_scene == null:
		return
	var requested := _fire_request_once or _wants_shoot_held()
	_fire_request_once = false
	if not requested:
		return
	if not _can_fire_weapon():
		return
	if _fire_cooldown_remaining > 0.0:
		return

	var lasers_parent := _get_lasers_container()
	if lasers_parent == null:
		return

	var spawned := laser_scene.instantiate()
	if spawned is Node2D:
		lasers_parent.add_child(spawned)
		spawned.global_position = global_position + Vector2(0, -28)
		_weapon_charges = maxi(0, _weapon_charges - 1)
		if _weapon_charges <= 0:
			_weapon_recharging = true
			_weapon_recharge_progress = 0.0
		_fire_cooldown_remaining = fire_cooldown
		if _main != null and _main.has_method("play_laser_shoot_sfx"):
			_main.play_laser_shoot_sfx()
	elif spawned is Node:
		spawned.queue_free()


func _get_lasers_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Lasers")


func set_external_lean(lean: float) -> void:
	external_lean_x = clampf(lean, -1.0, 1.0)


func request_fire_once() -> void:
	_fire_request_once = true
