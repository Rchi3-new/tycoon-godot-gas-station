extends SceneTree
## Saves PNG previews of the endless city from the real main scene: the spawn at
## gameplay zoom, a zoomed-out overview, and a gameplay view far from the spawn.
## Needs a display, so do not pass --headless:
## godot --path . --script res://scripts/tools/capture_endless_city.gd -- --out=C:/absolute/folder

const MAIN_SCENE := "res://scenes/main.tscn"
## Chunk offset of the far view, to show that the city keeps going.
const FAR_CHUNKS := Vector2(9, -6)


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if not out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("Run with a display and pass -- --out=<absolute folder>.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var city := main.get_node("World/EndlessCity") as EndlessCity
	var player := main.get_node("World/Player") as Node2D
	var camera := player.get_node("Camera2D") as Camera2D
	await _save(city, out.path_join("spawn.png"))
	camera.zoom = Vector2.ONE * 0.25
	await _save(city, out.path_join("overview.png"))
	player.position += FAR_CHUNKS * EndlessCity.CHUNK_SIZE
	camera.zoom = Vector2.ONE
	await _save(city, out.path_join("far.png"))
	quit(0)


func _save(city: EndlessCity, path: String) -> void:
	# Let the camera move first, then build everything it sees before drawing.
	await process_frame
	city.stream_all()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
	else:
		print("Saved %s" % path)
