extends Node2D

## Subtle downward scroll speed for the starfield (pixels per second).
const BG_SCROLL_SPEED: float = 38.0

const _HEART_FULL := preload("res://assets/art/heart_full.png")
const _HEART_2_3 := preload("res://assets/art/heart_2_3.png")
const _HEART_1_3 := preload("res://assets/art/heart_1_3.png")
const _HEART_EMPTY := preload("res://assets/art/heart_empty.png")

## If >= 0, use this CameraServer index (Inspector override). -1 = auto-pick OBS Virtual Camera when present.
@export var force_camera_feed_index: int = -1

## Prefer capture formats that usually decode to clean full-color in Godot (order matters).
const _WEBCAM_FORMAT_PRIORITY: PackedStringArray = [
	"MJPEG", "JPEG", "RGB", "BGR", "BGRA", "ARGB", "RGBA",
	"yuvs", "420v", "420f", "YUY2", "NV12", "UYVY",
]

## Right-panel debug webcam (TextureRect under CameraPlaceholder).
@onready var _camera_feed: TextureRect = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraFeed
@onready var _camera_placeholder_label: Label = $UILayer/HUD/RootLayout/MainSplit/CameraPanel/CameraPlaceholder/CameraPlaceholderLabel

@onready var _bg1: Sprite2D = $GameRoot/World/Background
@onready var _bg2: Sprite2D = $GameRoot/World/Background2

@onready var _heart1: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart1
@onready var _heart2: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart2
@onready var _heart3: TextureRect = $UILayer/HUD/RootLayout/MainSplit/GamePanel/HeartsUI/Heart3
@onready var _player_ship: Node = $GameRoot/Player/PlayerShip

var _logged_no_feed_yet: bool = false
var _webcam_setup_in_progress: bool = false
var _bg_tile_height: float = 0.0
var _bg_scroll: float = 0.0
var _bg_base_x: float = 400.0
var _bg_base_y: float = 450.0


func _ready() -> void:
	_setup_background_parallax()
	_setup_hearts_ui()
	_start_debug_webcam_if_available()


func _setup_hearts_ui() -> void:
	if _heart1 == null or _heart2 == null or _heart3 == null:
		return
	if _player_ship == null or not is_instance_valid(_player_ship):
		return
	if not _player_ship.has_signal("health_changed"):
		return
	if not _player_ship.health_changed.is_connected(_on_player_health_changed):
		_player_ship.health_changed.connect(_on_player_health_changed)
	_on_player_health_changed(_player_ship.current_health, _player_ship.max_health)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_refresh_hearts_display(current, maximum)


func _refresh_hearts_display(current_health: int, max_health: int) -> void:
	if not is_instance_valid(_heart1) or not is_instance_valid(_heart2) or not is_instance_valid(_heart3):
		return
	var hp := clampi(current_health, 0, max_health)
	var mx := maxi(1, max_health)
	# Map any max_health onto 0–3 heart steps, then same art as max 3.
	var steps := 3
	var filled := int(round((float(hp) / float(mx)) * float(steps)))
	filled = clampi(filled, 0, steps)
	match filled:
		3:
			_apply_heart_row(_HEART_FULL, _HEART_FULL, _HEART_FULL)
		2:
			_apply_heart_row(_HEART_FULL, _HEART_FULL, _HEART_2_3)
		1:
			_apply_heart_row(_HEART_FULL, _HEART_1_3, _HEART_EMPTY)
		_:
			_apply_heart_row(_HEART_EMPTY, _HEART_EMPTY, _HEART_EMPTY)


func _apply_heart_row(t1: Texture2D, t2: Texture2D, t3: Texture2D) -> void:
	_heart1.texture = t1
	_heart2.texture = t2
	_heart3.texture = t3


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
	_camera_feed.material = null
	_camera_feed.use_parent_material = false

	if not CameraServer.camera_feeds_updated.is_connected(_on_camera_feeds_updated):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)

	CameraServer.monitoring_feeds = true
	print("Webcam debug: Monitoring enabled; looking for a camera…")

	call_deferred("_try_assign_first_camera_feed")


