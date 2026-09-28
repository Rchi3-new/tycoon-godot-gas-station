extends SceneTree
## One-shot authoring tool: writes the starter BlockPattern scenes that EndlessCity
## places into its chunks. Each layout below is an 18 x 18 ASCII grid.
## godot --headless --path . --script res://scripts/tools/build_block_patterns.gd
## Rebuilding REPLACES scenes/level/blocks/<name>.tscn for every name listed here,
## so copy hand-painted blocks to a new name first.
##
## Ground grid: a asphalt, p paving, P cracked paving, g grass, d dirt. These
## put an opaque detail tile over asphalt: o pothole, w puddle, f leaves,
## v gravel, x oil, m manhole, - / | lane dash, z crosswalk.
## Props grid: = / ! barrier horizontal / vertical, s sandbags, c crates,
## r / R brick / concrete rubble, b barrel, t tires, v vent, l streetlamp,
## p pallet. Big props mark their top-left cell and fill the rest of their
## footprint with +: C car, S bus shelter, K kiosk (3x3, top-left on a
## multiple of 3); T tree, B bush (2x2, top-left on even cells).
## Rubble, pallets and bushes are passable; everything else blocks.

const TILESET_PATH := "res://resources/tilesets/survivors_street.tres"
const OUTPUT_DIR := "res://scenes/level/blocks"
const SIZE := BlockPattern.SIZE_CELLS
const GROUND_SOURCE := 0
const PROPS_SOURCE := 1
const ASPHALT := Vector2i(0, 0)
const GROUND_TILES := {
	"a": Vector2i(0, 0), "p": Vector2i(0, 2), "P": Vector2i(1, 2), "g": Vector2i(3, 2), "d": Vector2i(2, 2),
}
const DETAIL_TILES := {
	"o": Vector2i(0, 1), "w": Vector2i(1, 1), "f": Vector2i(2, 1), "v": Vector2i(3, 1), "x": Vector2i(3, 0),
	"m": Vector2i(3, 3), "-": Vector2i(0, 3), "|": Vector2i(1, 3), "z": Vector2i(2, 3),
}
## Markings have a direction, so only these details get random flips.
const FLIPPABLE_DETAILS := "owfvxm"
const PROP_TILES := {
	"=": ["Obstacles", Vector2i(0, 0)], "!": ["Obstacles", Vector2i(1, 0)],
	"s": ["Obstacles", Vector2i(2, 0)], "c": ["Obstacles", Vector2i(3, 0)],
	"r": ["Obstacles", Vector2i(0, 1)], "R": ["Obstacles", Vector2i(1, 1)],
	"b": ["Obstacles", Vector2i(2, 1)], "t": ["Obstacles", Vector2i(3, 1)],
	"v": ["Obstacles", Vector2i(1, 3)], "l": ["Obstacles", Vector2i(2, 3)],
	"p": ["Obstacles", Vector2i(3, 3)],
	"C": ["Landmarks", Vector2i(0, 2)], "S": ["Landmarks", Vector2i(1, 2)], "K": ["Landmarks", Vector2i(0, 3)],
	"T": ["Foliage", Vector2i(2, 2)], "B": ["Foliage", Vector2i(3, 2)],
}
## Layer name: [cell scale, z_index, holds props].
const LAYERS := {
	"Ground": [1, -10, false], "Details": [1, -9, false],
	"Obstacles": [1, 0, true], "Landmarks": [3, 0, true], "Foliage": [2, 0, true],
}

