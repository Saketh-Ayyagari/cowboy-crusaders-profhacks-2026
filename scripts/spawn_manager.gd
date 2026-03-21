extends Node

## Assign `res://scenes/asteroid.tscn` in the Inspector. Leave empty to disable spawning.
@export var asteroid_scene: PackedScene

## Spawn timing: seconds between spawns at run start.
@export var base_spawn_interval: float = 1.0
## Floor — never spawn faster than this (seconds between spawn ticks).
@export var minimum_spawn_interval: float = 0.24
## How much the spawn interval shrinks per second of active play.
@export var spawn_ramp_per_second: float = 0.018

## Speed: starting global multiplier on fall speed (before orange variant).
@export var base_speed_multiplier: float = 1.0
## Cap on global speed multiplier from time.
@export var max_speed_multiplier: float = 1.85
## How much the speed multiplier rises per second of active play.
@export var speed_ramp_per_second: float = 0.0105

## Extra multiplier for `asteroid2.png` (orange) — stacks on top of time scaling.
@export var orange_speed_multiplier: float = 1.85

## Base fall speed before multipliers (pixels per second).
@export var base_asteroid_speed: float = 250.0

## Bursts: only after this many seconds of play can multi-spawns roll.
@export var burst_unlock_time: float = 18.0
## Chance (0–1) each spawn tick to spawn a burst instead of a single rock.
@export var burst_chance: float = 0.30
## Max asteroids in one burst (actual count is 2..max inclusive when burst fires).
@export var max_burst_count: int = 3

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
## Active run time only while this node processes (intro off, game over off).
var _run_time: float = 0.0


func reset_for_run() -> void:
	_elapsed = 0.0
	_run_time = 0.0


func _process(delta: float) -> void:
	_run_time += delta
	_elapsed += delta
	var interval := _get_spawn_interval()
	if _elapsed < interval:
		return
	_elapsed -= interval
	_spawn_tick()


func _get_spawn_interval() -> float:
	return maxf(minimum_spawn_interval, base_spawn_interval - spawn_ramp_per_second * _run_time)


func _get_speed_scale() -> float:
	return minf(max_speed_multiplier, base_speed_multiplier + speed_ramp_per_second * _run_time)


func _spawn_tick() -> void:
	var n := 1
	if _run_time >= burst_unlock_time and randf() < burst_chance:
		var hi := clampi(max_burst_count, 2, 3)
		n = randi_range(2, hi)
		print("SpawnManager: burst x%d @ t=%.1fs" % [n, _run_time])
	for i in range(n):
		_spawn_one_asteroid(i, n)


func _spawn_one_asteroid(index_in_group: int, group_size: int) -> void:
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
	spawned.setup_variant(tex, variant_mult, is_orange)

	if is_orange:
		print("Spawn: fast orange asteroid (x%.2f)" % variant_mult)

	var main_ref := get_node_or_null("/root/Main")
	if main_ref != null:
		spawned.set_meta("score_session_id", main_ref.score_session_id)

	container.add_child(spawned)
	var x := _pick_spawn_x(index_in_group, group_size)
	var y_jitter := float(index_in_group) * -6.0
	spawned.position = Vector2(x, spawn_y + y_jitter)


func _pick_spawn_x(index_in_group: int, group_size: int) -> float:
	if group_size <= 1:
		return randf_range(spawn_x_min, spawn_x_max)
	var span := spawn_x_max - spawn_x_min
	var seg := span / float(group_size)
	var lo := spawn_x_min + float(index_in_group) * seg
	var hi := lo + seg
	var margin := seg * 0.08
	return randf_range(lo + margin, hi - margin)


func _get_asteroids_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Asteroids")
