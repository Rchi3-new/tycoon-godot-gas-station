extends SceneTree
## One-shot authoring tool. Saves real editable TileMapLayer cells and a shared TileSet.
## Run after importing the PNG atlases:
## godot --headless --path . --script res://scripts/tools/build_survivors_arena.gd
## Optional user arguments: -- --columns=40 --rows=30 --cell-size=64 --seed=49028
## Regenerating replaces survivors_arena.tscn and survivors_street.tres.

const GROUND_PATH := "res://art/tilesets/survivors_ground.png"
const PROPS_PATH := "res://art/tilesets/survivors_props.png"
const TILESET_PATH := "res://resources/tilesets/survivors_street.tres"
const SCENE_PATH := "res://scenes/survivors_arena.tscn"
const PREVIEW_SCRIPT_PATH := "res://scripts/survivors_map_preview.gd"
const ATLAS_GRID := 4
const GROUND_SOURCE := 0
const PROPS_SOURCE := 1

const GROUND_NAMES := [
	"Asphalt", "Cracked asphalt", "Chipped asphalt", "Oil stain",
	"Pothole", "Puddle", "Autumn leaves", "Gravel",
	"Concrete paving", "Cracked paving", "Dirt and grit", "Muted grass",
	"Horizontal lane dash", "Vertical lane dash", "Crosswalk stripe", "Drain",
]
const PROP_NAMES := [
	"Concrete barrier horizontal", "Concrete barrier vertical", "Sandbags", "Crate stack",
	"Brick rubble", "Concrete rubble", "Rusty barrel", "Tire stack",
	"Wrecked compact car", "Damaged bus shelter", "Dead autumn tree", "Bush",
	"Kiosk roof", "Roof vent", "Streetlamp", "Broken pallet",
]

var columns := 40
var rows := 30
var world_cell_size := 64
var generation_seed := 49028
var native_cell_size := 256
var rng := RandomNumberGenerator.new()
var placed_props: Dictionary[Vector2i, bool] = {}
var reserved_prop_areas: Array[Rect2] = []


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	_read_arguments()
	var ground_texture := load(GROUND_PATH) as Texture2D
	var props_texture := load(PROPS_PATH) as Texture2D
	if not _validate_atlases(ground_texture, props_texture):
		quit(1)
		return
	rng.seed = generation_seed
	placed_props.clear()
	reserved_prop_areas.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/tilesets"))
	var tile_set := _make_tileset(ground_texture, props_texture)
	var error := ResourceSaver.save(tile_set, TILESET_PATH)
	if error != OK:
		push_error("Cannot save TileSet: %s" % error_string(error))
		quit(1)
		return
	# Loading the saved resource makes the scene reference the editable .tres on disk.
	tile_set = load(TILESET_PATH) as TileSet
	var arena := _make_arena(tile_set)
	var packed := PackedScene.new()
	error = packed.pack(arena)
	if error == OK:
		error = ResourceSaver.save(packed, SCENE_PATH)
	if error != OK:
		push_error("Cannot save arena scene: %s" % error_string(error))
		arena.free()
		quit(1)
		return
	print("Saved %s and %s" % [TILESET_PATH, SCENE_PATH])
	print("Arena: %dx%d cells; %d world px/cell; %d atlas px/cell; seed %d" % [columns, rows, world_cell_size, native_cell_size, generation_seed])
	print("Tiles: %d ground, %d detail, %d obstacle, %d landmark, %d foliage" % [arena.get_node("Ground").get_used_cells().size(), arena.get_node("Details").get_used_cells().size(), arena.get_node("Obstacles").get_used_cells().size(), arena.get_node("Landmarks").get_used_cells().size(), arena.get_node("Foliage").get_used_cells().size()])
	arena.free()
	quit(0)


func _read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--columns="):
			columns = clampi(argument.trim_prefix("--columns=").to_int(), 32, 96)
		elif argument.begins_with("--rows="):
			rows = clampi(argument.trim_prefix("--rows=").to_int(), 24, 72)
		elif argument.begins_with("--cell-size="):
			world_cell_size = clampi(argument.trim_prefix("--cell-size=").to_int(), 16, 128)
		elif argument.begins_with("--seed="):
			generation_seed = argument.trim_prefix("--seed=").to_int()