const PATTERNS: Array[Dictionary] = [
	{
		# The open field: flower beds in the corners, nothing blocking near the centre.
		"name": "plaza", "weight": 3.0, "spawn_safe": true,
		"ground": [
			"pppppppppppppppppp",
			"pggggaaaaaaaaggggp",
			"pggggaaaafaaaggggp",
			"pggggaaoaaaaaggggp",
			"pggggaaaaaaaaggggp",
			"paaaaaaaaaaaaawaap",
			"paafaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaamaaaaaaap",
			"paaaaaaaaaaaaoaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaawaaaaaaaaaaap",
			"paaaaaaaaaavaaaaap",
			"pggggaaaaaaaaggggp",
			"pggggaaaxaaaaggggp",
			"pggggaaaaaaaaggggp",
			"pggggaaaaaafaggggp",
			"pppppppppppppppppp",
		],
		"props": [
			"....l........l....",
			"..................",
			"..B+..........B+..",
			"..++..........++..",
			"l................l",
			"......r...........",
			"..............p...",
			"..................",
			"..................",
			"..................",
			"...R..............",
			".............r....",
			"..................",
			"l................l",
			"..B+..........B+..",
			"..++..........++..",
			"..................",
			"....l........l....",
		],
	},
	{
		# Two rows of wrecks in painted bays around a wide central aisle.
		"name": "parking", "weight": 2.0, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paa|aa|aa|aa|aa|ap",
			"paa|aa|aa|xa|aa|ap",
			"paa|aa|aa|aa|aa|ap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaoaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaawaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paa|aa|aa|aa|aa|ap",
			"paa|aa|xa|aa|aa|ap",
			"paa|aa|aa|aa|aa|ap",
			"paaaaaaaaaaaaaaaap",
			"paafaaaaaaaaaaaaap",
			"pppppppppppppppppp",
		],
		"props": [
			".........l........",
			".b................",
			"..................",
			"...C++C++...C++...",
			"...++++++...+++...",
			"...++++++...+++...",
			"..................",
			"...............t..",
			"l................l",
			"..................",
			"..c...............",
			"..................",
			"...C++...C++C++...",
			"...+++...++++++...",
			"...+++...++++++...",
			"................b.",
			".t................",
			".........l........",
		],
	},
	{
		# Trolleybus stop: shelters on the south sidewalk face the next road.
		"name": "bus_stop", "weight": 2.0, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaafaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaoaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"p-a-a-a-a-a-a-a-ap",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
		],
		"props": [
			"..................",
			"..................",
			"..................",
			"..b.........K++...",
			"............+++p..",
			"............+++...",
			"l..........c.....l",
			"..................",
			"..................",
			"..................",
			"..................",
			"..................",
			"..T+..B+..B+..T+..",
			"..++..++..++..++..",
			"..................",
			"...S++..l...S++...",
			"...+++......+++...",
			"...+++......+++...",
		],
	},
	{
		# Four sandbag nests on dirt and a broken barrier ring with open corners.
		"name": "checkpoint", "weight": 1.5, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"paaaaaaaaaaaaaaaap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"paaavaaaaaaaxaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaoaaaaaaap",
			"paaaaxaaaaaaaaaaap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"padddddaaaadddddap",
			"paaaaaaaaaaaaaaaap",
			"pppppppppppppppppp",
		],
		"props": [
			"..................",
			".b................",
			"..................",
			"...sss......sss...",
			"...s..........s...",
			"...s.c......b.s...",
			"........==........",
			"..................",
			"......!....!......",
			"......!....!......",
			"..................",
			"........==........",
			"...s.t......c.s...",
			"...s..........s...",
			"...sss......sss...",
			"..................",
			"................b.",
			"..................",
		],
	},
	{
		# Courtyard park: trees and bushes around a paved cross with lamps.
		"name": "park", "weight": 2.0, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgddggggp",
			"pgggggggppgdgggggp",
			"pgggggggppgggggggp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pgggggggppgggggggp",
			"pgggddggppgggggggp",
			"pggggdggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pgggggggppgggggggp",
			"pppppppppppppppppp",
		],
		"props": [
			"..................",
			"..................",
			"..T+..T+..B+T+....",
			"..++..++..++++....",
			"l................l",
			"..................",
			"..T+B+......B+T+..",
			"..++++.l..l.++++..",
			"..................",
			"..................",
			".......l..l...B+..",
			"..............++..",
			"..T+........T+....",
			"l.++........++...l",
			"....B+T+......T+..",
			"....++++......++..",
			"..................",
			"..................",
		],
	},
	{
		# Kiosk rows on paving with stock piled around them; the aisle stays open.
		"name": "market", "weight": 1.5, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"paaaaaaaaaaaaaaaap",
			"paaafaaaaaaaaaaaap",
			"paaaaaaaaaxaaaaaap",
			"paaaaavaaaaaaaaaap",
			"paaaaaaaaaaaaoaaap",
			"paaaaaaaaaaaaaaaap",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
			"pppppppppppppppppp",
		],
		"props": [
			".........l........",
			"..................",
			"..................",
			".t.K++K++...K++...",
			"...++++++c..+++b..",
			"...++++++.p.+++...",
			"..................",
			"..................",
			"..................",
			"l................l",
			"..................",
			"..................",
			"...K++...K++K++...",
			"...+++c..++++++b..",
			".c.+++.p.++++++...",
			"..................",
			"..................",
			"........l.........",
		],
	},
	{
		# Shelled lot: mostly passable rubble, a few concrete stubs and one wreck.
		"name": "ruins", "weight": 1.5, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"pddddddddPPPPPPPPp",
			"pddddddddPPPPPPPPp",
			"pdddgddddPPPPPPPPp",
			"pddddddddPPPgPPPPp",
			"pddddddddPPPPPPPPp",
			"paaaaaaaaaaaaaaaap",
			"pvaaaaaaoaaaaaaavp",
			"paaaaaaaaaaaaaaaap",
			"paaavaaaaaaaaaaaap",
			"paaaaaaaaaaoaaaaap",
			"paaaaaaaaaaaaaaaap",
			"pPPPPPPPPggggggggp",
			"pPPPPPPPPgggddgggp",
			"pPPPPPPPPggddddggp",
			"pPPPPPPPPggggggggp",
			"pPPPPPPPPggggggggp",
			"pppppppppppppppppp",
		],
		"props": [
			"..................",
			"......R...........",
			"..r..........v..b.",
			"...v.......R......",
			".......r..........",
			"...............r..",
			"....==...C++......",
			".........+++......",
			".........+++...!..",
			".......r......R...",
			".R................",
			"................r.",
			"...r..............",
			"..........p...v...",
			".....v............",
			"..t.....R...r.....",
			"..................",
			"..................",
		],
	},
	{
		# A barrier wall across the block with two gaps: a Survivors chokepoint.
		"name": "barricade", "weight": 1.0, "spawn_safe": false,
		"ground": [
			"pppppppppppppppppp",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaoaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaaaxaaap",
			"paaaaaaaaaaaaaaaap",
			"paavaaaaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"pddddddddddddddddp",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaaavaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaoaaaaaaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paaaaaaaaaawaaaaap",
			"paaaaaaaaaaaaaaaap",
			"paafaaaaaaaaaaaaap",
			"pppppppppppppppppp",
		],
		"props": [
			"..................",
			"..................",
			"..................",
			"........t.........",
			"l..c.........!...l",
			".............!....",
			"..................",
			"..................",
			".====..====..====.",
			"..................",
			"..................",
			"..................",
			"....!.........c...",
			"l...!....b.......l",
			"..................",
			"..................",
			"..................",
			"..................",
		],
	},
]