func _on_camera_feeds_updated() -> void:
	_try_assign_first_camera_feed()


func _datatype_to_string(dt: int) -> String:
	match dt:
		CameraFeed.FEED_NOIMAGE:
			return "FEED_NOIMAGE"
		CameraFeed.FEED_RGB:
			return "FEED_RGB"
		CameraFeed.FEED_YCBCR:
			return "FEED_YCBCR"
		CameraFeed.FEED_YCBCR_SEP:
			return "FEED_YCBCR_SEP"
		CameraFeed.FEED_EXTERNAL:
			return "FEED_EXTERNAL"
		_:
			return "unknown(%d)" % dt


func _resolve_webcam_feed_index() -> int:
	var count := CameraServer.get_feed_count()
	if count <= 0:
		return 0
	if force_camera_feed_index >= 0:
		if force_camera_feed_index < count:
			var forced := CameraServer.get_feed(force_camera_feed_index)
			var forced_name := forced.get_name() if forced else "?"
			print("Webcam debug: Using force_camera_feed_index = %d ('%s')" % [force_camera_feed_index, forced_name])
			return force_camera_feed_index
		push_warning(
			"Webcam debug: force_camera_feed_index=%d out of range (count=%d); falling back to auto."
			% [force_camera_feed_index, count]
		)
	# Prefer OBS Virtual Camera (correct colors on Mac vs built-in camera Godot bug).
	for i in range(count):
		var f := CameraServer.get_feed(i)
		if f == null:
			continue
		var name_u := f.get_name().to_upper()
		if "OBS" in name_u or "VIRTUAL CAMERA" in name_u:
			print("Webcam debug: Using OBS / virtual camera — index %d, '%s'" % [i, f.get_name()])
			return i
	var fallback := CameraServer.get_feed(0)
	var fb_name := fallback.get_name() if fallback else "?"
	print("Webcam debug: No OBS Virtual Camera in feed list; using index 0 ('%s')." % fb_name)
	return 0


func _pick_preferred_format_index(formats: Array) -> int:
	if formats.is_empty():
		return 0
	for key in _WEBCAM_FORMAT_PRIORITY:
		var ku := key.to_upper()
		for i in range(formats.size()):
			var entry: Variant = formats[i]
			var haystack := str(entry).to_upper()
			if ku in haystack:
				return i
	return 0


func _ordered_format_indices(n: int, preferred: int) -> Array[int]:
	var out: Array[int] = []
	var used: Dictionary = {}
	if preferred >= 0 and preferred < n:
		out.append(preferred)
		used[preferred] = true
	for i in range(n):
		if not used.has(i):
			out.append(i)
	return out


func _await_feed_datatype(feed: CameraFeed) -> int:
	# macOS / some drivers update get_datatype() a frame or two after set_format.
	await get_tree().process_frame
	await get_tree().process_frame
	return feed.get_datatype()


func _try_set_format_and_probe(feed: CameraFeed, index: int, params: Dictionary) -> int:
	feed.feed_is_active = false
	var ok: bool = feed.set_format(index, params)
	if not ok:
		print("Webcam debug: set_format(%d, %s) returned false" % [index, params])
	feed.feed_is_active = true
	await get_tree().process_frame
	var dt: int = await _await_feed_datatype(feed)
	print(
		"Webcam debug: probe format index=%d params=%s -> datatype=%s"
		% [index, params, _datatype_to_string(dt)]
	)
	return dt


