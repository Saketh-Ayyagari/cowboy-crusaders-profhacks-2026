extends Area2D

## How fast the laser travels upward (pixels per second).
@export var speed: float = 700.0


func _process(delta: float) -> void:
	position.y -= speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
