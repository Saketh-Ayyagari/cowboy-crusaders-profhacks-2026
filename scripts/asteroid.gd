extends Area2D

## How fast the asteroid falls downward (pixels per second).
@export var fall_speed: float = 250.0

## True for orange `asteroid2.png` (faster rock + higher score when lasered).
var is_fast_variant: bool = false

var _hit_player: bool = false
var _award_destroy_bonus: bool = true


func _ready() -> void:
	add_to_group("asteroids")


## Sets sprite texture and multiplies fall speed (spawn manager sets speed before this).
func setup_variant(
	texture: Texture2D, speed_multiplier: float = 1.0, orange_rock: bool = false
) -> void:
	is_fast_variant = orange_rock
	if texture != null:
		var sprite := $AsteroidSprite as Sprite2D
		if sprite:
			sprite.texture = texture
	fall_speed *= speed_multiplier


func _exit_tree() -> void:
	if not _award_destroy_bonus:
		return
	var tr := get_tree()
	if tr == null:
		return
	var main := tr.root.get_node_or_null("Main")
	if main == null or not main.has_method("on_asteroid_destroyed"):
		return
	var sid: int = int(get_meta("score_session_id", -1))
	main.on_asteroid_destroyed(is_fast_variant, sid)


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
	_award_destroy_bonus = false
	if body.has_method("take_damage"):
		body.call("take_damage", 1)
	queue_free()


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	_award_destroy_bonus = false
	queue_free()
