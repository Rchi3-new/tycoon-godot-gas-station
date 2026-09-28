class_name EndlessCity
extends Node2D
## Endless post-Soviet city streamed around a target, like a Vampire Survivors
## stage: the map never ends, chunks are built ahead of the camera and freed
## behind it, and the same seed always rebuilds the same streets.
##
## Each chunk is ROAD_CELLS of road along its west and north edges plus one
## BlockPattern (an editable 18 x 18 cell scene) in the remaining square, so the
## roads join into one unbroken grid across the whole world.

const CELL_SIZE := 64
const ROAD_CELLS := 5
const CENTER_LANE := 2
const CHUNK_CELLS := ROAD_CELLS + BlockPattern.SIZE_CELLS
const CHUNK_SIZE := CELL_SIZE * CHUNK_CELLS

const GROUND_SOURCE := 0
const PROPS_SOURCE := 1
const H_DASH := Vector2i(0, 3)
const V_DASH := Vector2i(1, 3)
const CROSSWALK := Vector2i(2, 3)
const CAR := Vector2i(0, 2)
const BARRIER_H := Vector2i(0, 0)
const BARREL := Vector2i(2, 1)
const TIRES := Vector2i(3, 1)
## Road surface tiles (asphalt variants, then wear details) and their frequency.
const ROAD_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 3),
]
const ROAD_WEIGHTS: Array[float] = [70.0, 14.0, 8.0, 2.0, 1.5, 1.5, 1.5, 1.0, 0.5]
const WRECK_CHANCE := 0.25
const BARRICADE_CHANCE := 0.2
const SALT_BLOCK := 0x51ab
const SALT_STREET := 0x7ea4

@export var tile_set: TileSet
## Block scenes (root script BlockPattern), picked per chunk by their weight.
@export var block_patterns: Array[PackedScene] = []
## Same seed, same city. Change it for a different stage layout.
@export var world_seed: int = 1945
## Node the city streams around, usually the player. Without one, the camera view is used.
@export var target: Node2D
## Extra world pixels kept built around the visible rectangle.
@export var stream_margin: float = 384.0
## Chunks built per frame while streaming; each takes about a millisecond.
@export_range(1, 16) var chunk_builds_per_frame: int = 1

var _chunks: Dictionary[Vector2i, Node2D] = {}
var _weights := PackedFloat32Array()
var _road_weights := PackedFloat32Array(ROAD_WEIGHTS)
var _spawn_pattern := -1


func _ready() -> void:
	if tile_set == null or block_patterns.is_empty():
		push_error("EndlessCity needs a TileSet and at least one block pattern.")
		set_process(false)
		return
	for index in block_patterns.size():
		var pattern := block_patterns[index].instantiate() as BlockPattern
		if pattern == null:
			push_error("Block pattern %d must use block_pattern.gd on its root." % index)
			set_process(false)
			return
		_weights.append(pattern.weight)
		if pattern.spawn_safe and _spawn_pattern < 0:
			_spawn_pattern = index
		pattern.free()
	_spawn_pattern = maxi(_spawn_pattern, 0)
	# Deferred so the owning scene can move the target to the spawn point first.
	stream_all.call_deferred()


func _process(_delta: float) -> void:
	_stream(chunk_builds_per_frame)


## Centre of chunk (0, 0)'s block: the clear square every run starts in.
func get_spawn_position() -> Vector2:
	return Vector2.ONE * (ROAD_CELLS + BlockPattern.SIZE_CELLS * 0.5) * CELL_SIZE


## Builds every chunk the current view needs at once, e.g. after a teleport.
func stream_all() -> void:
	_stream(0)


## The loaded chunk at the given chunk coordinates, or null.
func get_chunk(coords: Vector2i) -> Node2D:
	return _chunks.get(coords)


static func chunk_coords_at(local_position: Vector2) -> Vector2i:
	return Vector2i((local_position / CHUNK_SIZE).floor())


## Budget 0 builds everything missing; otherwise the nearest chunks go first.
func _stream(budget: int) -> void:
	var area := _stream_rect()
	var first := chunk_coords_at(area.position)
	var last := chunk_coords_at(area.end)
	# One chunk of hysteresis stops chunks thrashing while the target walks along a seam.
	var keep := Rect2i(first - Vector2i.ONE, last - first + Vector2i(3, 3))
	for coords: Vector2i in _chunks.keys():
		if not keep.has_point(coords):
			_chunks[coords].queue_free()
			_chunks.erase(coords)
	var missing: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not _chunks.has(Vector2i(x, y)):
				missing.append(Vector2i(x, y))
	if budget > 0 and missing.size() > budget:
		missing.sort_custom(_is_closer.bind(area.get_center()))
		missing.resize(budget)
	for coords in missing:
		_chunks[coords] = _build_chunk(coords)


