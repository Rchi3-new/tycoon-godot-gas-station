extends SceneTree
## Authoring tool for modular street scenes and native TileMapPattern resources.
## Run after importing city_*.png and building survivors_street.tres.
## godot --headless --path . --script res://scripts/tools/build_city_patterns.gd
## Replaces only the city TileSet, city patterns and city showcase.

const BASE_TILESET := "res://resources/tilesets/survivors_street.tres"
const CITY_TILESET := "res://resources/tilesets/survivors_city.tres"
const SHOWCASE := "res://scenes/city_patterns_showcase.tscn"
const PREVIEW_SCRIPT := "res://scripts/survivors_map_preview.gd"
const GRID := Vector2i(12, 12)
const CELL_SIZE := 64
const CONNECTORS: Array[Vector2i] = [
	Vector2i(5, 0), Vector2i(6, 0), Vector2i(5, 11), Vector2i(6, 11),
	Vector2i(0, 5), Vector2i(0, 6), Vector2i(11, 5), Vector2i(11, 6),
]
const IDS := ["apartment_courtyard", "trolleybus_stop", "market_corner", "city_entrance", "roadside_checkpoint", "playground"]
const TITLES := ["01  APARTMENT COURTYARD", "02  TROLLEYBUS STOP", "03  MARKET CORNER", "04  CITY ENTRANCE", "05  ROADSIDE CHECKPOINT", "06  PLAYGROUND"]
const STREET_NAMES := [
	"Bench", "Dumpster", "Mailbox", "Payphone",
	"Bicycle rack", "Tire planter", "Fruit stand", "Plastic crates",
	"Broken swing", "Sandbox", "Iron fence horizontal", "Iron fence corner",
	"Electrical cabinet", "Trolley wire pole", "Laundry line", "Newspaper and bottle litter",
]
const SIGN_NAMES := [
	"City entry MIRNYY", "City exit MIRNYY", "Direction CENTRE right", "Direction STATION left",
	"Grocer fascia", "Pharmacy fascia", "Repair fascia", "Bus stop sign",
	"Pedestrian crossing sign", "Parking sign", "Stop sign", "Speed limit 40",
	"Keep right sign", "Mira street plaque", "Notice board", "Weathered blue billboard",
]
const ARCHITECTURE_NAMES := ["Panel apartment block", "Shell-damaged apartment block", "Small grocer", "Garage pair"]
const TRANSIT_NAMES := ["Blue-white trolleybus", "Rusty yellow tram", "Long bus shelter", "Overhead trolley wires"]

