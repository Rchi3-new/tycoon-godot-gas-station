extends SceneTree
## Validate the authored scene after the atlas import and arena build.
## godot --headless --path . --script res://scripts/tools/validate_survivors_arena.gd

const SCENE_PATH := "res://scenes/survivors_arena.tscn"
const CARDINALS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Arena scene could not be loaded.")
		_finish()
		return
	var arena := packed.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	var dimensions: Vector2i = arena.get_meta("grid_dimensions", Vector2i.ZERO)
	var cell_size: int = arena.get_meta("world_cell_size", 0)
	if dimensions.x <= 0 or dimensions.y <= 0 or cell_size <= 0:
		_fail("Arena grid metadata is missing or invalid.")
		_finish()
		return
	var ground := arena.get_node_or_null("Ground") as TileMapLayer
	var details := arena.get_node_or_null("Details") as TileMapLayer
	var obstacles := arena.get_node_or_null("Obstacles") as TileMapLayer
	var landmarks := arena.get_node_or_null("Landmarks") as TileMapLayer
	var foliage := arena.get_node_or_null("Foliage") as TileMapLayer
	if ground == null or details == null or obstacles == null or landmarks == null or foliage == null:
		_fail("Arena must contain Ground, Details, Obstacles, Landmarks and Foliage TileMapLayers.")
		_finish()
		return
	_check(ground.get_used_cells().size() == dimensions.x * dimensions.y, "Every ground cell must be filled.")
	_check(not details.get_used_cells().is_empty(), "Detail layer is empty.")
	_check(not obstacles.get_used_cells().is_empty(), "Obstacle layer is empty.")
	_check(landmarks.get_used_cells().size() == 8, "Expected four large vehicles and four kiosks/bus shelters.")
	_check(not foliage.get_used_cells().is_empty(), "Foliage layer is empty.")
	_check(ground.tile_set.resource_path == "res://resources/tilesets/survivors_street.tres", "Scene does not reference the saved editable TileSet.")
	_check(is_equal_approx(ground.scale.x * ground.tile_set.tile_size.x, cell_size), "TileMap scale does not produce the configured world cell size.")
	_check(is_equal_approx(landmarks.scale.x, ground.scale.x * 3.0), "Landmarks must use three times the ground cell scale.")
	_check(is_equal_approx(foliage.scale.x, ground.scale.x * 2.0), "Foliage must use twice the ground cell scale.")
	var map_bounds := Rect2(Vector2.ZERO, Vector2(dimensions) * cell_size)
	for layer in [ground, details, obstacles, landmarks, foliage]:
		_check(layer.tile_set == ground.tile_set, "%s does not share the editable TileSet resource." % layer.name)
		for cell in layer.get_used_cells():
			_check(layer.get_cell_tile_data(cell) != null, "%s cell %s references a missing atlas tile." % [layer.name, cell])
			var center: Vector2 = layer.to_global(layer.map_to_local(cell))
			var size: Vector2 = Vector2(layer.tile_set.tile_size) * layer.scale
			_check(map_bounds.encloses(Rect2(center - size * 0.5, size)), "%s tile artwork extends beyond the map bounds." % layer.name)
	var registered_tiles := 0
	for index in ground.tile_set.get_source_count():
		var source := ground.tile_set.get_source(ground.tile_set.get_source_id(index)) as TileSetAtlasSource
		if source == null:
			_fail("TileSet has an unexpected non-atlas source.")
			continue
		registered_tiles += source.get_tiles_count()
		_check(source.get_atlas_grid_size() == Vector2i(4, 4), "Each imported atlas must contain a 4x4 tile grid.")
	_check(registered_tiles == 32, "Expected 32 registered atlas tiles.")
	# Allow TileMap physics bodies to enter the physics server before querying them.
	await physics_frame
	await physics_frame
	var space := arena.get_world_2d().direct_space_state
	var spawn := arena.get_node_or_null("PlayerSpawn") as Marker2D
	if spawn == null:
		_fail("PlayerSpawn marker is missing.")
	else:
		var spawn_circle := CircleShape2D.new()
		spawn_circle.radius = cell_size * 0.40
		var spawn_query := PhysicsShapeQueryParameters2D.new()
		spawn_query.shape = spawn_circle
		spawn_query.transform = Transform2D(0.0, spawn.global_position)
		spawn_query.collision_mask = 1
		_check(space.intersect_shape(spawn_query, 1).is_empty(), "PlayerSpawn overlaps an environment collider.")
	for layer in [obstacles, landmarks, foliage]:
		_validate_cover_collision(space, layer)
	var map_size := Vector2(dimensions) * cell_size
	var center := map_size * 0.5
	var boundary := arena.get_node_or_null("MapBoundary") as StaticBody2D
	_check(boundary != null, "Map boundary body is missing.")
	if boundary != null:
		for target in [Vector2(-cell_size * 2.0, center.y), Vector2(map_size.x + cell_size * 2.0, center.y), Vector2(center.x, -cell_size * 2.0), Vector2(center.x, map_size.y + cell_size * 2.0)]:
			var ray := PhysicsRayQueryParameters2D.create(center, target, 1)
			var hit := space.intersect_ray(ray)
			_check(not hit.is_empty() and hit.get("collider") == boundary, "A cardinal escape route is blocked or a perimeter wall is missing toward %s." % target)
	_validate_accessibility(space, ground, dimensions, cell_size)
	_finish()