func _stream_rect() -> Rect2:
	var viewport := get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	view = get_global_transform().affine_inverse() * view
	if is_instance_valid(target):
		view.position = to_local(target.global_position) - view.size * 0.5
	return view.grow(stream_margin)


func _is_closer(a: Vector2i, b: Vector2i, point: Vector2) -> bool:
	var half := Vector2.ONE * CHUNK_SIZE * 0.5
	return (Vector2(a * CHUNK_SIZE) + half).distance_squared_to(point) < (Vector2(b * CHUNK_SIZE) + half).distance_squared_to(point)


func _build_chunk(coords: Vector2i) -> Node2D:
	var chunk := Node2D.new()
	chunk.name = "Chunk_%d_%d" % [coords.x, coords.y]
	chunk.position = Vector2(coords * CHUNK_SIZE)
	chunk.y_sort_enabled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(coords, SALT_STREET)
	_paint_street(_add_layer(chunk, "Street", 1, -10, false), rng)
	var block := block_patterns[_pick_pattern(coords)].instantiate() as Node2D
	block.position = Vector2.ONE * ROAD_CELLS * CELL_SIZE
	chunk.add_child(block)
	_add_road_props(chunk, rng)
	add_child(chunk)
	return chunk


func _pick_pattern(coords: Vector2i) -> int:
	if coords == Vector2i.ZERO:
		return _spawn_pattern
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(coords, SALT_BLOCK)
	return maxi(rng.rand_weighted(_weights), 0)


## Crosswalks line up with the block sidewalks on both sides of each intersection.
func _paint_street(street: TileMapLayer, rng: RandomNumberGenerator) -> void:
	var last := CHUNK_CELLS - 1
	for y in CHUNK_CELLS:
		for x in CHUNK_CELLS:
			var vertical := x < ROAD_CELLS
			var horizontal := y < ROAD_CELLS
			if not (vertical or horizontal):
				continue
			var cell := Vector2i(x, y)
			if vertical and horizontal:
				_set_asphalt(street, cell, rng)
			elif horizontal and (x == ROAD_CELLS or x == last):
				street.set_cell(cell, GROUND_SOURCE, CROSSWALK)
			elif vertical and (y == ROAD_CELLS or y == last):
				street.set_cell(cell, GROUND_SOURCE, CROSSWALK, TileSetAtlasSource.TRANSFORM_TRANSPOSE)
			elif horizontal and y == CENTER_LANE and x % 2 == 1:
				street.set_cell(cell, GROUND_SOURCE, H_DASH)
			elif vertical and x == CENTER_LANE and y % 2 == 1:
				street.set_cell(cell, GROUND_SOURCE, V_DASH)
			else:
				_set_asphalt(street, cell, rng)


func _set_asphalt(street: TileMapLayer, cell: Vector2i, rng: RandomNumberGenerator) -> void:
	# Any mix of flip_h, flip_v and transpose: flat ground reads the same from every side.
	var flips := rng.randi_range(0, 7) * TileSetAtlasSource.TRANSFORM_FLIP_H
	street.set_cell(cell, GROUND_SOURCE, ROAD_TILES[rng.rand_weighted(_road_weights)], flips)


## Occasional wrecks and roadblocks break up the avenues but always leave
## at least two lanes open for kiting.
func _add_road_props(chunk: Node2D, rng: RandomNumberGenerator) -> void:
	if rng.randf() < WRECK_CHANCE:
		# One 3x cell covers 3 x 3 ground cells: the west lanes of the vertical road.
		var wrecks := _add_layer(chunk, "RoadWrecks", 3, 0, true)
		wrecks.set_cell(Vector2i(0, rng.randi_range(2, 6)), PROPS_SOURCE, CAR)
	if rng.randf() < BARRICADE_CHANCE:
		var props := _add_layer(chunk, "RoadProps", 1, 0, true)
		var x := rng.randi_range(8, 16)
		var lane := 1 if rng.randf() < 0.5 else 3
		props.set_cell(Vector2i(x, lane), PROPS_SOURCE, BARRIER_H)
		props.set_cell(Vector2i(x + 1, lane), PROPS_SOURCE, BARRIER_H)
		props.set_cell(Vector2i(x + 3, lane), PROPS_SOURCE, BARREL if rng.randf() < 0.5 else TIRES)


func _add_layer(parent: Node2D, layer_name: String, cell_scale: int, z: int, props: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.scale = Vector2.ONE * cell_scale
	layer.z_index = z
	# Props sort against characters by Y and collide on physics layer 1; ground does neither.
	layer.y_sort_enabled = props
	layer.collision_enabled = props
	layer.navigation_enabled = false
	parent.add_child(layer)
	return layer


func _hash(coords: Vector2i, salt: int) -> int:
	return _mix(_mix(_mix(world_seed ^ salt) ^ coords.x) ^ coords.y)


## 32-bit integer hash. The masks keep every product below 2^63, so nothing overflows.
static func _mix(value: int) -> int:
	var x := value & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	return (x >> 16) ^ x
