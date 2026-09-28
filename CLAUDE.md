# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A Vampire Survivors-style top-down survival game set in a war-damaged post-Soviet city. It is built with **Godot 4.6** in **GDScript**, using the GL Compatibility renderer and a 1280x720 base viewport with `canvas_items` stretch. The config name is still "Gas Station Tycoon". Remote: `github.com/Rchi3-new/tycoon-godot-gas-station`.

F5 runs `scenes/main.tscn`: a placeholder player (`move_*` actions: WASD, arrows, gamepad) walking an endless streamed city. Enemies, weapons and pickups don't exist yet.

## Commands

The Godot editor isn't on PATH. On this machine it is at `C:\Users\gtuch\Downloads\Godot_v4.6.1-stable_mono_win64\` (use the `_console.exe` build for CLI output).

```sh
GODOT="/c/Users/gtuch/Downloads/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe"
"$GODOT" --headless --path . --import   # re-import; also registers new class_name scripts, run it after adding one
"$GODOT" --path .                        # play
"$GODOT" -e --path .                     # open in editor
"$GODOT" --headless --path . --script res://scripts/tools/validate_endless_city.gd
"$GODOT" --headless --path . --script res://scripts/tools/validate_survivors_arena.gd
"$GODOT" --headless --path . --script res://scripts/tools/build_block_patterns.gd   # OVERWRITES scenes/level/blocks/*.tscn
"$GODOT" --path . --script res://scripts/tools/capture_endless_city.gd -- --out=<absolute dir>   # PNG previews; needs a display
```

Everything in `scripts/tools/` is an `extends SceneTree` script run with `--script`. The validators check real physics queries and exit non-zero on failure. There is no unit-test framework. `build_city_patterns.gd` and `validate_city_patterns.gd` expect `art/tilesets/city_*.png` atlases that aren't in the repo, so they can't run.

## Architecture

- **Tiles.** Everything paints from `resources/tilesets/survivors_street.tres`. Source 0 is the ground atlas and source 1 the props atlas, each 4x4 with 64 px tiles; that size depends on the PNGs' `.import` `size_limit=256`, so keep those settings. Custom data: `tile_name`, `blocks_movement`. Collision is physics layer 1. `art/tilesets/README.md` has the atlas coordinate tables.
- **Big props.** They use scaled TileMapLayers: cars, kiosks and bus shelters at 3x (192 px), trees and bushes at 2x (128 px).
- **Endless city** (`scripts/level/endless_city.gd`, `EndlessCity`). The world is a grid of 23x23-cell chunks (1472 px). Each chunk has:
  - a procedural `Street` layer: a 5-cell road band along its west and north edges, with lane dashes, crosswalks and occasional wrecks or roadblocks;
  - one `BlockPattern` scene instanced at cell (5, 5).
- **Streaming.** Chunks load around `target` (view rect plus `stream_margin`), unload with one chunk of hysteresis, and build at most `chunk_builds_per_frame` per frame. All randomness hashes `world_seed` + chunk coords + a salt, so a reloaded chunk is identical. Chunk (0, 0) always uses the first `spawn_safe` pattern, and `get_spawn_position()` is its centre.
- **Block patterns** (`scenes/level/blocks/*.tscn`, root script `scripts/level/block_pattern.gd`). Each is an 18x18-cell editable scene whose outer ring is sidewalk; `weight` sets how often it is picked.
  - Layer contract: Ground z -10 and Details z -9 (no collision, not Y-sorted); Obstacles 1x, Landmarks 3x and Foliage 2x (Y-sorted, colliding).
  - The starter set is generated from the ASCII grids in `build_block_patterns.gd`.
  - A new pattern must also be added to `block_patterns` in `scenes/level/endless_city.tscn`.
- **Draw order.** `World` in `main.tscn` is Y-sorted. Every node between it and a prop layer (EndlessCity, chunk, block root) must keep `y_sort_enabled`, or props stop sorting against characters. Ground layers stay underneath through negative `z_index`.
- **Physics layers.** 1 is the environment, 2 is the player; the player masks 1.
- **Openness rules** enforced by `validate_endless_city.gd`:
  - every block is at least 80% walkable for a 24 px actor, has no sealed pockets, and all four sides are reachable;
  - the spawn is clear for 256 px;
  - a 56 px horde probe reaches every intersection;
  - chunks rebuild deterministically.
- **Older arena.** `scenes/survivors_arena.tscn` is a standalone bounded arena with a preview camera only, built by `build_survivors_arena.gd`.

## Conventions

- Commit the `*.uid` files (Godot 4.4+ writes one next to each script) and the `*.import` files. Don't commit `.godot/`, which is a regenerated cache.
- `.gitattributes` forces LF line endings. Keep `.tscn`/`.gd` files LF so Windows checkouts don't produce spurious diffs.
- Prefer editing scenes in the editor. When hand-editing `.tscn`, keep `ext_resource` ids consistent.
