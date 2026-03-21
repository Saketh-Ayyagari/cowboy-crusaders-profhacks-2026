extends CharacterBody2D

## Horizontal movement speed in pixels per second.
@export var horizontal_speed: float = 400.0

## Left and right bounds for x movement (min, max).
## The ship's x position will be clamped to this range.
@export var movement_bounds: Vector2 = Vector2(80, 1520)

## Assign the laser scene in the Inspector (e.g. `res://scenes/laser.tscn`). Leave empty to disable firing.
@export var laser_scene: PackedScene

## Seconds to wait after each shot before another shot is allowed.
@export var fire_cooldown: float = 0.25

var _fire_cooldown_remaining: float = 0.0


func _physics_process(delta: float) -> void:
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
	# Clamp x movement to movement_bounds
	global_position.x = clampf(
		global_position.x,
		movement_bounds.x,
		movement_bounds.y
	)


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
	elif spawned is Node:
		spawned.queue_free()


func _get_lasers_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Lasers")
