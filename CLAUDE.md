# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Gas Station Tycoon**: a 2D tycoon game built with **Godot 4.6** in **GDScript**. The project uses the GL Compatibility renderer and a 1280x720 base viewport with `canvas_items` stretch. Remote: `github.com/Rchi3-new/tycoon-godot-gas-station`.

The project is at the initial scaffold stage. The entry point is `scenes/main.tscn`, a `Node2D` root with a `Camera2D`, and its script is `scripts/main.gd`. Scenes go in `scenes/` and scripts in `scripts/`.

## Commands

The Godot editor isn't on PATH. On this machine it is at `C:\Users\gtuch\Downloads\Godot_v4.6.1-stable_mono_win64\` (use the `_console.exe` build for CLI output).

```sh
GODOT="/c/Users/gtuch/Downloads/Godot_v4.6.1-stable_mono_win64/Godot_v4.6.1-stable_mono_win64_console.exe"
"$GODOT" --headless --path . --import          # (re)import assets, regenerate .godot/ cache
"$GODOT" --headless --path . --quit-after 5    # smoke-test: load main scene, surface script errors
"$GODOT" --path .                               # run the game
"$GODOT" -e --path .                            # open in editor
```

No test framework has been set up yet.

## Conventions

- Commit the `*.uid` files (Godot 4.4+ writes one next to each script) and the `*.import` files. Don't commit `.godot/`, which is a regenerated cache.
- `.gitattributes` forces LF line endings. Keep `.tscn`/`.gd` files LF so Windows checkouts don't produce spurious diffs.
- Prefer editing scenes in the editor. When hand-editing `.tscn`, keep `ext_resource` ids and `load_steps` consistent.
