# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.7 (Forward Plus) 2D pixel-art platformer. GDScript only, no addons, no test suite, no build scripts. `README.md` covers the game from a player's/contributor's perspective; this file covers what you need to change the code safely.

## Working rules

**After implementing any new feature, mechanic, level, NPC behaviour, input binding, or architectural change, run the `readme-maintainer` agent.** It decides whether `README.md` or this file went stale and updates them. This is not optional and not something to skip because the change felt small — the Mechanics table, Controls table, and Status section in the README go stale faster than anything else in the repo.

**The two implementation agents have a hard split — do not let either cross it:**

- `gameplay-engineer` writes **`.gd` files only**. It never edits `.tscn`, `project.godot`, `.import`, or `.gd.uid`, even for a one-line change. It reads them freely.
- `scene-architect` owns **everything that is not GDScript**: `.tscn` node trees and properties, Inspector `@export` values, `AnimationTree` states, `project.godot` (input map, `[layer_names]`, `[global_group]`, autoloads, rendering), import settings and resource wiring. It never writes script logic.

A task that needs both gets both, in that order, with the script agent's report naming exactly what the scene needs.

**Nothing gets build- or parse-verified.** Roberto tests every change manually in the Godot editor before it is committed or called ready. Do not run the Godot binary, a headless parse check, or an import pass to confirm your own work — see the `godot-verification-policy` skill. Run it only when he explicitly asks.

Four project skills carry the standards; load the relevant one before working:

- `godot-gdscript-standards` — before writing or reviewing any `.gd` file.
- `godot-mechanic-design` — before designing a player ability, NPC behaviour, or game system.
- `godot-scene-architecture` — before creating a scene, adding a level, changing scene loading, or hand-editing a `.tscn`.
- `godot-verification-policy` — before calling anything done, and any time you consider running Godot.

The game renders at a **160x90 viewport** upscaled to a 1280x720 window (`window/stretch/mode="viewport"`, `default_texture_filter=0`, `snap_2d_transforms_to_pixel=true`). All positions, collision sizes, and tuning constants are in this tiny pixel space — a "small" number like `7.0` for a raycast length is a meaningful distance here.

## Commands

There is no CLI build/test pipeline, and agents do not run one. These are the commands **Roberto** uses when he tests (`godot` is **not** on PATH here; the binary is `Godot_v4.7-stable_win64.exe`):

```bash
godot --path .                      # open project in editor, F5 to run the main scene
godot --path . --headless --quit    # reimport assets
godot --path . res://scenes/scenarios/scene_03.tscn   # run one scenario directly
```

Running a scenario `.tscn` directly works because each one carries its own `player_spawn` (see below).

Do not run any of these to verify your own changes. Only run one if he explicitly asks.

## Architecture

### Scene flow — two coexisting systems

The main scene is `scenes/scenarios/00_scene_manager.tscn`, **not** a scene_00. There are two different transition mechanisms in the codebase and new work should use the second:

1. **Legacy, full scene swap** — `scene_1.gd` / `scene_2.gd` are self-contained cutscene directors that `await` a `transition_splash_screen.fade_out()` and then call `get_tree().change_scene_to_packed(next_scene)`. `next_scene` is a `@export`ed `PackedScene` wired in the Inspector.
2. **Current, additive streaming** — `SceneManager` (`scripts/00_scene_manager.gd`) holds a `current_level_container` Node2D and instantiates/frees level scenes into it. `SceneTrigger` (`scripts/00_scene_trigger.gd`) is an `Area2D` that adds itself to the `scene_triggers` group and emits `scene_transition_requested(scenes_to_load, scenes_to_unload)` when the player's body enters. `SceneManager` connects to triggers in the group at `_ready()` and re-scans newly instantiated subtrees so streamed-in levels wire themselves up. Unloading matches on `child.scene_file_path` against the `PackedScene.resource_path` of `scenes_to_unload`, checked both in the container and at `get_tree().root`.

