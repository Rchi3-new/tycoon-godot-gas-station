extends SceneTree
## Validate editable city modules, their saved patterns, and actual physics routes.
## Run after importing atlases and building the city patterns:
## godot --headless --path . --script res://scripts/tools/validate_city_patterns.gd

const TILESET_PATH := "res://resources/tilesets/survivors_city.tres"
const PATTERN_IDS := [
	"apartment_courtyard", "trolleybus_stop", "market_corner",
	"city_entrance", "roadside_checkpoint", "playground",
]
const LAYER_NAMES := ["Ground", "Details", "Props"]
const GRID := Vector2i(12, 12)
const CELL_SIZE := 64
const ACTOR_RADIUS := 12.0
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SOURCE_GRIDS := [4, 4, 4, 4, 2, 2, 4, 1, 1, 1]
const SOURCE_REGIONS := [64, 64, 64, 128, 256, 256, 64, 256, 192, 192]
const TRACK_MASKS := [10, 5, 15, 0, 3, 9, 6, 12, 10, 5, 10, 5, 10, 5, 10, 5]

var failures: Array[String] = []
var tile_set: TileSet
var verified_blockers := 0
var verified_large_sources: Dictionary[int, bool] = {}
var verified_connectors := 0
var verified_sweeps := 0


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	tile_set = load(TILESET_PATH) as TileSet
	if tile_set == null:
		_fail("The saved city TileSet could not be loaded.")
		_finish()
		return
	_validate_atlases()
	if not failures.is_empty():
		_finish()
		return
	for pattern_id in PATTERN_IDS:
		await _validate_module(pattern_id)
	_validate_track_preview()
	await _validate_apartment_preview()
	_check(verified_large_sources.has(4), "No architecture tile produced an actual collision hit.")
	_check(verified_large_sources.has(5), "No transit tile produced an actual collision hit.")
	for view_source in [7, 8, 9]:
		_check(verified_large_sources.has(view_source), "Apartment view source %d produced no actual collision hit." % view_source)
	_finish()


func _validate_atlases() -> void:
	_check(tile_set.tile_size == Vector2i.ONE * CELL_SIZE, "City TileSet must use a 64px grid.")
	_check(tile_set.get_source_count() == 10, "Expected ten city atlas sources.")
	_check(tile_set.get_physics_layers_count() > 0, "Environment physics layer is missing.")
	if tile_set.get_physics_layers_count() == 0:
		return
	_check(tile_set.get_physics_layer_collision_layer(0) == 1, "Environment colliders must occupy layer 1.")
	_check(tile_set.get_custom_data_layer_by_name("tile_name") >= 0, "tile_name custom data is missing.")
	_check(tile_set.get_custom_data_layer_by_name("blocks_movement") >= 0, "blocks_movement custom data is missing.")
	_check(tile_set.get_custom_data_layer_by_name("track_connections") >= 0, "track_connections custom data is missing.")
	if not failures.is_empty():
		return
	var total := 0
	for source_id in SOURCE_GRIDS.size():
		if not tile_set.has_source(source_id):
			_fail("Missing atlas source %d." % source_id)
			continue
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			_fail("Source %d has no atlas texture." % source_id)
			continue
		var side: int = SOURCE_GRIDS[source_id]
		_check(source.get_tiles_count() == side * side, "Unexpected tile count in source %d." % source_id)
		_check(source.get_atlas_grid_size() == Vector2i.ONE * side, "Incorrect atlas grid for source %d." % source_id)
		_check(source.texture_region_size == Vector2i.ONE * SOURCE_REGIONS[source_id], "Incorrect imported tile size for source %d." % source_id)
		_check(not source.texture.resource_path.is_empty(), "Source %d has no saved texture reference." % source_id)
		var pixels := source.texture.get_image()
		if pixels == null or pixels.is_empty():
			_fail("Source %d texture cannot be read." % source_id)
			continue
		if pixels.is_compressed():
			if pixels.decompress() != OK:
				_fail("Source %d texture cannot be decompressed." % source_id)
				continue
		for y in side:
			for x in side:
				var coords := Vector2i(x, y)
				if not source.has_tile(coords):
					_fail("Missing source %d tile %s." % [source_id, coords])
					continue
				var data := source.get_tile_data(coords, 0)
				if data == null:
					_fail("Source %d tile %s has no base tile data." % [source_id, coords])
					continue
				total += 1
				_check(not str(data.get_custom_data("tile_name")).is_empty(), "Unnamed source %d tile %s." % [source_id, coords])
				_check(data.texture_origin == Vector2i.ZERO, "Unexpected texture offset in source %d tile %s." % [source_id, coords])
				var blocks: bool = data.get_custom_data("blocks_movement")
				_check(blocks == (data.get_collision_polygons_count(0) > 0), "Collision flag disagrees with polygon data for source %d tile %s." % [source_id, coords])
				if source_id == 4 or source_id == 5 or source_id >= 7:
					_check(blocks, "Large architecture/transit source %d tile %s has no footprint collider." % [source_id, coords])
				elif source_id == 6:
					_check(not blocks, "Tram track ground must remain passable at %s." % coords)
					_check(data.get_custom_data("track_connections") == TRACK_MASKS[y * 4 + x], "Tram track edge mask is incorrect at %s." % coords)
				var region: Rect2i = source.get_tile_texture_region(coords)
				if not Rect2i(Vector2i.ZERO, pixels.get_size()).encloses(region):
					_fail("Source %d tile %s samples outside its image." % [source_id, coords])
					continue
				if source_id == 6:
					_validate_opaque_ground(pixels, region, coords)
				elif source_id > 0:
					_validate_alpha(pixels, region, source_id, coords)
	_check(total == 91, "Expected 91 valid registered atlas tiles; found %d." % total)
	print("Atlas references checked: %d tiles across ten sources; prop alpha and opaque track ground checked per tile." % total)


