extends Node2D

## Right-panel debug webcam (TextureRect under CameraPlaceholder).
@onready var _camera_feed: TextureRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraFeed
@onready var _camera_placeholder_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraPlaceholderLabel

var _logged_no_feed_yet: bool = false


func _ready() -> void:
	_start_debug_webcam_if_available()


func _start_debug_webcam_if_available() -> void:
	if _camera_feed == null:
		print("Webcam debug: CameraFeed node not found.")
		return

	_camera_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

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

	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = feed.get_id()
	cam_tex.camera_is_active = true
	_camera_feed.texture = cam_tex

	if is_instance_valid(_camera_placeholder_label):
		_camera_placeholder_label.visible = false

	print("Webcam debug: Camera feed found — assigned OK ('%s', id=%d)." % [feed.get_name(), feed.get_id()])