func _validate_cover_collision(space: PhysicsDirectSpaceState2D, layer: TileMapLayer) -> void:
	var cover_verified := false
	for cell in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data == null or not data.get_custom_data("blocks_movement"):
			continue
		# Query the actual polygon center, including the lower trunk of a tree.
		var polygon := data.get_collision_polygon_points(0, 0)
		var footprint_center := Vector2.ZERO
		for point in polygon:
			footprint_center += point
		footprint_center /= polygon.size()
		var center := layer.to_global(layer.map_to_local(cell) + footprint_center)
		var offset := Vector2(layer.tile_set.tile_size.x * layer.scale.x * 0.45, 0.0)
		var query := PhysicsRayQueryParameters2D.create(center - offset, center + offset, 1)
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit.get("collider") == layer:
			cover_verified = true
			break
	_check(cover_verified, "No collidable prop on %s produced a physics hit." % layer.name)


func _validate_accessibility(space: PhysicsDirectSpaceState2D, ground: TileMapLayer, dimensions: Vector2i, cell_size: int) -> void:
	# Test a 24px-wide actor at the default 64px tile scale, using real physics shapes.
	var circle := CircleShape2D.new()
	circle.radius = cell_size * 0.1875
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 1
	var walkable: Dictionary[Vector2i, bool] = {}
	for y in dimensions.y:
		for x in dimensions.x:
			var cell := Vector2i(x, y)
			query.transform = Transform2D(0.0, ground.to_global(ground.map_to_local(cell)))
			if space.intersect_shape(query, 1).is_empty():
				walkable[cell] = true
	var start := Vector2i(dimensions.x / 2, dimensions.y / 2)
	if not walkable.has(start):
		_fail("The central floor cell is blocked for the test actor.")
		return
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for step in CARDINALS:
			var neighbor: Vector2i = current + step
			if walkable.has(neighbor) and not reached.has(neighbor):
				reached[neighbor] = true
				queue.append(neighbor)
	for target in [Vector2i(1, start.y), Vector2i(dimensions.x - 2, start.y), Vector2i(start.x, 1), Vector2i(start.x, dimensions.y - 2)]:
		_check(reached.has(target), "No connected floor route from spawn to %s." % target)
	_check(reached.size() == walkable.size(), "Some walkable floor cells are disconnected from the central arena.")
	print("Accessible floor centers for a %.0fpx-diameter actor: %d/%d" % [circle.radius * 2.0, reached.size(), walkable.size()])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: saved atlas references, full ground, clear spawn, cover collisions, four boundaries and connected arena paths.")
		quit(0)
	else:
		print("FAIL: %d arena validation issue(s)." % failures.size())
		quit(1)