func _validate_apartment_preview() -> void:
	var packed: PackedScene = load("res://scenes/panel_apartment_views_showcase.tscn") as PackedScene
	if packed == null:
		_fail("Apartment views showcase is missing.")
		return
	var preview: Node2D = packed.instantiate() as Node2D
	root.add_child(preview)
	var apartments: TileMapLayer = preview.get_node_or_null("Apartments") as TileMapLayer
	if apartments == null:
		_fail("Apartment views showcase needs an Apartments TileMapLayer.")
		preview.free()
		return
	_check(apartments.tile_set == tile_set, "Apartment views do not use the saved shared TileSet.")
	_check(preview.y_sort_enabled and apartments.y_sort_enabled and apartments.z_index == 0, "Apartment views must sort at character Z using Y sorting.")
	_check(apartments.get_used_cells().size() == 4, "Apartment preview must show exactly four views.")
	var expected_sources: Array[int] = [4, 7, 8, 9]
	var seen_sources: Dictionary[int, bool] = {}
	var dimensions: Vector2i = preview.get_meta("grid_dimensions", Vector2i.ZERO)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(dimensions) * CELL_SIZE)
	for cell in apartments.get_used_cells():
		var source_id: int = apartments.get_cell_source_id(cell)
		seen_sources[source_id] = true
		_check(expected_sources.has(source_id) and apartments.get_cell_atlas_coords(cell) == Vector2i.ZERO, "Apartment preview contains an unexpected source or atlas tile.")
		var center: Vector2 = apartments.map_to_local(cell)
		_check(bounds.encloses(Rect2(center - Vector2(128, 128), Vector2(256, 256))), "Apartment view artwork extends outside the preview.")
		if source_id >= 7:
			var data: TileData = apartments.get_cell_tile_data(cell)
			if data == null:
				_fail("Apartment view source %d has no tile data." % source_id)
				continue
			_check(data.y_sort_origin >= 60 and data.y_sort_origin <= 120, "Apartment view sorting origin should sit near the sprite base.")
			for polygon_index in data.get_collision_polygons_count(0):
				var polygon: PackedVector2Array = data.get_collision_polygon_points(0, polygon_index)
				var top: float = 128.0
				var bottom: float = -128.0
				for point in polygon:
					top = minf(top, point.y)
					bottom = maxf(bottom, point.y)
					_check(absf(point.x) <= 128.0 and point.y >= 60.0 and point.y <= 128.0, "Apartment view collider must fit within the ground-level sprite base.")
				_check(bottom - top <= 40.0, "Apartment view collider covers the facade instead of its narrow base.")
	for source_id in expected_sources:
		_check(seen_sources.has(source_id), "Apartment preview is missing source %d." % source_id)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState2D = preview.get_world_2d().direct_space_state
	_validate_physics_hits(space, apartments, "panel_apartment_views")
	preview.free()
	await physics_frame
	print("Apartment preview checked: front/rear/left/right, base sorting and actual footprint collisions.")