var failed := false


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var tile_set := load(TILESET_PATH) as TileSet
	if tile_set == null:
		push_error("Import the project first: %s did not load." % TILESET_PATH)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for spec in PATTERNS:
		var block := _build_block(spec, tile_set)
		if block == null:
			continue
		var packed := PackedScene.new()
		var error := packed.pack(block)
		if error == OK:
			error = ResourceSaver.save(packed, "%s/%s.tscn" % [OUTPUT_DIR, spec.name])
		if error != OK:
			_fail("%s: cannot save scene (%s)." % [spec.name, error_string(error)])
		else:
			print("Saved %s/%s.tscn: %d obstacle, %d landmark, %d foliage cells" % [
				OUTPUT_DIR, spec.name, block.get_node("Obstacles").get_used_cells().size(),
				block.get_node("Landmarks").get_used_cells().size(), block.get_node("Foliage").get_used_cells().size()])
		block.free()
	quit(1 if failed else 0)


func _build_block(spec: Dictionary, tile_set: TileSet) -> BlockPattern:
	var ground_rows: Array = spec.ground
	var prop_rows: Array = spec.props
	for rows in [ground_rows, prop_rows]:
		if rows.size() != SIZE or rows.any(func(row: String) -> bool: return row.length() != SIZE):
			_fail("%s: every grid must be %d rows of %d characters." % [spec.name, SIZE, SIZE])
			return null
	var block := BlockPattern.new()
	block.name = String(spec.name).to_pascal_case()
	block.weight = spec.weight
	block.spawn_safe = spec.spawn_safe
	block.y_sort_enabled = true
	var layers: Dictionary[String, TileMapLayer] = {}
	for layer_name: String in LAYERS:
		var settings: Array = LAYERS[layer_name]
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tile_set
		layer.scale = Vector2.ONE * settings[0]
		layer.z_index = settings[1]
		layer.y_sort_enabled = settings[2]
		layer.collision_enabled = settings[2]
		layer.navigation_enabled = false
		block.add_child(layer)
		layer.owner = block
		layers[layer_name] = layer
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec.name)
	_paint_ground(spec.name, ground_rows, layers.Ground, layers.Details, rng)
	_paint_props(spec.name, prop_rows, layers)
	if failed:
		block.free()
		return null
	return block