func _configure_camera_feed_for_display(feed: CameraFeed) -> String:
	var formats: Array = feed.get_formats()
	var n: int = formats.size()
	print("Webcam debug: %d format(s) reported for this device." % n)
	for i in range(n):
		print("Webcam debug:   format[%d] = %s" % [i, formats[i]])

	if n == 0:
		print("Webcam debug: No format list — using engine default (no set_format).")
		return "no_formats_default"

	var preferred: int = _pick_preferred_format_index(formats)
	var order: Array[int] = _ordered_format_indices(n, preferred)

	# Pass 1: normal set_format — look for true RGB pipeline (best for correct color).
	for idx in order:
		var dt := await _try_set_format_and_probe(feed, idx, {})
		if dt == CameraFeed.FEED_RGB:
			print("Webcam debug: COLOR PATH = native_rgb (format index %d)" % idx)
			return "native_rgb"

	# Pass 2: Godot docs — "grayscale" output forces a decoded FEED_RGB path (fixes YUV shown as wrong RGB / red cast).
	print("Webcam debug: No native FEED_RGB found; trying grayscale decode pass…")
	for idx in order:
		var dt2 := await _try_set_format_and_probe(feed, idx, {"output": "grayscale"})
		if dt2 == CameraFeed.FEED_RGB:
			print(
				"Webcam debug: COLOR PATH = grayscale_decode (format index %d) — grayscale image, but no false color tint."
				% idx
			)
			return "grayscale_decode"

	# Last resort: preferred index, default params
	print("Webcam debug: COLOR PATH = fallback_preferred_empty — tint may be driver/YUV related.")
	feed.feed_is_active = false
	feed.set_format(preferred, {})
	feed.feed_is_active = true
	await get_tree().process_frame
	return "fallback_preferred_empty"


func _finish_webcam_texture_bind(feed: CameraFeed, color_path: String) -> void:
	var cam_tex := CameraTexture.new()
	cam_tex.camera_feed_id = feed.get_id()
	cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
	cam_tex.camera_is_active = true

	_camera_feed.material = null
	_camera_feed.modulate = Color.WHITE
	_camera_feed.self_modulate = Color.WHITE
	_camera_feed.texture = cam_tex

	if is_instance_valid(_camera_placeholder_label):
		_camera_placeholder_label.visible = false

	var dt: int = feed.get_datatype()
	print("Webcam debug: feed_is_active = %s" % feed.feed_is_active)
	print("Webcam debug: cam_tex.camera_is_active = %s" % cam_tex.camera_is_active)
	print(
		"Webcam debug: Assigned %s (camera_feed_id=%d, which_feed=FEED_RGBA_IMAGE/0)"
		% [cam_tex, cam_tex.camera_feed_id]
	)
	print("Webcam debug: final get_datatype() = %s" % _datatype_to_string(dt))
	print("Webcam debug: color_path = %s" % color_path)

	if color_path == "grayscale_decode":
		print(
			"Webcam debug: NOTE — Using grayscale decode so YUV is not mis-read as RGB (removes red cast; no chroma)."
		)
	elif color_path == "fallback_preferred_empty" or dt != CameraFeed.FEED_RGB:
		print(
			"Webcam debug: NOTE — If the feed is still tinted, the OS is likely handing Godot a YUV layout this build mishandles; try another camera app or a Godot engine update."
		)


func _run_webcam_setup_async(feed: CameraFeed) -> void:
	var path := await _configure_camera_feed_for_display(feed)
	_finish_webcam_texture_bind(feed, path)
	_webcam_setup_in_progress = false


func _try_assign_first_camera_feed() -> void:
	if _camera_feed == null:
		return
	if _camera_feed.texture != null:
		return
	if _webcam_setup_in_progress:
		return

	var count := CameraServer.get_feed_count()
	print("Webcam debug: CameraServer.get_feed_count() = %d" % count)

	if count == 0:
		if not _logged_no_feed_yet:
			print("Webcam debug: No camera feed found (not supported or permission denied).")
			_logged_no_feed_yet = true
		return

	var feed_index := _resolve_webcam_feed_index()
	var feed := CameraServer.get_feed(feed_index)
	if feed == null:
		print("Webcam debug: get_feed(%d) returned null." % feed_index)
		return

	print(
		"Webcam debug: Using feed index %d — name '%s', id=%d"
		% [feed_index, feed.get_name(), feed.get_id()]
	)

	_webcam_setup_in_progress = true
	_run_webcam_setup_async(feed)