To chain a level: drop `00_scene_trigger.tscn` into it and fill `scenes_to_load` / `scenes_to_unload` in the Inspector with the next/previous level `.tscn`s.

### Player spawning

Levels do **not** contain a player instance. Each contains a `player_spawn.tscn` (`PlayerSpawn`, a `Marker2D`) which on `_ready` defers a check of the `player` group: if no player exists it instantiates its `@export var player_scene` at its own position; if one exists it only repositions when `force_reposition` is true. This is what makes both "boot the whole game" and "run this one scenario" work from the same scene file.

### Player controller (`scripts/player.gd`)

Single `_physics_process` on a `CharacterBody2D`, ordered deliberately — changing the order breaks things:

1. `is_sliding` recomputed from `slide_check` raycast normal (slope 35°–55° while `velocity.y >= 0`).
2. Ledge state **returns early**, bypassing gravity, movement and `move_and_slide()` entirely; position is driven by `Tween`s instead.
3. Asymmetric gravity: separate multipliers for ascent, apex float, and fall, plus variable jump height via `MAX_JUMP_HOLD_TIME` / `JUMP_HOLD_FORCE`.
4. Collision shape is resized for crouch **before** `move_and_slide()`, guarded by `was_crouch_collision_active` so it only fires on change.
5. After moving, ledge detection, raycast direction flipping, and fall-height → `roll` vs `land` classification.

Tuning lives in the `const` block at the top of the file; prefer editing those over inlining numbers.

**Input abstraction for cutscenes**: every input read is gated on `input_enabled`. When false the controller reads `simulated_left` / `simulated_right` / `simulated_crouch` instead. Cutscene directors call `player.set_input_enabled(false)` then poke those booleans (see `scene_2.gd`). Other externally-called player API: `set_pursuit_mode(bool)` (swaps `BASE_SPEED`/`PURSUIT_SPEED` and the run animation's `run_speed` scale) and `stumble(duration)`.

### Animation

`AnimationTree` + `AnimationNodeStateMachine` on the player, driven two ways from `player.gd`:
- `state_machine.travel("name")` for direct transitions (`jump`, `fall`, `slide`, `roll`, `stumble`, `crouch-*`).
- Boolean conditions via `set_animation_condition()` / `get_animation_condition()`, which write `parameters/conditions/<name>` — the declared ones are `climb`, `idle`, `land_requested`, `ledge_grab`, `roll_requested`, `run`.

State names are string-matched in `animations()`; renaming a state in the AnimationTree requires updating those literals. `is_roll_playing()` gates jumping and direction changes.

### Ledges

`ledge.gd` is a `@tool` `StaticBody2D` on **physics layer 3 (`"ledge"`, mask value 4)** — the player's `ledge_grab_hit` / `ledge_grab_miss` raycasts use `collision_mask = 4` to see only these. The `ledge_side` enum (Custom/Left/Right) auto-sets `grab_offset` and marks it read-only in the Inspector via `_validate_property`. The player calls `collider.get_grab_position()` duck-typed via `has_method`, so any node exposing that method can be grabbed.

### Conventions

- `scripts/` is flat; `.gd` files pair with `.gd.uid` files — commit both, never edit the `.uid`.
- `scenes/objects/` holds reusable prefabs (player, npcs, environment pieces); `scenes/scenarios/` holds levels. `00_`-prefixed files are the infrastructure ones.
- Cross-node calls are duck-typed defensively (`if node and node.has_method("x")`) rather than typed — follow that pattern for anything a designer might not wire up in the Inspector.
- Anything a designer tunes is an `@export` with a `##` doc comment, not a constant.
- `transition_splash_screen.tscn` is the shared fade overlay: `prepare()` in `_ready`, then `await fade_in(d)` / `await fade_out(d)`.
- Stray `scenes/*.tscn*.tmp` files are Godot editor leftovers, not source.
