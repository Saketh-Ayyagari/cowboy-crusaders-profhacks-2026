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

## Maximum hit points before game-over logic (not wired yet).
@export var max_health: int = 3

var current_health: int = 0
var _fire_cooldown_remaining: float = 0.0

## Cached half-width so the sprite/collision edges stay inside the playfield.
var _ship_half_width_world: float = 16.0

## When false, movement and shooting are ignored (e.g. intro). Main enables this when the run starts.
var controls_enabled: bool = false

@onready var _main: Node = get_node_or_null("/root/Main")


func _ready() -> void:
	current_health = max_health
	add_to_group("player")
	_ship_half_width_world = _compute_ship_half_width()
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
	_handle_input()
	_update_position()
	_try_fire()


func _reduce_fire_cooldown(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)


func _handle_input() -> void:
	velocity.x = 0.0

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


func _try_fire() -> void:
	if laser_scene == null:
		return
	if _fire_cooldown_remaining > 0.0:
		return
	if not Input.is_action_pressed("ui_accept"):
		return

	var lasers_parent := _get_lasers_container()
	if lasers_parent == null:
		return

	var spawned := laser_scene.instantiate()
	if spawned is Node2D:
		lasers_parent.add_child(spawned)
		spawned.global_position = global_position + Vector2(0, -28)
		_fire_cooldown_remaining = fire_cooldown
		if _main != null and _main.has_method("play_laser_shoot_sfx"):
			_main.play_laser_shoot_sfx()
	elif spawned is Node:
		spawned.queue_free()


func _get_lasers_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Lasers")
