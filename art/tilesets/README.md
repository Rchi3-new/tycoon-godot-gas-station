# Post-Soviet survivors tilemap

An editable Godot 4.6 starter arena based on the survivors concept art. It contains terrain, street props and environment collisions; characters, enemy waves and combat are separate game systems.

## Open and paint

1. Open `res://scenes/survivors_arena.tscn` in Godot.
2. Press **F6** to preview this scene. WASD/arrows or middle drag pan; the wheel zooms; Home fits the map; H hides the help panel.
3. To edit, select a TileMapLayer, open the TileMap panel, choose a tile from the shared TileSet, and paint normally. Cells are saved in the scene, so no runtime generator is required.

The map has 40 × 30 ground cells at 64 × 64 world pixels: 2560 × 1920 overall. `PlayerSpawn` marks the clear center. The project’s existing main scene is separate; use F6 for this map.

| Layer | Purpose | World cell size |
| --- | --- | --- |
| Ground | Asphalt, sidewalk and outer verge | 64 px |
| Details | Wear, potholes, markings and drains | 64 px |
| Obstacles | Small cover, barrels and rubble | 64 px |
| Landmarks | Larger cars, kiosks and bus shelters | 192 px |
| Foliage | Trees and bushes | 128 px |

All layers share `res://resources/tilesets/survivors_street.tres`. Ground and Details use opaque surface tiles. Props use real alpha transparency. Nearest texture filtering is set on the arena root.

## Atlases

Both PNG source images have an exact 4 × 4 layout with no margin or separation. The generated source files are 1254 × 1254 pixels. Their checked-in `.png.import` settings use Godot’s **Process → Size Limit = 256**, producing 256 × 256 imported textures with **64 × 64 tiles**. Keep these import settings with the PNG files. Removing the size limit invalidates the TileSet’s atlas coordinates. Mipmaps are off and compression is lossless.

Ground source ID: **0**. Coordinates below are zero-based, from the top-left.

| Row / y | x = 0 | x = 1 | x = 2 | x = 3 |
| --- | --- | --- | --- | --- |
| 0 | Asphalt | Cracked asphalt | Chipped asphalt | Oil stain |
| 1 | Pothole | Puddle | Autumn leaves | Gravel |
| 2 | Concrete paving | Cracked paving | Dirt and grit | Muted grass |
| 3 | Horizontal lane dash | Vertical lane dash | Crosswalk stripe | Manhole |

Props source ID: **1**.

| Row / y | x = 0 | x = 1 | x = 2 | x = 3 |
| --- | --- | --- | --- | --- |
| 0 | Horizontal barrier | Vertical barrier | Sandbags | Crates |
| 1 | Brick rubble | Concrete rubble | Barrel | Tires |
| 2 | Wrecked car | Bus shelter | Autumn tree | Bush |
| 3 | Kiosk | Vent | Streetlamp | Pallet |

Each tile has `tile_name` and `blocks_movement` custom data. This is a manually paintable atlas set; it does not include terrain-connect/autotiling rules or building-wall modules.

## Collision and reuse

Environment collisions occupy physics layer **1**. Barriers, sandbags, crates, barrels, tires, cars, shelters, kiosks, vents, tree trunks and lamp bases have footprints. Loose rubble, bushes, pallets and ground details are passable. `MapBoundary` prevents leaving the map. A player body should include layer 1 in its collision mask.

To use the arena inside your game, keep its TileMapLayers, boundary and spawn marker, and remove or disable the preview camera/controller when adding your gameplay camera. `survivors_map_preview.gd` only implements map inspection, not player movement.

## Rebuild and validate

The saved scene is ready to edit. Rebuilding is optional and **replaces the saved arena and TileSet**, so preserve any manual edits first.

From the project directory, with your Godot 4.6 executable substituted for `godot`:

```text
godot --headless --path . --log-file .godot/tilemap-import.log --editor --import
godot --headless --path . --log-file .godot/tilemap-build.log --script res://scripts/tools/build_survivors_arena.gd
godot --headless --path . --log-file .godot/tilemap-validation.log --script res://scripts/tools/validate_survivors_arena.gd
```

The generator supports `-- --columns=40 --rows=30 --cell-size=64 --seed=49028`. Validation checks saved resource references, all ground cells, real physics at cover and boundaries, a clear spawn, and connected floor-cell centers for a 24 px actor. The connectivity check samples cells; it does not replace movement testing for a differently sized character.

The preview can capture a rendered PNG using `-- --capture-map=<absolute-output-path>` when running with a graphics display. Use a writable log path; do not use `--headless` for captures.

Artwork was generated with the built-in `image_gen` tool. Exact prompts are in [generation-prompts.txt](generation-prompts.txt). The source artwork remains unmodified; Godot handles the runtime texture size during import.