func _validate_atlases(ground: Texture2D, props: Texture2D) -> bool:
	if ground == null or props == null:
		push_error("Both PNG atlases must exist and be imported before building. Run Godot --headless --path . --import first.")
		return false
	var size := Vector2i(ground.get_size())
	if size.x != size.y or size.x % ATLAS_GRID != 0 or size.x < 64:
		push_error("Ground atlas must be square, at least 64px, and divisible into a 4x4 grid.")
		return false
	if Vector2i(props.get_size()) != size:
		push_error("Ground and prop atlases must have matching dimensions.")
		return false
	native_cell_size = size.x / ATLAS_GRID
	return true


func _make_tileset(ground_texture: Texture2D, props_texture: Texture2D) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.resource_name = "Post-Soviet Street / Survivors"
	tile_set.tile_size = Vector2i.ONE * native_cell_size
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "tile_name")
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(1, "blocks_movement")
	tile_set.set_custom_data_layer_type(1, TYPE_BOOL)
	_add_atlas(tile_set, ground_texture, GROUND_SOURCE, GROUND_NAMES)
	var props := _add_atlas(tile_set, props_texture, PROPS_SOURCE, PROP_NAMES)
	# Footprints are deliberately tighter than art; branches, shadows and rubble are passable.
	_add_box_collision(props, Vector2i(0, 0), Vector2(0.43, 0.19))
	_add_box_collision(props, Vector2i(1, 0), Vector2(0.19, 0.43))
	_add_box_collision(props, Vector2i(2, 0), Vector2(0.40, 0.23))
	_add_box_collision(props, Vector2i(3, 0), Vector2(0.30, 0.28))
	_add_box_collision(props, Vector2i(2, 1), Vector2(0.18, 0.18))
	_add_box_collision(props, Vector2i(3, 1), Vector2(0.24, 0.23))
	_add_box_collision(props, Vector2i(0, 2), Vector2(0.23, 0.42))
	_add_box_collision(props, Vector2i(1, 2), Vector2(0.40, 0.26))
	_add_box_collision(props, Vector2i(2, 2), Vector2(0.09, 0.09), Vector2(0.0, 0.11))
	_add_box_collision(props, Vector2i(0, 3), Vector2(0.39, 0.34))
	_add_box_collision(props, Vector2i(1, 3), Vector2(0.23, 0.23))
	_add_box_collision(props, Vector2i(2, 3), Vector2(0.07, 0.07), Vector2(0.0, 0.25))
	return tile_set


func _add_atlas(tile_set: TileSet, texture: Texture2D, source_id: int, names: Array) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.resource_name = "Ground" if source_id == GROUND_SOURCE else "Props and cover"
	source.texture = texture
	source.texture_region_size = Vector2i.ONE * native_cell_size
	source.use_texture_padding = true
	tile_set.add_source(source, source_id)
	for y in ATLAS_GRID:
		for x in ATLAS_GRID:
			var atlas_coords := Vector2i(x, y)
			source.create_tile(atlas_coords)
			var data := source.get_tile_data(atlas_coords, 0)
			data.set_custom_data("tile_name", names[y * ATLAS_GRID + x])
			data.set_custom_data("blocks_movement", false)
	return source


func _add_box_collision(source: TileSetAtlasSource, coords: Vector2i, half_extent: Vector2, offset := Vector2.ZERO) -> void:
	var tile := source.get_tile_data(coords, 0)
	var half := half_extent * native_cell_size
	var center := offset * native_cell_size
	tile.set_collision_polygons_count(0, 1)
	tile.set_collision_polygon_points(0, 0, PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	]))
	tile.set_custom_data("blocks_movement", true)


func _make_arena(tile_set: TileSet) -> Node2D:
	var arena := Node2D.new()
	arena.name = "SurvivorsArena"
	arena.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var map_size := Vector2(columns, rows) * world_cell_size
	if ResourceLoader.exists(PREVIEW_SCRIPT_PATH):
		arena.set_script(load(PREVIEW_SCRIPT_PATH))
		arena.set("map_size", map_size)
	arena.set_meta("grid_dimensions", Vector2i(columns, rows))
	arena.set_meta("world_cell_size", world_cell_size)
	arena.set_meta("generation_seed", generation_seed)
	arena.set_meta("description", "Editable survivors arena. Collision layer 1 = environment. PlayerSpawn is clear. Run this scene to inspect the map.")
	var ground := _make_layer(arena, tile_set, "Ground", 0)
	var details := _make_layer(arena, tile_set, "Details", 1)
	var obstacles := _make_layer(arena, tile_set, "Obstacles", 2)
	var landmarks := _make_layer(arena, tile_set, "Landmarks", 3, 3.0)
	var foliage := _make_layer(arena, tile_set, "Foliage", 4, 2.0)
	# Align the large-object grid with the sidewalk centers at x = 224 and 2336.
	landmarks.position.x = world_cell_size * 2.0
	ground.collision_enabled = false
	details.collision_enabled = false
	_paint_ground(ground, details)
	_paint_landmarks(landmarks)
	_paint_foliage(foliage)
	_paint_props(obstacles)
	_add_boundary(arena, map_size)
	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = map_size * 0.5
	spawn.gizmo_extents = 32.0
	_attach(arena, spawn, arena)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = map_size * 0.5
	var fit := minf(1180.0 / map_size.x, 660.0 / map_size.y)
	camera.zoom = Vector2.ONE * fit
	_attach(arena, camera, arena)
	return arena