func _validate_opaque_ground(pixels: Image, region: Rect2i, coords: Vector2i) -> void:
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if pixels.get_pixel(x, y).a < 0.99:
				_fail("Tram track ground tile %s contains a transparent gap." % coords)
				return


func _validate_track_preview() -> void:
	var packed := load("res://scenes/tram_tracks_showcase.tscn") as PackedScene
	if packed == null:
		_fail("Tram track showcase scene is missing.")
		return
	var preview := packed.instantiate() as Node2D
	var tracks := preview.get_node_or_null("JoinedTracks") as TileMapLayer
	var palette := preview.get_node_or_null("TilePalette") as TileMapLayer
	if tracks == null or palette == null:
		_fail("Tram track showcase must contain JoinedTracks and TilePalette TileMapLayers.")
		preview.free()
		return
	_check(tracks.tile_set == tile_set and palette.tile_set == tile_set, "Track preview does not reference the expanded shared TileSet.")
	_check(not tracks.collision_enabled and not palette.collision_enabled, "Track preview ground must not enable collision.")
	var field: Rect2i = preview.get_meta("track_field", Rect2i())
	var terminals: Array = preview.get_meta("track_terminals", [])
	_check(field.has_area() and tracks.get_used_cells().size() == field.get_area(), "Track demo asphalt panel has missing ground cells.")
	_check(terminals.size() == 4, "Track demo must declare four through-route endpoints.")
	var palette_coords: Dictionary[Vector2i, bool] = {}
	for cell in palette.get_used_cells():
		_check(palette.get_cell_source_id(cell) == 6, "Palette contains a non-track tile.")
		palette_coords[palette.get_cell_atlas_coords(cell)] = true
	_check(palette_coords.size() == 16, "Track palette does not display all 16 distinct tiles.")
	var connected: Dictionary[Vector2i, int] = {}
	for cell in tracks.get_used_cells():
		_check(tracks.get_cell_source_id(cell) == 6 and field.has_point(cell), "Joined track panel contains an invalid source or out-of-bounds tile.")
		var data := tracks.get_cell_tile_data(cell)
		if data != null:
			var mask: int = data.get_custom_data("track_connections")
			if mask != 0:
				connected[cell] = mask
	var edges := [[Vector2i.UP, 1, 4], [Vector2i.RIGHT, 2, 8], [Vector2i.DOWN, 4, 1], [Vector2i.LEFT, 8, 2]]
	for cell in connected:
		for edge in edges:
			var outward_mask: int = edge[1]
			var reciprocal_mask: int = edge[2]
			if (connected[cell] & outward_mask) != 0:
				var neighbor: Vector2i = cell + Vector2i(edge[0])
				var matches: bool = connected.has(neighbor) and (connected[neighbor] & reciprocal_mask) != 0
				var terminal_exit: bool = terminals.has(cell) and not field.has_point(neighbor)
				_check(matches or terminal_exit, "Track tile %s has an unmatched edge toward %s." % [cell, neighbor])
	_check(not connected.is_empty(), "Track demo contains no connected rail tiles.")
	if not connected.is_empty():
		var queue: Array[Vector2i] = [connected.keys()[0]]
		var reached: Dictionary[Vector2i, bool] = {queue[0]: true}
		var cursor := 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			for edge in edges:
				var neighbor: Vector2i = cell + Vector2i(edge[0])
				var outward_mask: int = edge[1]
				var reciprocal_mask: int = edge[2]
				if (connected[cell] & outward_mask) != 0 and connected.has(neighbor) and (connected[neighbor] & reciprocal_mask) != 0 and not reached.has(neighbor):
					reached[neighbor] = true
					queue.append(neighbor)
		_check(reached.size() == connected.size(), "Joined track routes contain disconnected sections.")
	print("Track preview checked: 16 palette entries, %d joined track cells and four route endpoints." % connected.size())
	preview.free()


