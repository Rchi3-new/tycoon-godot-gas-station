# tycoon-godot-gas-station

An editable post-Soviet survivors arena is available in `scenes/survivors_arena.tscn` (Godot 4.6). Open it and press F6 to preview, pan and zoom. See [the tilemap guide](art/tilesets/README.md) for painting, atlas coordinates, collisions and regeneration.

The [city asset expansion](art/tilesets/CITY_ASSETS.md) adds 43 transparent sprites, Cyrillic signs, five-storey concrete-panel apartments with front/rear/left/right views, a yellow bus, a cream-and-red tram and everyday street objects, plus 16 tram-track ground tiles. Open `scenes/city_patterns_showcase.tscn` with F6 to inspect six reusable modules, `scenes/panel_apartment_views_showcase.tscn` for apartment views, or `scenes/tram_tracks_showcase.tscn` for connected tracks; native per-layer patterns are in `resources/patterns/`.

## Endless city

Press **F5** to walk an endless city in the style of Vampire Survivors, using a placeholder survivor (WASD, arrows or a gamepad).

- **No map edges.** A road grid runs through the whole world, and every 23 × 23-cell chunk holds one city block picked at random by weight.
- **Streaming.** Chunks stream in ahead of the camera and out behind it.
- **Repeatable.** The same `world_seed` always rebuilds the same city.

### Blocks

Blocks are editable 18 × 18-cell scenes in `scenes/level/blocks/`: plaza (the clear spawn), parking, bus stop, checkpoint, park, market, ruins and barricade.

To add a block:

1. Duplicate a block scene.
2. Paint it with the shared TileSet. Big props go on the 3× `Landmarks` and 2× `Foliage` layers.
3. Set its `weight`.
4. Add it to **Block Patterns** on `scenes/level/endless_city.tscn`.
5. Run the validator. It checks that the block stays open enough for hordes to flow through:

```text
godot --headless --path . --script res://scripts/tools/validate_endless_city.gd
```
