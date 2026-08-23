---
name: godot-scene-architecture
description: How to structure Godot scenes, node trees, and level loading — scene composition and reuse, keeping levels independently runnable, additive scene streaming vs full swaps, spawn points, physics layers and groups, and safely hand-editing .tscn files and uid:// references. Load when creating or restructuring a scene, adding a level, changing how scenes transition or how the player is spawned, or hand-editing a .tscn.
---

# Scene architecture in Godot 4

A Godot scene is a reusable prefab *and* a unit of composition. The design goal for every scene: **it should run on its own with F6.**

## Composition rules

- **A scene owns its children; it does not own its parent.** Never reference upward with `get_parent()` or an absolute path. Anything the scene needs from outside comes in through an `@export` wired in the Inspector, or a signal it emits.
- **Split a scene out when it has its own behaviour or will appear more than once.** A ledge with grab logic earns a scene. A collision shape does not.
- **Prefer instancing over duplicating.** If two levels contain the same ten-node obstacle laid out by hand, it should have been a scene — changing it later otherwise means editing every copy.
- **Keep prefabs and levels in separate directories.** Reusable things under `objects/`, playable things under `scenarios/`. Infrastructure scenes (managers, triggers) benefit from a prefix like `00_` so they sort to the top and read as not-a-level.

## Making levels independently runnable

The player should **not** be saved inside a level. That couples level layout to player state, makes two players impossible, and means testing a level mid-game requires playing through everything before it.

Instead, each level carries a **spawn marker** that conditionally creates the player:

```gdscript
extends Marker2D
class_name PlayerSpawn

@export var player_scene: PackedScene
@export var force_reposition: bool = false

func _ready() -> void:
    call_deferred("_handle_player_spawn")   # let the tree finish building first

func _handle_player_spawn() -> void:
    var existing := get_tree().get_nodes_in_group("player")
    if existing.is_empty():
        var p := player_scene.instantiate() as Node2D
        p.global_position = global_position
        get_parent().add_child(p)
    elif force_reposition:
        (existing[0] as Node2D).global_position = global_position
```

This gives you both behaviours from one node: run the level alone and it spawns a player; stream into it mid-game and the existing player carries over. The `call_deferred` matters — spawning during `_ready` races with the rest of the tree entering.

## Scene transitions: two approaches

**Full swap** — `get_tree().change_scene_to_packed(next)`. Simple, frees everything, loses all state. Fine for going from a menu to a level, or between narratively separate chapters. Always hide the swap behind a fade, because the frame the new scene builds on will hitch.

**Additive streaming** — a manager node instantiates the next level into a container and frees the previous one. Keeps the player and any persistent state alive, allows overlap so the seam is invisible, and lets you unload behind the player. Necessary for a continuous world.

For streaming, the pieces are:

1. A **manager** holding a container node, exposing `change_scenes(to_load, to_unload)`.
2. **Triggers** (`Area2D`) placed at level exits, each `@export`ing the `PackedScene`s to load and unload, emitting a signal on player entry.
3. A **group** (`scene_triggers`) so the manager finds triggers without knowing the tree shape — including in levels it just instantiated, which requires re-scanning the new subtree after it enters.

Match unloading on `child.scene_file_path` against `PackedScene.resource_path` rather than on node names, which designers rename.

Guard triggers against re-entry (`trigger_once` plus `set_deferred("monitoring", false)`), or walking back through the seam re-fires the transition.

Use `add_child` via `call_deferred` when instantiating from inside a physics callback — adding nodes mid-physics-step is a common source of "Condition ... is true" errors.

## Physics layers and groups

**Name every layer you use** in `project.godot` under `[layer_names]`. An unnamed layer becomes an unexplained `collision_mask = 4` six months later.

Remember the mask is a **bitmask**: layer 1 = 1, layer 2 = 2, layer 3 = 4, layer 4 = 8. Give special interactions their own layer so a raycast can look for exactly one thing — a ledge-detection ray that also hits the ground is a ledge-detection ray that doesn't work.

**Groups** are the right tool for "find the thing without knowing where it is". Declare them project-wide under `[global_group]` for autocompletion. Use them for `player`, `enemies`, `checkpoints`, `scene_triggers`. Do not use them for one-off references that an `@export var node: Node2D` would express more clearly.

## `@export` design

`@export`s are the contract between you and whoever lays out levels — including future you.

```gdscript
## Packed scenes to instantiate when triggered
@export var scenes_to_load: Array[PackedScene] = []

## Set to true if the trigger should only execute once
@export var trigger_once: bool = true
```

Type the arrays (`Array[PackedScene]`, not `Array`) so the Inspector validates drops. Write a `##` doc comment on every one — it becomes the Inspector tooltip. Use `@export_enum`, `@export_range`, and `@export_group` to make invalid states unrepresentable rather than documenting them.

For `@tool` scripts, `_validate_property()` can grey out fields that don't apply to the current mode, which is better than a comment saying "ignored unless X".

Note: adding an `@export` after scenes are saved means existing instances keep the old value until re-saved. Changing a default does not propagate to placed instances.

## Hand-editing `.tscn` files

Godot's scene format is text and diffs well, which tempts you to edit it directly. It is safe if you respect three things:

**1. Never invent a `uid://`.** UIDs are generated by the editor and stored in `.uid` sidecar files for scripts and `.import` files for assets. Copying an existing UID string is fine; making one up produces a broken reference that Godot silently resolves to null. If you need a new resource referenced, add it by `path=` and open the editor once to let it regenerate.

**2. `ext_resource` ids are file-local.** The `id="3_a8ls1"` strings are arbitrary but must be unique in the file and match every `ExtResource("3_a8ls1")` use. When copying a node between files you must bring its `ext_resource` lines too, renaming ids on collision.

**3. Map before you edit.** These files run to hundreds of lines. `grep -n "^\[node" file.tscn` gives you the tree; `grep -n "^\[ext_resource"` gives you the dependencies. Read those before touching anything.

Always tell the user when you hand-edited a scene and what to verify in the editor — a malformed `.tscn` fails at load with a message that points at a line number, not a cause.

Commit `.gd.uid` and `.import` files. Never edit them by hand. `.godot/` is generated and belongs in `.gitignore`.

## Pixel-art project settings

For a low-resolution game, these settings work together and breaking one undoes the others:

- `window/stretch/mode = "viewport"` — render at the small resolution, scale the result.
- `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest) — no blurring.
- `rendering/2d/snap/snap_2d_transforms_to_pixel = true` — no shimmer on movement.

With snapping on, sub-pixel offsets in scene layout are silently rounded, so authoring art or positions on half-pixels produces jitter that looks like a physics bug. Keep camera positions and node offsets on whole pixels.

## Scene review checklist

- [ ] Runs standalone with F6
- [ ] No upward `get_parent()` / absolute node paths
- [ ] External dependencies come in via typed, documented `@export`s
- [ ] Repeated hand-placed structures extracted into instanced scenes
- [ ] Physics layers used are named in `project.godot`
- [ ] Groups used for cross-tree lookup, `@export` for specific references
- [ ] Nodes added from physics callbacks use `call_deferred`
- [ ] Area2D triggers guarded against re-entry
- [ ] Positions on whole pixels