func _validate_alpha(pixels: Image, region: Rect2i, source_id: int, coords: Vector2i) -> void:
	var has_transparent := false
	var has_visible := false
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var alpha := pixels.get_pixel(x, y).a
			has_transparent = has_transparent or alpha < 0.01
			has_visible = has_visible or alpha > 0.5
			if has_transparent and has_visible:
				return
	_check(has_transparent, "Source %d tile %s lacks true transparent pixels." % [source_id, coords])
	_check(has_visible, "Source %d tile %s has no visible artwork." % [source_id, coords])


func _validate_module(pattern_id: String) -> void:
	var scene_path := "res://scenes/patterns/%s.tscn" % pattern_id
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("Could not load module %s." % pattern_id)
		return
	var module := packed.instantiate() as Node2D
	if module == null:
		_fail("Module %s must have a Node2D root." % pattern_id)
		return
	root.add_child(module)
	_check(module.get_meta("pattern_id", "") == pattern_id, "%s pattern_id metadata disagrees with its filename." % pattern_id)
	_check(module.get_meta("grid_dimensions", Vector2i.ZERO) == GRID, "%s grid_dimensions is not 12x12." % pattern_id)
	_check(module.get_meta("footprint_cells", Vector2i.ZERO) == GRID, "%s declared footprint is not 12x12." % pattern_id)
	_check(module.get_meta("world_cell_size", 0) == CELL_SIZE, "%s world_cell_size is not 64." % pattern_id)
	_check(module.transform.is_equal_approx(Transform2D.IDENTITY), "%s root must retain a local identity transform for stamping." % pattern_id)
	var ground := module.get_node_or_null("Ground") as TileMapLayer
	var props := module.get_node_or_null("Props") as TileMapLayer
	var layers: Array[TileMapLayer] = []
	for layer_name in LAYER_NAMES:
		var layer := module.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			_fail("%s is missing layer %s." % [pattern_id, layer_name])
			continue
		layers.append(layer)
		_validate_layer(layer, pattern_id)
		_validate_saved_pattern(layer, pattern_id)
	if ground == null or props == null:
		module.free()
		return
	_check(ground.get_used_cells().size() == GRID.x * GRID.y, "%s ground does not fill all 144 cells." % pattern_id)
	for y in GRID.y:
		for x in GRID.x:
			_check(ground.get_cell_source_id(Vector2i(x, y)) == 0, "%s ground cell %s is missing or is not terrain." % [pattern_id, Vector2i(x, y)])
	_check(not props.get_used_cells().is_empty(), "%s has no authored props." % pattern_id)
	var connectors: Array = module.get_meta("connector_cells", [])
	var expected_connectors: Array[Vector2i] = []
	for lane in [5, 6]:
		expected_connectors.append_array([Vector2i(lane, 0), Vector2i(lane, 11), Vector2i(0, lane), Vector2i(11, lane)])
	_check(connectors.size() == expected_connectors.size(), "%s must declare eight connector cells." % pattern_id)
	for connector in expected_connectors:
		_check(connectors.has(connector), "%s is missing connector %s." % [pattern_id, connector])
	# TileMap collision bodies are deferred; let them enter the actual physics world.
	await physics_frame
	await physics_frame
	var space := module.get_world_2d().direct_space_state
	for layer in layers:
		_validate_physics_hits(space, layer, pattern_id)
	_validate_routes(space, ground, expected_connectors, pattern_id)
	module.free()
	await physics_frame