func _paint_ground(pattern: String, rows: Array, ground: TileMapLayer, details: TileMapLayer, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var key: String = rows[y][x]
			var cell := Vector2i(x, y)
			if DETAIL_TILES.has(key):
				ground.set_cell(cell, GROUND_SOURCE, ASPHALT, _flips(rng))
				var flips := _flips(rng) if FLIPPABLE_DETAILS.contains(key) else 0
				details.set_cell(cell, GROUND_SOURCE, DETAIL_TILES[key], flips)
			elif GROUND_TILES.has(key):
				ground.set_cell(cell, GROUND_SOURCE, _surface(key, rng), _flips(rng))
			else:
				_fail("%s: unknown ground character '%s' at %s." % [pattern, key, cell])


## Plain asphalt and paving get worn variants so large areas do not tile visibly.
func _surface(key: String, rng: RandomNumberGenerator) -> Vector2i:
	match key:
		"a":
			return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)][rng.rand_weighted(PackedFloat32Array([74.0, 16.0, 10.0]))]
		"p":
			return Vector2i(1, 2) if rng.randf() < 0.18 else Vector2i(0, 2)
	return GROUND_TILES[key]


func _flips(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 7) * TileSetAtlasSource.TRANSFORM_FLIP_H


func _paint_props(pattern: String, rows: Array, layers: Dictionary[String, TileMapLayer]) -> void:
	var covered: Dictionary[Vector2i, bool] = {}
	for y in SIZE:
		for x in SIZE:
			var key: String = rows[y][x]
			if key == "." or key == "+":
				continue
			if not PROP_TILES.has(key):
				_fail("%s: unknown prop character '%s' at %s." % [pattern, key, Vector2i(x, y)])
				continue
			var layer_name: String = PROP_TILES[key][0]
			var span: int = LAYERS[layer_name][0]
			if x % span != 0 or y % span != 0:
				_fail("%s: '%s' at %s must start on a multiple of %d." % [pattern, key, Vector2i(x, y), span])
				continue
			for dy in span:
				for dx in span:
					var cell := Vector2i(x + dx, y + dy)
					if cell.x >= SIZE or cell.y >= SIZE or covered.has(cell):
						_fail("%s: '%s' at %s overlaps another prop or the block edge." % [pattern, key, Vector2i(x, y)])
					elif (dx > 0 or dy > 0) and rows[cell.y][cell.x] != "+":
						_fail("%s: '%s' at %s must fill its footprint with '+'." % [pattern, key, Vector2i(x, y)])
					covered[cell] = true
			layers[layer_name].set_cell(Vector2i(x, y) / span, PROPS_SOURCE, PROP_TILES[key][1])
	for y in SIZE:
		for x in SIZE:
			if rows[y][x] == "+" and not covered.has(Vector2i(x, y)):
				_fail("%s: stray '+' at %s." % [pattern, Vector2i(x, y)])


func _fail(message: String) -> void:
	failed = true
	push_error(message)
