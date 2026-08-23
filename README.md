# bear-game

A 2D pixel-art platformer built in **Godot 4.7**. You play a lone traveller making their way through a forest while a bear closes in behind you — the levels mix precision platforming (ledge grabs, variable-height jumps, crouch tunnels, slopes) with scripted chase sequences.

The game renders at a native **160×90** resolution and is upscaled to the window, so every sprite, collision box and tuning value is authored in a very small pixel space.

<!-- TODO: add a gameplay GIF or screenshot here -->

---

## Requirements

- **Godot 4.7** (stable, Forward Plus renderer) — no C#, no external addons, no package manager.
- **Aseprite** (optional) — only needed to edit art. Source `.aseprite` files live next to their exported `.png`s.

## Running the game

Open the project folder in the Godot editor and press <kbd>F5</kbd>. The main scene is `scenes/scenarios/00_scene_manager.tscn`.

From the command line:

```bash
godot --path .                                        # open the editor
godot --path . --headless --quit                      # reimport assets / check the project parses
godot --path . res://scenes/scenarios/scene_03.tscn   # run a single level directly
```

Any level under `scenes/scenarios/` can be launched on its own — each one carries a `player_spawn` node that creates the player if none exists, so you never have to boot through the whole game to test one section.

## Controls

| Action | Keys |
| --- | --- |
| Move left / right | <kbd>←</kbd> <kbd>→</kbd> |
| Jump | <kbd>↑</kbd> or <kbd>X</kbd> — *hold to jump higher* |
| Crouch | <kbd>↓</kbd> or <kbd>C</kbd> |
| Climb a ledge | <kbd>↑</kbd> while hanging |
| Drop from a ledge | <kbd>↓</kbd> while hanging |
| Roll | automatic — land from a medium-height fall while holding a direction |

Crouching is also forced automatically when there is a low ceiling overhead, and sliding starts on its own when you step onto a steep enough slope — while sliding you can neither steer nor jump, you ride it to the bottom.

## Mechanics

| Mechanic | Notes |
| --- | --- |
| **Variable-height jump** | Holding jump applies extra upward force for a short window; releasing early cuts the ascent. Gravity uses separate multipliers for rising, hanging at the apex, and falling, so jumps feel floaty at the peak and snappy on the way down. |
| **Ledge grab & climb** | Falling into a ledge collider snaps the player onto it and freezes physics entirely; a tween drives the climb up and over. Ledges live on their own physics layer so only the grab raycasts see them. |
| **Crouch** | Shrinks the collision box (21px → 15px tall) so the player fits through low gaps. Held automatically while under a ceiling. |
| **Roll** | Triggered by landing on flat ground from a fall within a specific height band while holding a direction; locks out steering and jumping until it finishes. |
| **Slide** | A 35°–55° slope cannot be walked up — standing on one pushes the player down it at a fixed speed, takes away horizontal control and locks the sprite facing downhill. Landing on such a slope plays no roll or landing, it goes straight into the slide. When the slope runs out the down-slope momentum carries for a moment so the player runs onto the flat instead of stopping dead. Jumping out of a slide is deliberately switched off at the moment. |
| **Stumble** | Obstacle triggers call `stumble()` on the player, halving their speed and playing a recovery animation. |
| **Pursuit mode** | A scene can call `set_pursuit_mode(true)` to raise the player's top speed and speed up the run animation during chases. |
| **Bear AI** | Walks or flees toward a target X coordinate, with its run speed jittering slightly over time so the chase doesn't look mechanical. During gameplay a level script keeps it a fixed distance behind the player. |

## Project layout

```
assets/            Aseprite sources + exported PNGs (player, npcs, environment, cars)
scenes/
  objects/         Reusable prefabs
    player/        player.tscn, player_spawn.tscn
    npcs/          bear.tscn, wolf.tscn
    environment/   ground pieces, ledges, trees, rocks, backgrounds
    cars/
  scenarios/       Playable levels + the scene-streaming infrastructure
    00_scene_manager.tscn   <- main scene
    00_scene_trigger.tscn
    scene_00 … scene_04
scripts/           All GDScript (flat directory, one file per behaviour)
```

## How levels fit together

The game boots into `00_scene_manager.tscn`, which holds a `SceneManager` and an empty `current_level_container`. Levels are **streamed in and out additively** rather than swapped:

1. A level contains a `00_scene_trigger` (an `Area2D`) somewhere near its exit.
2. In the Inspector you fill that trigger's `scenes_to_load` with the next level and `scenes_to_unload` with the one being left behind.
3. When the player walks into it, the trigger emits a signal, `SceneManager` instantiates the incoming level and frees the outgoing one, then wires up any triggers inside the new level so the chain continues.

The player is never part of a level file. Each level has a `player_spawn` marker that spawns the player only if one doesn't already exist, which is what lets levels be tested in isolation *and* lets the player carry across a streamed transition.

The two earliest scenes (`scene_01`, `scene_02`) predate this system and still do a full `change_scene_to_packed` swap behind a fade. They work, but new levels should use the streaming triggers.

## Adding a level

1. Create `scenes/scenarios/scene_NN.tscn` with a `Node2D` root.
2. Block out geometry with a `StaticBody2D` + `CollisionShape2D` children (see `scene_03` / `scene_04` for the pattern), instancing `ledge.tscn` where the player should be able to grab on.
3. Drop in `player_spawn.tscn` and position it where the player should appear.
4. Drop in `00_scene_trigger.tscn` at the exit and fill in `scenes_to_load` / `scenes_to_unload`.
5. Point the previous level's trigger at your new scene.

Level geometry is currently traced over sketch PNGs in `assets/environment/scene-sketches/`, which sit in the scene as a reference `Sprite2D` behind the real art.

## Art pipeline

Sprites are drawn in Aseprite and exported as individual numbered PNGs per animation (`assets/player/run/run1.png`, `run2.png`, …). Animations are assembled in the player's `AnimationPlayer` and driven by an `AnimationTree` state machine. Texture filtering is off project-wide and 2D transforms snap to the pixel grid, so imported art must stay on whole-pixel boundaries to avoid shimmering.

## Status

Playable vertical slice. Implemented: the full player moveset, bear chase behaviour, scene streaming, and levels `scene_00` through `scene_04` (the later ones still using sketch art as placeholder). Slope sliding is the most recent addition; the down-slope launch for jumping out of a slide is written and wired up but deliberately commented off in `scripts/player.gd`, so it is a one-line change to turn back on. The wolf has a complete animation set in `assets/` but no behaviour script yet.

## Contributing / working on this repo

`CLAUDE.md` in the repo root documents the architecture in the detail needed to change it safely — especially the ordering constraints inside `scripts/player.gd`'s physics loop and the string-matched animation state names. Read it before touching the player controller.