func _validate_layer(layer: TileMapLayer, pattern_id: String) -> void:
	_check(layer.tile_set == tile_set, "%s/%s does not reference the saved shared TileSet." % [pattern_id, layer.name])
	_check(layer.transform.is_equal_approx(Transform2D.IDENTITY), "%s/%s must use the unscaled shared grid." % [pattern_id, layer.name])
	if layer.tile_set != tile_set:
		return
	var cells := Rect2i(Vector2i.ZERO, GRID)
	var pixels := Rect2(Vector2.ZERO, Vector2(GRID) * CELL_SIZE)
	for cell in layer.get_used_cells():
		_check(cells.has_point(cell), "%s/%s cell %s is outside the declared footprint." % [pattern_id, layer.name, cell])
		var data := layer.get_cell_tile_data(cell)
		if data == null:
			_fail("%s/%s cell %s references a missing tile." % [pattern_id, layer.name, cell])
			continue
		var source := tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		var artwork_size := Vector2(source.get_tile_texture_region(layer.get_cell_atlas_coords(cell)).size)
		var center := layer.map_to_local(cell)
		_check(pixels.encloses(Rect2(center - artwork_size * 0.5, artwork_size)), "%s/%s tile %s artwork extends beyond its footprint." % [pattern_id, layer.name, cell])
		for polygon_index in data.get_collision_polygons_count(0):
			var polygon := data.get_collision_polygon_points(0, polygon_index)
			_check(polygon.size() >= 3, "%s/%s cell %s has a degenerate collider." % [pattern_id, layer.name, cell])
			for point in polygon:
				var position: Vector2 = center + point
				_check(position.x >= 0.0 and position.y >= 0.0 and position.x <= pixels.end.x and position.y <= pixels.end.y, "%s/%s cell %s collider extends beyond its footprint." % [pattern_id, layer.name, cell])


func _validate_saved_pattern(layer: TileMapLayer, pattern_id: String) -> void:
	var path := "res://resources/patterns/%s_%s.tres" % [pattern_id, str(layer.name).to_lower()]
	var pattern := load(path) as TileMapPattern
	if pattern == null:
		_fail("Missing saved TileMapPattern: %s." % path)
		return
	# TileMapPattern serializes occupied cells, not an explicit padded size.
	# Preserve the module footprint in metadata while verifying exact stamp offsets.
	var occupied_end := Vector2i.ZERO
	for occupied_cell in pattern.get_used_cells():
		occupied_end = occupied_end.max(occupied_cell + Vector2i.ONE)
	_check(pattern.get_size() == occupied_end, "%s has incorrect occupied extents." % path)
	_check(pattern.get_meta("footprint_cells", Vector2i.ZERO) == GRID, "%s has an incorrect declared footprint." % path)
	_check(pattern.get_meta("origin_cells", Vector2i(-1, -1)) == Vector2i.ZERO, "%s has an incorrect local stamp origin." % path)
	_check(pattern.get_meta("tile_set_path", "") == TILESET_PATH, "%s has no correct TileSet reference metadata." % path)
	_check(pattern.get_meta("pattern_id", "") == pattern_id, "%s pattern_id metadata is wrong." % path)
	_check(pattern.get_meta("layer_name", "") == str(layer.name), "%s layer metadata is wrong." % path)
	_check(pattern.get_meta("grid_dimensions", Vector2i.ZERO) == GRID, "%s grid metadata is wrong." % path)
	_check(pattern.get_meta("world_cell_size", 0) == CELL_SIZE, "%s cell size metadata is wrong." % path)
	_check(pattern.get_used_cells().size() == layer.get_used_cells().size(), "%s cell count differs from its editable scene layer." % path)
	for cell in pattern.get_used_cells():
		_check(Rect2i(Vector2i.ZERO, GRID).has_point(cell), "%s has a cell outside its footprint." % path)
		_check(pattern.get_cell_source_id(cell) == layer.get_cell_source_id(cell) and pattern.get_cell_atlas_coords(cell) == layer.get_cell_atlas_coords(cell) and pattern.get_cell_alternative_tile(cell) == layer.get_cell_alternative_tile(cell), "%s cell %s differs from its scene layer; local stamp alignment may have shifted." % [path, cell])


func _validate_physics_hits(space: PhysicsDirectSpaceState2D, layer: TileMapLayer, pattern_id: String) -> void:
	for cell in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data == null or not data.get_custom_data("blocks_movement"):
			continue
		_check(layer.collision_enabled, "%s/%s has blocking tiles but disabled collision." % [pattern_id, layer.name])
		for polygon_index in data.get_collision_polygons_count(0):
			var polygon := data.get_collision_polygon_points(0, polygon_index)
			if polygon.size() < 3:
				continue
			var polygon_center := Vector2.ZERO
			for point in polygon:
				polygon_center += point
			polygon_center /= polygon.size()
			var query := PhysicsPointQueryParameters2D.new()
			query.position = layer.to_global(layer.map_to_local(cell) + polygon_center)
			query.collision_mask = 1
			var hit_own_layer := false
			for hit in space.intersect_point(query, 32):
				if hit.get("collider") == layer:
					hit_own_layer = true
			_check(hit_own_layer, "%s/%s blocking cell %s produced no actual physics hit." % [pattern_id, layer.name, cell])
			if hit_own_layer:
				verified_blockers += 1
				var source_id := layer.get_cell_source_id(cell)
				if source_id >= 4:
					verified_large_sources[source_id] = true


