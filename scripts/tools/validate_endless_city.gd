extends SceneTree
## Validates the endless city with real physics queries: the BlockPattern
## contract, Vampire Survivors openness (walkable share, no sealed pockets,
## horde-wide lanes to every intersection), a clear spawn, chunk unloading
## and deterministic rebuilds.
## godot --headless --path . --script res://scripts/tools/validate_endless_city.gd

const CITY_SCENE := "res://scenes/level/endless_city.tscn"
const CELL := EndlessCity.CELL_SIZE
const ACTOR_RADIUS := 12.0
## A shoulder-to-shoulder clump of enemies must still flow between intersections.
const HORDE_RADIUS := 28.0
const SPAWN_CLEARANCE := 256.0
const MIN_BLOCK_WALKABLE := 0.8
const MIN_CITY_WALKABLE := 0.88
## Layer name: [cell scale, z_index, holds props (Y-sorted and colliding)].
const LAYERS := {
	"Ground": [1, -10, false], "Details": [1, -9, false],
	"Obstacles": [1, 0, true], "Landmarks": [3, 0, true], "Foliage": [2, 0, true],
}
const CARDINALS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var failures: Array[String] = []


func _initialize() -> void:
	_validate.call_deferred()


func _validate() -> void:
	var packed := load(CITY_SCENE) as PackedScene
	var city: EndlessCity = null
	if packed != null:
		city = packed.instantiate() as EndlessCity
	if city == null:
		_fail("%s must load with endless_city.gd on its root." % CITY_SCENE)
		_finish()
		return
	_check(not city.block_patterns.is_empty(), "EndlessCity has no block patterns.")
	# Each pattern alone in the physics world, then the streamed city.
	for scene in city.block_patterns:
		await _validate_block(scene, city.tile_set)
	var anchor := Node2D.new()
	root.add_child(anchor)
	var spawn := city.get_spawn_position()
	anchor.position = spawn
	city.target = anchor
	root.add_child(city)
	var started := Time.get_ticks_usec()
	city.stream_all()
	var built := city.get_child_count()
	print("Streamed %d chunks around spawn in %.1f ms (%.2f ms per chunk)." % [
		built, (Time.get_ticks_usec() - started) / 1000.0, (Time.get_ticks_usec() - started) / 1000.0 / maxi(built, 1)])
	await physics_frame
	await physics_frame
	var space := root.get_world_2d().direct_space_state
	_validate_chunks(city)
	_check(_blockers_near(space, spawn, SPAWN_CLEARANCE) == 0, "Something blocks movement within %d px of the spawn." % SPAWN_CLEARANCE)
	_validate_openness(space, spawn)
	await _validate_streaming(city, anchor, spawn)
	_validate_seed(city)
	_finish()


