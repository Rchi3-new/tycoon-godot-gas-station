@tool
class_name BlockPattern
extends Node2D
## One editable city block. EndlessCity picks a pattern by weight for every chunk
## and places it just east and south of that chunk's roads.
##
## Contract, checked by scripts/tools/validate_endless_city.gd:
## - The footprint is SIZE_CELLS x SIZE_CELLS cells of 64 px from the origin.
##   Its outer ring is the sidewalk that meets the surrounding roads.
## - Ground (z -10) fills every cell; Details (z -9) holds opaque wear tiles.
## - Obstacles (1x), Landmarks (3x: cars, kiosks, shelters) and Foliage (2x: trees,
##   bushes) are Y-sorted against characters and collide on physics layer 1.
## - Keep it Vampire Survivors open: most of the block walkable, no sealed
##   pockets, and every side reachable from every other.

const SIZE_CELLS := 18
const CELL_SIZE := 64

## Relative chance of this block being picked for a chunk.
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0
## Clear around its centre, so a run can start here (used for chunk 0, 0).
@export var spawn_safe: bool = false


func _draw() -> void:
	# Editor-only footprint outline, so painting stays inside the block.
	if Engine.is_editor_hint():
		var size := Vector2.ONE * SIZE_CELLS * CELL_SIZE
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.78, 0.3), false, 4.0)
