extends Node2D
## Camera controls for inspecting the standalone Survivors arena tilemap.

@export var map_size: Vector2 = Vector2(2560.0, 1920.0)
@export var pan_speed: float = 700.0
@export var minimum_zoom: float = 0.15
@export var maximum_zoom: float = 2.0

@onready var _camera: Camera2D = $Camera2D

var _help: PanelContainer
var _dragging: bool = false
var _fitted: bool = true


func _ready() -> void:
	set_process(not Engine.is_editor_hint())
	set_process_input(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	_camera.enabled = true
	_camera.position_smoothing_enabled = false
	_create_help()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_fit_map()
	var capture_path: String = _capture_argument()
	if not capture_path.is_empty():
		_capture_map(capture_path)


func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if not direction.is_zero_approx():
		_fitted = false
		_camera.position += direction.normalized() * pan_speed * delta / _camera.zoom.x
		_clamp_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			_fit_map()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			_help.visible = not _help.visible
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.15)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.15)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_fitted = false
		_camera.position -= event.relative / _camera.zoom.x
		_clamp_camera()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false


func _fit_map() -> void:
	var available: Vector2 = get_viewport_rect().size - Vector2(48.0, 48.0)
	var fit_zoom: float = minf(available.x / map_size.x, available.y / map_size.y)
	_camera.zoom = Vector2.ONE * clampf(fit_zoom, minimum_zoom, maximum_zoom)
	_camera.position = map_size * 0.5
	_camera.force_update_scroll()
	_fitted = true


func _zoom_at(screen_position: Vector2, multiplier: float) -> void:
	var old_zoom: float = _camera.zoom.x
	var new_zoom: float = clampf(old_zoom * multiplier, minimum_zoom, maximum_zoom)
	var from_center: Vector2 = screen_position - get_viewport_rect().size * 0.5
	_camera.position += from_center * (1.0 / old_zoom - 1.0 / new_zoom)
	_camera.zoom = Vector2.ONE * new_zoom
	_fitted = false
	_clamp_camera()
	_camera.force_update_scroll()


func _clamp_camera() -> void:
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / _camera.zoom.x
	for axis in range(2):
		if half_view[axis] * 2.0 >= map_size[axis]:
			_camera.position[axis] = map_size[axis] * 0.5
		else:
			_camera.position[axis] = clampf(
				_camera.position[axis], half_view[axis], map_size[axis] - half_view[axis]
			)


func _on_viewport_resized() -> void:
	if _fitted:
		_fit_map()
	else:
		_clamp_camera()


func _create_help() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "PreviewHelp"
	add_child(overlay)
	_help = PanelContainer.new()
	_help.position = Vector2(16.0, 16.0)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.05, 0.06, 0.9)
	background.content_margin_left = 12.0
	background.content_margin_right = 12.0
	background.content_margin_top = 9.0
	background.content_margin_bottom = 9.0
	_help.add_theme_stylebox_override("panel", background)
	overlay.add_child(_help)
	var label := Label.new()
	label.text = "ARENA MAP  |  CAMERA PREVIEW\nWASD / arrows / middle drag: pan   Wheel: zoom\nHome: fit map   H: toggle help"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(label)


func _capture_argument() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-map="):
			return argument.trim_prefix("--capture-map=")
	return ""


func _capture_map(path: String) -> void:
	set_process(false)
	set_process_input(false)
	_help.hide()
	if DisplayServer.get_name() == "headless":
		push_error("Map capture requires a real graphics display; do not use --headless.")
		get_tree().quit(1)
		return
	if not path.is_absolute_path():
		push_error("--capture-map requires an absolute output path.")
		get_tree().quit(1)
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		push_error("Unable to create map capture directory: %s" % error_string(directory_error))
		get_tree().quit(1)
		return
	for frame in range(4):
		await get_tree().process_frame
	# Hidden preview windows may skip their regular draw; render once for the PNG.
	RenderingServer.force_draw(false)
	var captured_image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = captured_image.save_png(path)
	if save_error != OK:
		push_error("Unable to save map capture: %s" % error_string(save_error))
		get_tree().quit(1)
		return
	print("Map capture saved: %s" % path)
	get_tree().quit()
