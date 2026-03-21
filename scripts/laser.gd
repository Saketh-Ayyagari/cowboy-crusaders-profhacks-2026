extends Area2D

## How fast the laser travels upward (pixels per second).
@export var speed: float = 700.0


func _process(delta: float) -> void:
	position.y -= speed * delta


func _on_area_entered(area: Area2D) -> void:
	if area == null or not is_instance_valid(area):
		return
	if not area.is_in_group("asteroids"):
		return
	if is_instance_valid(area):
		area.queue_free()
	if is_instance_valid(self):
		queue_free()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
