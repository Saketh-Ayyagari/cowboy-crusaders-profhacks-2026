extends Node2D

## Subtle downward scroll speed for the starfield (pixels per second).
const BG_SCROLL_SPEED: float = 38.0

## Right-panel debug webcam (TextureRect under CameraPlaceholder).
@onready var _camera_feed: TextureRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraFeed
@onready var _camera_placeholder_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraPlaceholderLabel

@onready var _bg1: Sprite2D = $GameRoot/World/Background
@onready var _bg2: Sprite2D = $GameRoot/World/Background2

var _logged_no_feed_yet: bool = false
var _bg_tile_height: float = 0.0
var _bg_scroll: float = 0.0
var _bg_base_x: float = 400.0
var _bg_base_y: float = 450.0


func _ready() -> void:
	_setup_background_parallax()
	_start_debug_webcam_if_available()


func _setup_background_parallax() -> void:
	if _bg1 == null or _bg2 == null:
		return
	var tex_h := float(_bg1.texture.get_height()) * _bg1.scale.y
	_bg_tile_height = tex_h
	_bg_base_x = _bg1.position.x
	_bg_base_y = _bg1.position.y
	_bg_scroll = 0.0
	_bg2.texture = _bg1.texture
	_bg2.scale = _bg1.scale
	_bg2.z_index = _bg1.z_index
	_apply_background_positions()


func _apply_background_positions() -> void:
	var h := _bg_tile_height
	if h <= 0.0:
		return
	var o := fposmod(_bg_scroll, h)
	_bg1.position = Vector2(_bg_base_x, _bg_base_y + o)
	_bg2.position = Vector2(_bg_base_x, _bg_base_y - h + o)


func _process(delta: float) -> void:
	_scroll_backgrounds(delta)


func _scroll_backgrounds(delta: float) -> void:
	if _bg1 == null or _bg2 == null:
		return
	if _bg_tile_height <= 0.0:
		return
	_bg_scroll += BG_SCROLL_SPEED * delta
	_apply_background_positions()


func _start_debug_webcam_if_available() -> void:
	if _camera_feed == null:
		print("Webcam debug: CameraFeed node not found.")
		return

	_camera_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_feed.modulate = Color.WHITE
	_camera_feed.self_modulate = Color.WHITE

	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)

	CameraServer.monitoring_feeds = true
	print("Webcam debug: Monitoring enabled; looking for a camera…")

	call_deferred("_try_assign_first_camera_feed")


func _on_camera_feeds_updated() -> void:
	_try_assign_first_camera_feed()


func _try_assign_first_camera_feed() -> void:
	if _camera_feed == null:
		return
	if _camera_feed.texture != null:
		return

	var count := CameraServer.get_feed_count()
	if count == 0:
		if not _logged_no_feed_yet:
			print("Webcam debug: No camera feed found (not supported or permission denied).")
			_logged_no_feed_yet = true
		return

	var feed := CameraServer.get_feed(0)
	if feed == null:
		print("Webcam debug: get_feed(0) returned null.")
		return

	# Prefer the decoded RGBA image plane (avoids wrong Y/CbCr plane = odd color tint on some cameras).
	var formats: Array = feed.get_formats()
	if formats.size() > 0:
		feed.set_format(0, {})

	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = feed.get_id()
	cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	cam_tex.camera_is_active = true

	_camera_feed.modulate = Color.WHITE
	_camera_feed.self_modulate = Color.WHITE
	_camera_feed.texture = cam_tex

	if is_instance_valid(_camera_placeholder_label):
		_camera_placeholder_label.visible = false

	print(
		"Webcam debug: Cleaner camera texture path used (FEED_RGBA_IMAGE + white modulate). Feed '%s' id=%d."
		% [feed.get_name(), feed.get_id()]
	)