func _validate_block(scene: PackedScene, tile_set: TileSet) -> void:
	var label := scene.resource_path.get_file().get_basename()
	var block := scene.instantiate() as BlockPattern
	if block == null:
		_fail("%s: root must use block_pattern.gd." % label)
		return
	root.add_child(block)
	_check(block.y_sort_enabled, "%s: root must be Y-sorted so props sort against characters." % label)
	_check(block.weight > 0.0, "%s: weight must be positive or the pattern never appears." % label)
	var size := BlockPattern.SIZE_CELLS
	var footprint := Rect2(Vector2.ZERO, Vector2.ONE * size * CELL)
	for layer_name: String in LAYERS:
		var layer := block.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			_fail("%s: missing TileMapLayer %s." % [label, layer_name])
			continue
		var spec: Array = LAYERS[layer_name]
		_check(layer.scale == Vector2.ONE * spec[0], "%s/%s: scale must be %d." % [label, layer_name, spec[0]])
		_check(layer.z_index == spec[1], "%s/%s: z_index must be %d." % [label, layer_name, spec[1]])
		_check(layer.y_sort_enabled == spec[2] and layer.collision_enabled == spec[2], "%s/%s: Y-sort and collision must both be %s." % [label, layer_name, spec[2]])
		_check(layer.tile_set == tile_set, "%s/%s: must use the shared street TileSet." % [label, layer_name])
		for cell in layer.get_used_cells():
			_check(layer.get_cell_tile_data(cell) != null, "%s/%s: cell %s references a missing tile." % [label, layer_name, cell])
			var rect := Rect2(layer.position + Vector2(cell * CELL) * layer.scale, Vector2.ONE * CELL * layer.scale)
			_check(footprint.encloses(rect), "%s/%s: cell %s spills outside the %dx%d footprint." % [label, layer_name, cell, size, size])
	var ground := block.get_node_or_null("Ground") as TileMapLayer
	if ground != null:
		_check(ground.position == Vector2.ZERO and ground.get_used_cells().size() == size * size, "%s: Ground must fill all %d cells from the origin." % [label, size * size])
	await physics_frame
	await physics_frame
	var space := root.get_world_2d().direct_space_state
	var walkable := _walkable(space, Vector2.ZERO, Vector2i.ONE * size, ACTOR_RADIUS)
	var share := float(walkable.size()) / (size * size)
	_check(share >= MIN_BLOCK_WALKABLE, "%s: only %d%% walkable; keep blocks at least %d%% open." % [label, share * 100, MIN_BLOCK_WALKABLE * 100])
	if not walkable.is_empty():
		var reached := _flood(walkable, walkable.keys()[0])
		_check(reached.size() == walkable.size(), "%s: %d walkable cells are sealed off from the rest." % [label, walkable.size() - reached.size()])
		for side in [Rect2i(0, 0, size, 1), Rect2i(0, size - 1, size, 1), Rect2i(0, 0, 1, size), Rect2i(size - 1, 0, 1, size)]:
			_check(reached.keys().any(func(cell: Vector2i) -> bool: return side.has_point(cell)), "%s: side %s cannot be reached." % [label, side])
	if block.spawn_safe:
		_check(_blockers_near(space, footprint.get_center(), SPAWN_CLEARANCE) == 0, "%s: spawn_safe but something blocks near its centre." % label)
	print("%s: %d%% walkable for a %dpx actor, weight %.1f%s" % [label, roundi(share * 100), ACTOR_RADIUS * 2, block.weight, ", spawn safe" if block.spawn_safe else ""])
	block.free()
	await physics_frame


func _validate_chunks(city: EndlessCity) -> void:
	var road_cells := EndlessCity.ROAD_CELLS * EndlessCity.CHUNK_CELLS * 2 - EndlessCity.ROAD_CELLS * EndlessCity.ROAD_CELLS
	for y in range(-1, 2):
		for x in range(-1, 2):
			var chunk := city.get_chunk(Vector2i(x, y))
			if chunk == null:
				_fail("Chunk %s around the spawn was not streamed in." % Vector2i(x, y))
				continue
			var street := chunk.get_node_or_null("Street") as TileMapLayer
			_check(street != null and street.get_used_cells().size() == road_cells, "Chunk %s: roads must cover exactly the west and north bands." % Vector2i(x, y))
			var blocks := chunk.get_children().filter(func(child: Node) -> bool: return child is BlockPattern)
			_check(blocks.size() == 1 and blocks[0].position == Vector2.ONE * EndlessCity.ROAD_CELLS * CELL, "Chunk %s: needs one block placed just inside its roads." % Vector2i(x, y))
	var spawn_block := city.get_chunk(Vector2i.ZERO).get_children().filter(func(child: Node) -> bool: return child is BlockPattern)
	_check(not spawn_block.is_empty() and spawn_block[0].spawn_safe, "Chunk (0, 0) must use a spawn_safe block.")


## The 3 x 3 chunks around spawn, seams included, must play like an open Survivors field.
func _validate_openness(space: PhysicsDirectSpaceState2D, spawn: Vector2) -> void:
	var origin := -Vector2.ONE * EndlessCity.CHUNK_SIZE
	var size := Vector2i.ONE * EndlessCity.CHUNK_CELLS * 3
	var start := Vector2i((spawn - origin) / CELL)
	var walkable := _walkable(space, origin, size, ACTOR_RADIUS)
	var reached := _flood(walkable, start)
	var share := float(walkable.size()) / (size.x * size.y)
	_check(share >= MIN_CITY_WALKABLE, "City is only %d%% walkable around spawn." % roundi(share * 100))
	_check(reached.size() == walkable.size(), "%d walkable city cells are sealed off from the spawn." % (walkable.size() - reached.size()))
	var horde := _flood(_walkable(space, origin, size, HORDE_RADIUS), start)
	for y in 3:
		for x in 3:
			var intersection := Vector2i(x, y) * EndlessCity.CHUNK_CELLS + Vector2i.ONE * EndlessCity.CENTER_LANE
			_check(horde.has(intersection), "A %dpx horde cannot reach intersection %s from spawn." % [HORDE_RADIUS * 2, intersection])
	print("City around spawn: %d%% walkable, %d/%d cells connected, horde lanes reach all 9 intersections." % [roundi(share * 100), reached.size(), walkable.size()])


