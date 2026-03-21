extends Control

## Purely visual guides over the webcam preview (pose calibration / lean zones).
## Toggle on the WebcamDebugGuidesOverlay node in `main.tscn` → Inspector.
@export var show_pose_calibration_guides: bool = false:
	set(value):
		if show_pose_calibration_guides == value:
			return
		show_pose_calibration_guides = value
		visible = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	visible = show_pose_calibration_guides
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func _on_resized() -> void:
	queue_redraw()


func _draw() -> void:
	if not show_pose_calibration_guides:
		return
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return

	var x_third := w / 3.0
	var cx := w * 0.5
	var hy := h * 0.5

	var lw_zone := clampf(w * 0.002, 1.0, 2.0)
	var zone_col := Color(0.92, 0.86, 0.28, 0.78)
	draw_line(Vector2(x_third, 0.0), Vector2(x_third, h), zone_col, lw_zone, true)
	draw_line(Vector2(x_third * 2.0, 0.0), Vector2(x_third * 2.0, h), zone_col, lw_zone, true)

	var lw_center := clampf(w * 0.0025, 1.5, 3.0)
	draw_line(Vector2(cx, 0.0), Vector2(cx, h), Color(0.98, 0.22, 0.22, 0.9), lw_center, true)

	var lw_h := clampf(h * 0.0018, 1.0, 1.75)
	var h_col := Color(0.5, 0.82, 1.0, 0.38)
	draw_line(Vector2(0.0, hy), Vector2(w, hy), h_col, lw_h, true)