var failed := false


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	for directory in ["res://scenes/patterns", "res://resources/patterns", "res://resources/tilesets"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var base := load(BASE_TILESET) as TileSet
	if base == null or base.tile_size != Vector2i.ONE * CELL_SIZE:
		push_error("Build the base street TileSet with imported 64px cells first.")
		quit(1)
		return
	var tile_set := base.duplicate(true) as TileSet
	tile_set.resource_name = "Post-Soviet City / Modular Patterns"
	var street := _add_atlas(tile_set, 2, "city_streetlife", 4, 64, STREET_NAMES)
	var signs := _add_atlas(tile_set, 3, "city_signs", 4, 128, SIGN_NAMES)
	var architecture := _add_atlas(tile_set, 4, "city_architecture", 2, 256, ARCHITECTURE_NAMES)
	var transit := _add_atlas(tile_set, 5, "city_transit", 2, 256, TRANSIT_NAMES)
	if failed:
		quit(1)
		return
	_configure_collisions(street, signs, architecture, transit)
	if not _save(tile_set, CITY_TILESET):
		quit(1)
		return
	tile_set = load(CITY_TILESET) as TileSet
	for index in IDS.size():
		var module := _make_module(IDS[index], index, tile_set)
		_save_patterns(module, IDS[index])
		_save_scene(module, "res://scenes/patterns/%s.tscn" % IDS[index])
		module.free()
	if failed:
		quit(1)
		return
	var showcase := _make_showcase()
	_save_scene(showcase, SHOWCASE)
	showcase.free()
	if not failed:
		print("Saved city TileSet: 72 tiles across six sources (40 new city assets).")
		print("Saved six 12x12 modular scenes, 18 native TileMapPatterns and %s" % SHOWCASE)
	quit(1 if failed else 0)


func _add_atlas(tile_set: TileSet, source_id: int, basename: String, grid_size: int, region_size: int, names: Array) -> TileSetAtlasSource:
	var texture := load("res://art/tilesets/%s.png" % basename) as Texture2D
	if texture == null or Vector2i(texture.get_size()) != Vector2i.ONE * grid_size * region_size:
		push_error("%s must be imported at %dx%d pixels." % [basename, grid_size * region_size, grid_size * region_size])
		failed = true
		return null
	var source := TileSetAtlasSource.new()
	source.resource_name = basename.trim_prefix("city_").capitalize()
	source.texture = texture
	source.texture_region_size = Vector2i.ONE * region_size
	source.use_texture_padding = true
	tile_set.add_source(source, source_id)
	for y in grid_size:
		for x in grid_size:
			var coords := Vector2i(x, y)
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			data.set_custom_data("tile_name", names[y * grid_size + x])
			data.set_custom_data("blocks_movement", false)
			# Signs render above nearby architecture when used as wall-mounted fascia.
			data.z_index = 1 if source_id == 3 else 0
	return source


func _configure_collisions(street: TileSetAtlasSource, signs: TileSetAtlasSource, architecture: TileSetAtlasSource, transit: TileSetAtlasSource) -> void:
	var street_boxes := [
		[Vector2i(0, 0), Vector2(0.40, 0.14), Vector2.ZERO],
		[Vector2i(1, 0), Vector2(0.32, 0.28), Vector2.ZERO],
		[Vector2i(2, 0), Vector2(0.16, 0.19), Vector2.ZERO],
		[Vector2i(3, 0), Vector2(0.17, 0.24), Vector2.ZERO],
		[Vector2i(0, 1), Vector2(0.34, 0.14), Vector2.ZERO],
		[Vector2i(1, 1), Vector2(0.25, 0.23), Vector2.ZERO],
		[Vector2i(2, 1), Vector2(0.39, 0.28), Vector2.ZERO],
		[Vector2i(3, 1), Vector2(0.30, 0.25), Vector2.ZERO],
		[Vector2i(0, 2), Vector2(0.33, 0.19), Vector2.ZERO],
		[Vector2i(2, 2), Vector2(0.44, 0.06), Vector2.ZERO],
		[Vector2i(0, 3), Vector2(0.25, 0.28), Vector2.ZERO],
		[Vector2i(1, 3), Vector2(0.055, 0.055), Vector2(0.0, 0.23)],
	]
	for box in street_boxes:
		_box(street, box[0], box[1], box[2])
	# Corner fence retains its open interior; sandbox, laundry and litter are passable.
	_box(street, Vector2i(3, 2), Vector2(0.42, 0.055), Vector2(0.0, -0.28))
	_box(street, Vector2i(3, 2), Vector2(0.055, 0.33), Vector2(-0.36, 0.0), true)
	for index in [0, 1, 2, 3, 7, 8, 9, 10, 11, 12]:
		_box(signs, Vector2i(index % 4, index / 4), Vector2(0.035, 0.035), Vector2(0.0, 0.32))
	_box(signs, Vector2i(2, 3), Vector2(0.28, 0.055), Vector2(0.0, 0.28))
	_box(signs, Vector2i(3, 3), Vector2(0.34, 0.05), Vector2(0.0, 0.28))
	for y in 2:
		for x in 2:
			_box(architecture, Vector2i(x, y), Vector2(0.39, 0.34), Vector2(0.0, 0.05))
	_box(transit, Vector2i(0, 0), Vector2(0.44, 0.17))
	_box(transit, Vector2i(1, 0), Vector2(0.44, 0.17))
	_box(transit, Vector2i(0, 1), Vector2(0.42, 0.15), Vector2(0.0, 0.13))
	# Overhead wires are passable; only their two pole bases collide.
	_box(transit, Vector2i(1, 1), Vector2(0.025, 0.025), Vector2(-0.40, 0.15))
	_box(transit, Vector2i(1, 1), Vector2(0.025, 0.025), Vector2(0.40, 0.15), true)


func _box(source: TileSetAtlasSource, coords: Vector2i, half_extent: Vector2, offset := Vector2.ZERO, append := false) -> void:
	var data := source.get_tile_data(coords, 0)
	var polygon_index := data.get_collision_polygons_count(0) if append else 0
	var size := float(source.texture_region_size.x)
	var half := half_extent * size
	var center := offset * size
	data.set_collision_polygons_count(0, polygon_index + 1)
	data.set_collision_polygon_points(0, polygon_index, PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	]))
	data.set_custom_data("blocks_movement", true)


