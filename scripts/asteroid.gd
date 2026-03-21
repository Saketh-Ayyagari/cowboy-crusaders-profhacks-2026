extends Area2D

## How fast the asteroid falls downward (pixels per second).
@export var fall_speed: float = 250.0

var _hit_player: bool = false


func _ready() -> void:
	add_to_group("asteroids")


func _process(delta: float) -> void:
	position.y += fall_speed * delta


func _on_body_entered(body: Node2D) -> void:
	if _hit_player:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("player"):
		return
	_hit_player = true
	if body.has_method("take_damage"):
		body.call("take_damage", 1)
	queue_free()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