func _validate_routes(space: PhysicsDirectSpaceState2D, ground: TileMapLayer, connectors: Array[Vector2i], pattern_id: String) -> void:
	var shape := CircleShape2D.new()
	shape.radius = ACTOR_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.margin = 0.001
	var clear: Dictionary[Vector2i, bool] = {}
	for y in GRID.y:
		for x in GRID.x:
			var cell := Vector2i(x, y)
			query.transform = Transform2D(0.0, ground.to_global(ground.map_to_local(cell)))
			if space.intersect_shape(query, 1).is_empty():
				clear[cell] = true
	var start := Vector2i(5, 5)
	if not clear.has(start):
		_fail("%s central connector intersection is blocked for a 24px actor." % pattern_id)
		return
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var pending: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < pending.size():
		var current := pending[cursor]
		cursor += 1
		for direction in CARDINALS:
			var neighbor: Vector2i = current + direction
			if not clear.has(neighbor) or reached.has(neighbor):
				continue
			if _sweep_clear(space, query, ground.to_global(ground.map_to_local(current)), ground.to_global(ground.map_to_local(neighbor))):
				reached[neighbor] = true
				pending.append(neighbor)
	for cell in connectors:
		_check(reached.has(cell), "%s connector %s has no swept 24px-actor route from the center." % [pattern_id, cell])
		var outward := Vector2i.ZERO
		if cell.x == 0:
			outward = Vector2i.LEFT
		elif cell.x == GRID.x - 1:
			outward = Vector2i.RIGHT
		elif cell.y == 0:
			outward = Vector2i.UP
		elif cell.y == GRID.y - 1:
			outward = Vector2i.DOWN
		var center := ground.to_global(ground.map_to_local(cell))
		_check(_sweep_clear(space, query, center, center + Vector2(outward) * CELL_SIZE), "%s connector %s is obstructed at its module seam." % [pattern_id, cell])
		verified_connectors += 1
	# Verify the two promised straight crossing lanes, not only graph connectivity.
	for lane in [5, 6]:
		_check(_sweep_clear(space, query, ground.to_global(ground.map_to_local(Vector2i(0, lane))), ground.to_global(ground.map_to_local(Vector2i(11, lane)))), "%s east-west generation lane %d is obstructed." % [pattern_id, lane])
		_check(_sweep_clear(space, query, ground.to_global(ground.map_to_local(Vector2i(lane, 0))), ground.to_global(ground.map_to_local(Vector2i(lane, 11)))), "%s north-south generation lane %d is obstructed." % [pattern_id, lane])
	print("%s: 8 connectors checked; %d/%d clear sampled floor centers connected by physics sweeps." % [pattern_id, reached.size(), clear.size()])


func _sweep_clear(space: PhysicsDirectSpaceState2D, query: PhysicsShapeQueryParameters2D, from: Vector2, to: Vector2) -> bool:
	query.transform = Transform2D(0.0, from)
	query.motion = Vector2.ZERO
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.transform.origin = to
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.transform.origin = from
	query.motion = to - from
	var fractions := space.cast_motion(query)
	query.motion = Vector2.ZERO
	verified_sweeps += 1
	return fractions.size() == 2 and fractions[0] >= 0.99999


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: 91 atlas tiles; prop alpha and opaque track ground; joined track routes; four apartment views; six full module footprints; 18 aligned saved patterns; %d collider hits; %d connectors; %d actual 24px-circle sweeps." % [verified_blockers, verified_connectors, verified_sweeps])
		print("Routes validate sampled straight circle sweeps and connector seams, not exhaustive character motion or another actor size.")
		quit(0)
	else:
		print("FAIL: %d city pattern validation issue(s)." % failures.size())
		quit(1)
