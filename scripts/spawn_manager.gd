extends Node

## Assign `res://scenes/asteroid.tscn` in the Inspector. Leave empty to disable spawning.
@export var asteroid_scene: PackedScene

## How fast difficulty increases (spawn spacing tightens + asteroids speed up).
@export var difficulty_ramp_per_second: float = 0.012
## Shortest time between spawns as difficulty maxes out.
@export var minimum_spawn_interval: float = 0.45
## Starting seconds between each asteroid spawn.
@export var base_spawn_interval: float = 1.0

## Base fall speed before time scaling (pixels per second).
@export var base_asteroid_speed: float = 250.0
## Cap on global speed scaling from time (1.0 = no bonus).
@export var max_speed_multiplier: float = 1.5

## Extra multiplier for `asteroid2.png` (orange) — applied on top of time scaling.
@export var orange_speed_multiplier: float = 1.85

## Random horizontal range for new asteroids (local x under the Asteroids node).
@export var spawn_x_min: float = 80.0
@export var spawn_x_max: float = 1520.0

## Vertical spawn position (local y under the Asteroids node).
@export var spawn_y: float = -80.0

const _ASTEROID_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/asteroid1.png"),
	preload("res://assets/art/asteroid2.png"),
	preload("res://assets/art/asteroid3.png"),
]

var _elapsed: float = 0.0
var _run_time: float = 0.0


func _process(delta: float) -> void:
	_run_time += delta
	_elapsed += delta
	var interval := _get_spawn_interval()
	if _elapsed < interval:
		return
	_elapsed -= interval
	_spawn_asteroid()


func _get_spawn_interval() -> float:
	return maxf(minimum_spawn_interval, base_spawn_interval - difficulty_ramp_per_second * _run_time)


func _get_speed_scale() -> float:
	return minf(max_speed_multiplier, 1.0 + difficulty_ramp_per_second * _run_time)


func _spawn_asteroid() -> void:
	if asteroid_scene == null:
		return

	var container := _get_asteroids_container()
	if container == null:
		return

	var spawned := asteroid_scene.instantiate()
	if not (spawned is Node2D):
		if spawned is Node:
			spawned.queue_free()
		return

	var tex: Texture2D = _ASTEROID_TEXTURES[randi() % _ASTEROID_TEXTURES.size()]
	var is_orange := tex == _ASTEROID_TEXTURES[1]

	spawned.fall_speed = base_asteroid_speed * _get_speed_scale()
	var variant_mult := orange_speed_multiplier if is_orange else 1.0
	spawned.setup_variant(tex, variant_mult)

	if is_orange:
		print("Spawn: fast orange asteroid (x%.2f)" % variant_mult)

	container.add_child(spawned)
	var x := randf_range(spawn_x_min, spawn_x_max)
	spawned.position = Vector2(x, spawn_y)


func _get_asteroids_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Asteroids")
