extends Node

## Assign `res://scenes/asteroid.tscn` in the Inspector. Leave empty to disable spawning.
@export var asteroid_scene: PackedScene

## Seconds between each asteroid spawn.
@export var spawn_interval: float = 1.0

## Random horizontal range for new asteroids (local x under the Asteroids node).
@export var spawn_x_min: float = 80.0
@export var spawn_x_max: float = 1520.0

## Vertical spawn position (local y under the Asteroids node).
@export var spawn_y: float = -80.0

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < spawn_interval:
		return
	_elapsed -= spawn_interval
	_spawn_asteroid()


func _spawn_asteroid() -> void:
	if asteroid_scene == null:
		return

	var container := _get_asteroids_container()
	if container == null:
		return

	var spawned := asteroid_scene.instantiate()
	if spawned is Node2D:
		container.add_child(spawned)
		var x := randf_range(spawn_x_min, spawn_x_max)
		spawned.position = Vector2(x, spawn_y)
	elif spawned is Node:
		spawned.queue_free()


func _get_asteroids_container() -> Node:
	return get_node_or_null("/root/Main/GameRoot/Asteroids")