func _validate_streaming(city: EndlessCity, anchor: Node2D, spawn: Vector2) -> void:
	var probe := Vector2i(1, -1)
	var before := _snapshot(city.get_chunk(probe))
	for step in [Vector2(30, 0), Vector2(-30, 25)]:
		anchor.position = spawn + step * EndlessCity.CHUNK_SIZE
		city.stream_all()
		await process_frame
		var here := EndlessCity.chunk_coords_at(anchor.position)
		_check(city.get_chunk(here) != null, "No chunk was built at %s; the map must never end." % here)
		_check(city.get_chunk(probe) == null, "Chunk %s was not unloaded after the target left." % probe)
		_check(city.get_child_count() <= 25, "%d chunks stayed loaded; streaming leaks chunks." % city.get_child_count())
	anchor.position = spawn
	city.stream_all()
	_check(before == _snapshot(city.get_chunk(probe)), "Chunk %s rebuilt differently; generation must be deterministic." % probe)


func _validate_seed(city: EndlessCity) -> void:
	var counts: Dictionary[int, int] = {}
	var picks: Array[int] = []
	for y in range(-20, 20):
		for x in range(-20, 20):
			var pick := city._pick_pattern(Vector2i(x, y))
			picks.append(pick)
			counts[pick] = counts.get(pick, 0) + 1
	var original := city.world_seed
	city.world_seed += 1
	var changed := 0
	var index := 0
	for y in range(-20, 20):
		for x in range(-20, 20):
			changed += int(city._pick_pattern(Vector2i(x, y)) != picks[index])
			index += 1
	city.world_seed = original
	_check(changed * 2 > picks.size(), "Changing world_seed barely changes the layout (%d/%d chunks)." % [changed, picks.size()])
	var shares: Array[String] = []
	for pattern in city.block_patterns.size():
		shares.append("%s %d%%" % [city.block_patterns[pattern].resource_path.get_file().get_basename(), roundi(100.0 * counts.get(pattern, 0) / picks.size())])
	print("Block mix over 1600 chunks: %s" % ", ".join(shares))


func _snapshot(chunk: Node) -> Array[String]:
	var cells: Array[String] = []
	if chunk == null:
		return cells
	for layer in chunk.find_children("*", "TileMapLayer", true, false):
		var path := String(chunk.get_path_to(layer))
		for cell in layer.get_used_cells():
			cells.append("%s %s %d %s %d" % [path, cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)])
	cells.sort()
	return cells


func _walkable(space: PhysicsDirectSpaceState2D, origin: Vector2, size: Vector2i, radius: float) -> Dictionary[Vector2i, bool]:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	var cells: Dictionary[Vector2i, bool] = {}
	for y in size.y:
		for x in size.x:
			query.transform = Transform2D(0.0, origin + (Vector2(x, y) + Vector2.ONE * 0.5) * CELL)
			if space.intersect_shape(query, 1).is_empty():
				cells[Vector2i(x, y)] = true
	return cells


func _flood(cells: Dictionary[Vector2i, bool], start: Vector2i) -> Dictionary[Vector2i, bool]:
	var reached: Dictionary[Vector2i, bool] = {}
	if not cells.has(start):
		return reached
	reached[start] = true
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for step in CARDINALS:
			var next := current + step
			if cells.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


func _blockers_near(space: PhysicsDirectSpaceState2D, point: Vector2, radius: float) -> int:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform2D(0.0, point)
	return space.intersect_shape(query, 8).size()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: block contract, open Survivors layout, clear spawn, endless streaming and deterministic chunks.")
		quit(0)
	else:
		print("FAIL: %d endless city issue(s)." % failures.size())
		quit(1)