func _make_module(pattern_id: String, style: int, tile_set: TileSet) -> Node2D:
	var module := Node2D.new()
	module.name = pattern_id.to_pascal_case()
	module.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	module.set_meta("pattern_id", pattern_id)
	module.set_meta("grid_dimensions", GRID)
	module.set_meta("footprint_cells", GRID)
	module.set_meta("world_cell_size", CELL_SIZE)
	module.set_meta("connector_cells", CONNECTORS)
	module.set_meta("description", "Stamp all three layers at the same origin. Rows 5/6 and columns 5/6 remain open for aligned module connections.")
	var ground := _layer(module, "Ground", tile_set, 0)
	var details := _layer(module, "Details", tile_set, 1)
	var props := _layer(module, "Props", tile_set, 2)
	ground.collision_enabled = false
	details.collision_enabled = false
	_paint_ground(ground, details, style)
	for placement in _layout(pattern_id):
		var cell := Vector2i(placement[0], placement[1])
		var source_id: int = placement[2]
		var atlas := Vector2i(placement[3], placement[4])
		props.set_cell(cell, source_id, atlas)
	return module


func _layer(module: Node2D, layer_name: String, tile_set: TileSet, depth: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.z_index = depth
	layer.navigation_enabled = false
	_attach(module, layer, module)
	return layer


func _paint_ground(ground: TileMapLayer, details: TileMapLayer, style: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8040 + style
	for y in GRID.y:
		for x in GRID.x:
			var cross := x == 5 or x == 6 or y == 5 or y == 6
			var tile := Vector2i(0, 0)
			if not cross:
				match style:
					0, 2:
						tile = Vector2i(0, 2)
					1:
						tile = Vector2i(0, 2) if y >= 7 else Vector2i(0, 0)
					3:
						tile = Vector2i(3, 2)
					4:
						tile = Vector2i(2, 2) if x < 4 else Vector2i(0, 0)
					5:
						tile = Vector2i(3, 2)
			if rng.randf() < 0.13:
				if tile == Vector2i(0, 0):
					tile = Vector2i(1, 0)
				elif tile == Vector2i(0, 2):
					tile = Vector2i(1, 2)
			ground.set_cell(Vector2i(x, y), 0, tile)
	# Ground-only markings stay walkable through the common two-cell connectors.
	for y in [1, 4, 7, 10]:
		details.set_cell(Vector2i(5, y), 0, Vector2i(1, 3))
	for x in [1, 4, 7, 10]:
		details.set_cell(Vector2i(x, 6), 0, Vector2i(0, 3))
	details.set_cell(Vector2i(7, 4), 0, Vector2i(3, 3))
	if style == 1 or style == 2:
		for x in [5, 6]:
			details.set_cell(Vector2i(x, 8), 0, Vector2i(2, 3))
	if style == 5:
		for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(9, 2), Vector2i(9, 3)]:
			details.set_cell(cell, 0, Vector2i(2, 2))


func _layout(pattern_id: String) -> Array:
	# Entries are [cell_x, cell_y, source_id, atlas_x, atlas_y].
	# 256px architecture/transit is centered in a 5x5-cell quadrant. All origins
	# stay on the 64px grid, so native TileMapPatterns preserve their footprints.
	match pattern_id:
		"apartment_courtyard":
			return [
				[2,2,4,0,0], [9,2,4,1,0], [2,3,3,1,3],
				[1,8,2,0,0], [3,8,2,1,1], [2,10,2,2,3],
				[9,9,2,1,0], [10,8,2,2,0], [8,10,2,3,3], [8,8,3,2,3],
			]
		"trolleybus_stop":
			return [
				[2,2,5,0,0], [9,2,5,1,0], [2,9,5,0,1], [9,9,5,1,1],
				[3,8,3,3,1], [8,3,3,1,2], [8,8,3,0,2],
				[1,7,2,3,0], [10,0,2,1,3], [3,4,2,3,3],
			]
		"market_corner":
			return [
				[2,2,4,0,1], [9,9,4,1,1], [2,3,3,0,1], [9,10,3,2,1],
				[2,9,2,2,1], [3,10,2,3,1], [9,2,2,0,1],
				[8,3,2,0,0], [1,8,2,3,3], [10,3,2,1,1],
			]
		"city_entrance":
			return [
				[2,2,3,0,0], [9,2,3,1,0], [2,9,3,2,0], [8,3,3,3,0],
				[9,9,4,1,1], [1,3,1,3,2], [10,4,1,2,2],
				[3,8,2,3,3], [1,10,1,0,1],
			]
		"roadside_checkpoint":
			return [
				[9,2,4,1,0], [9,3,3,1,1], [2,3,3,2,2],
				[9,8,3,3,2], [8,10,3,0,3], [10,10,2,0,3],
				[1,2,1,0,0], [2,2,1,0,0], [3,2,1,0,0],
				[8,9,1,0,0], [9,9,1,0,0], [10,9,1,0,0],
				[1,9,1,2,0], [2,9,1,2,0], [3,10,1,3,0], [1,10,1,2,1],
			]
		"playground":
			return [
				[2,2,2,0,2], [3,2,2,0,2], [9,2,2,1,2],
				[2,9,2,0,1], [3,10,2,3,3], [9,9,2,0,0],
				[1,4,2,2,2], [2,4,2,2,2], [3,4,2,2,2], [10,10,2,3,2],
				[1,8,1,2,2], [10,2,1,3,2], [8,10,2,1,1], [8,8,3,3,3],
			]
	return []


func _save_patterns(module: Node2D, pattern_id: String) -> void:
	for layer_name in ["Ground", "Details", "Props"]:
		var layer := module.get_node(layer_name) as TileMapLayer
		var pattern := TileMapPattern.new()
		pattern.resource_name = "%s / %s" % [pattern_id.capitalize(), layer_name]
		for cell in layer.get_used_cells():
			pattern.set_cell(cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell))
		# Preserve leading/trailing empty cells so every layer stamps at one origin.
		pattern.set_size(GRID)
		pattern.set_meta("pattern_id", pattern_id)
		pattern.set_meta("layer_name", layer_name)
		pattern.set_meta("grid_dimensions", GRID)
		pattern.set_meta("world_cell_size", CELL_SIZE)
		pattern.set_meta("tile_set_path", CITY_TILESET)
		_save(pattern, "res://resources/patterns/%s_%s.tres" % [pattern_id, layer_name.to_lower()])