func _make_layer(arena: Node2D, tile_set: TileSet, layer_name: String, depth: int, size_multiplier := 1.0) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.scale = Vector2.ONE * float(world_cell_size) / native_cell_size * size_multiplier
	layer.z_index = depth
	layer.navigation_enabled = false
	layer.set_meta("world_cell_size", world_cell_size * size_multiplier)
	_attach(arena, layer, arena)
	return layer


func _paint_ground(ground: TileMapLayer, details: TileMapLayer) -> void:
	for y in rows:
		for x in columns:
			var cell := Vector2i(x, y)
			var edge_distance := mini(mini(x, columns - x - 1), mini(y, rows - y - 1))
			var tile := Vector2i.ZERO
			if edge_distance < 2:
				tile = Vector2i(3, 2) if rng.randf() < 0.65 else Vector2i(2, 2)
			elif edge_distance < 5:
				tile = Vector2i(0, 2) if rng.randf() < 0.84 else Vector2i(1, 2)
			else:
				var roll := rng.randf()
				if roll > 0.92:
					tile = Vector2i(2, 0)
				elif roll > 0.77:
					tile = Vector2i(1, 0)
			ground.set_cell(cell, GROUND_SOURCE, tile)
	# Wear and debris are individually erasable on the Details layer.
	for index in (columns * rows) / 32:
		var cell := Vector2i(rng.randi_range(5, columns - 6), rng.randi_range(5, rows - 6))
		if Vector2(cell).distance_to(Vector2(columns, rows) * 0.5) > 3.0:
			var candidates := [Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
			details.set_cell(cell, GROUND_SOURCE, candidates[index % candidates.size()])
	var middle_y := rows / 2
	for x in range(7, columns - 7, 3):
		details.set_cell(Vector2i(x, middle_y - 4), GROUND_SOURCE, Vector2i(0, 3))
		details.set_cell(Vector2i(x, middle_y + 4), GROUND_SOURCE, Vector2i(0, 3))
	for y in range(middle_y - 3, middle_y + 4, 2):
		for x in [6, 7, columns - 8, columns - 7]:
			details.set_cell(Vector2i(x, y), GROUND_SOURCE, Vector2i(2, 3))
	for cell in [Vector2i(10, 6), Vector2i(columns - 11, rows - 7), Vector2i(5, middle_y), Vector2i(columns - 6, middle_y)]:
		details.set_cell(cell, GROUND_SOURCE, Vector2i(3, 3))


func _paint_props(obstacles: TileMapLayer) -> void:
	# Four cover islands leave the central court and cardinal escape routes open.
	for anchor in [Vector2i(10, 8), Vector2i(columns - 13, 8), Vector2i(10, rows - 9), Vector2i(columns - 13, rows - 9)]:
		_place_prop(obstacles, anchor, Vector2i(0, 0))
		_place_prop(obstacles, anchor + Vector2i(1, 0), Vector2i(0, 0))
		_place_prop(obstacles, anchor + Vector2i(0, 2), Vector2i(3, 0))
		_place_prop(obstacles, anchor + Vector2i(2, 1), Vector2i(2, 1))
		_place_prop(obstacles, anchor + Vector2i(-1, -1), Vector2i(0, 1))
	# Small street furniture shares the ground grid. Vehicles and vegetation use
	# their own larger editable grids so their silhouettes read at gameplay scale.
	for x in [3, columns - 4]:
		_place_prop(obstacles, Vector2i(x, 11), Vector2i(2, 3))
		_place_prop(obstacles, Vector2i(x, rows - 12), Vector2i(2, 3))
	for index in (columns * rows) / 36:
		var cell := Vector2i(rng.randi_range(5, columns - 6), rng.randi_range(5, rows - 6))
		var decoration := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(3, 3)]
		_place_prop(obstacles, cell, decoration[index % decoration.size()])


