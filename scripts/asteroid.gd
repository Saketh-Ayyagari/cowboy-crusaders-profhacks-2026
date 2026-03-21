extends Area2D

## How fast the asteroid falls downward (pixels per second).
@export var fall_speed: float = 250.0


func _process(delta: float) -> void:
	position.y += fall_speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