func _make_showcase() -> Node2D:
	var showcase := Node2D.new()
	showcase.name = "CityPatternsShowcase"
	showcase.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var map_size := Vector2(2880.0, 2016.0)
	showcase.set_script(load(PREVIEW_SCRIPT))
	showcase.set("map_size", map_size)
	showcase.set_meta("description", "Six reusable 12x12 modules. Three-cell gutters separate examples. Open individual pattern scenes to edit their cells.")
	var background := Polygon2D.new()
	background.name = "GalleryBackground"
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(map_size.x, 0.0), map_size, Vector2(0.0, map_size.y)])
	background.color = Color("171e21")
	background.z_index = -1
	_attach(showcase, background, showcase)
	_label(showcase, "MODULAR CITY BLOCKS", Vector2(96.0, 24.0), 48, Color("e4e6d9"))
	_label(showcase, "12 x 12 cells per module  /  64px grid  /  two-cell connecting streets", Vector2(96.0, 88.0), 26, Color("98aaa9"))
	for index in IDS.size():
		var origin := Vector2(96.0 + (index % 3) * 960.0, 192.0 + (index / 3) * 960.0)
		var packed := load("res://scenes/patterns/%s.tscn" % IDS[index]) as PackedScene
		var module := packed.instantiate() as Node2D
		module.position = origin
		_attach(showcase, module, showcase)
		_label(showcase, TITLES[index], origin - Vector2(0.0, 52.0), 28, Color("d1b47a"))
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = map_size * 0.5
	camera.zoom = Vector2.ONE * 0.33
	_attach(showcase, camera, showcase)
	return showcase


func _label(parent: Node2D, text: String, position: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.z_index = 10
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_attach(parent, label, parent)


func _save_scene(scene: Node2D, path: String) -> void:
	var packed := PackedScene.new()
	var error := packed.pack(scene)
	if error != OK:
		push_error("Cannot pack %s: %s" % [path, error_string(error)])
		failed = true
		return
	_save(packed, path)


func _save(resource: Resource, path: String) -> bool:
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		failed = true
		return false
	return true


func _attach(parent: Node, child: Node, scene_owner: Node) -> void:
	parent.add_child(child)
	child.owner = scene_owner