func _paint_landmarks(layer: TileMapLayer) -> void:
	# Every sprite occupies a 3x3 ground-cell area: 192px at the default scale.
	for y in [7.5, rows - 7.5]:
		var sidewalk_tile := Vector2i(0, 3) if y < rows * 0.5 else Vector2i(1, 2)
		_place_scaled_prop(layer, Vector2(3.5, y) * world_cell_size, sidewalk_tile)
		_place_scaled_prop(layer, Vector2(columns - 3.5, y) * world_cell_size, sidewalk_tile)
		_place_scaled_prop(layer, Vector2(6.5, y) * world_cell_size, Vector2i(0, 2))
		_place_scaled_prop(layer, Vector2(columns - 6.5, y) * world_cell_size, Vector2i(0, 2))


func _paint_foliage(layer: TileMapLayer) -> void:
	# Trees and bushes occupy a 2x2 ground-cell area while retaining small trunk
	# collision footprints. Leave generous gaps where the cardinal routes exit.
	for x in range(1, columns / 2, 3):
		_place_scaled_prop(layer, Vector2(x * 2 + 1, 1) * world_cell_size, Vector2i(2, 2))
		_place_scaled_prop(layer, Vector2(x * 2 + 1, rows - 1) * world_cell_size, Vector2i(3, 2))
	for y in range(2, rows / 2 - 1, 3):
		_place_scaled_prop(layer, Vector2(1, y * 2 + 1) * world_cell_size, Vector2i(3, 2))
		_place_scaled_prop(layer, Vector2(columns - 1, y * 2 + 1) * world_cell_size, Vector2i(2, 2))


func _place_scaled_prop(layer: TileMapLayer, target: Vector2, atlas: Vector2i) -> void:
	var cell := layer.local_to_map(layer.transform.affine_inverse() * target)
	var center := layer.transform * layer.map_to_local(cell)
	var size := Vector2(layer.tile_set.tile_size) * layer.scale
	var bounds := Rect2(center - size * 0.5, size)
	var map_size := Vector2(columns, rows) * world_cell_size
	if not Rect2(Vector2.ZERO, map_size).encloses(bounds):
		return
	var relative := center - map_size * 0.5
	var corridor_margin := world_cell_size * 2.0 + size.x * 0.5
	if absf(relative.x) < corridor_margin or absf(relative.y) < corridor_margin:
		return
	layer.set_cell(cell, PROPS_SOURCE, atlas)
	reserved_prop_areas.append(bounds.grow(world_cell_size * 0.125))


func _place_prop(obstacles: TileMapLayer, cell: Vector2i, atlas: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows or placed_props.has(cell):
		return
	var relative := Vector2(cell) + Vector2.ONE * 0.5 - Vector2(columns, rows) * 0.5
	if absf(relative.x) < 2.0 or absf(relative.y) < 2.0 or relative.length() < 5.0:
		return
	var center := (Vector2(cell) + Vector2.ONE * 0.5) * world_cell_size
	for area in reserved_prop_areas:
		if area.has_point(center):
			return
	obstacles.set_cell(cell, PROPS_SOURCE, atlas)
	placed_props[cell] = true


func _add_boundary(arena: Node2D, map_size: Vector2) -> void:
	var boundary := StaticBody2D.new()
	boundary.name = "MapBoundary"
	boundary.collision_layer = 1
	boundary.collision_mask = 0
	_attach(arena, boundary, arena)
	var thickness := float(world_cell_size)
	var edges := [
		["North", Vector2(map_size.x * 0.5, -thickness * 0.5), Vector2(map_size.x + thickness * 2.0, thickness)],
		["South", Vector2(map_size.x * 0.5, map_size.y + thickness * 0.5), Vector2(map_size.x + thickness * 2.0, thickness)],
		["West", Vector2(-thickness * 0.5, map_size.y * 0.5), Vector2(thickness, map_size.y)],
		["East", Vector2(map_size.x + thickness * 0.5, map_size.y * 0.5), Vector2(thickness, map_size.y)],
	]
	for edge in edges:
		var shape := CollisionShape2D.new()
		shape.name = edge[0]
		shape.position = edge[1]
		var rectangle := RectangleShape2D.new()
		rectangle.size = edge[2]
		shape.shape = rectangle
		_attach(boundary, shape, arena)


func _attach(parent: Node, child: Node, scene_owner: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner
