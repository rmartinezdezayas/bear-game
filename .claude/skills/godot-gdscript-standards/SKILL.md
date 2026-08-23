---
name: godot-gdscript-standards
description: Coding standards and review checklist for GDScript in Godot 4. Load before writing or reviewing any .gd file — covers static typing, naming, script organisation, signal direction, node caching, the _process vs _physics_process split, and the specific mistakes that fail silently in Godot rather than erroring. Use when writing GDScript, reviewing a .gd diff, or answering "is this the idiomatic way to do X in Godot".
---

# GDScript standards (Godot 4)

Follow the official GDScript style guide. This file covers the parts that matter most in practice and the failure modes that produce *no error at all* — the expensive ones.

## Script organisation

Order within a file, top to bottom:

```
@tool / class_name / extends
## Class docstring
signals
enums
constants
@export vars
public vars
private vars (_prefixed)
@onready vars
_init / _ready / _process / _physics_process / _input
public methods
private methods (_prefixed)
inner classes
```

Naming: `snake_case` for files, functions, variables, and signals; `PascalCase` for `class_name` and node names in the editor; `CONSTANT_CASE` for constants and enum members; `_leading_underscore` for private members.

## Static typing

Type everything that isn't obvious. Types catch errors at parse time instead of three frames into a chase sequence, and they let the compiler emit faster bytecode.

```gdscript
var speed: float = 50.0
var target := Vector2.ZERO          # inferred — fine, the type is obvious
func grab(point: Vector2) -> void:  # always annotate params and return
```

Annotate `-> void` explicitly on functions that return nothing. Untyped `var x = get_node(...)` is the single most common source of "why is this nil" in GDScript.

Cast with `as`, and remember `as` yields `null` on failure rather than throwing:

```gdscript
var body := collider as CharacterBody2D
if not body:
    return
```

## Signals: call down, signal up

**A parent calls methods on its children. A child emits a signal and lets the parent listen.** A child that reaches upward with `get_parent()` or an absolute node path is coupled to a tree position it does not own, and breaks the moment the scene is instanced somewhere else.

Name signals in the past tense for things that happened — `health_changed`, `died`, `ledge_grabbed` — and use `_started` / `_finished` for things with duration.

Type signal parameters:

```gdscript
signal scene_transition_requested(scenes_to_load: Array[PackedScene], scenes_to_unload: Array[PackedScene])
```

Connect in `_ready`, and guard against double-connection when a node can be re-wired:

```gdscript
if not trigger.scene_transition_requested.is_connected(_on_scene_transition_requested):
    trigger.scene_transition_requested.connect(_on_scene_transition_requested)
```

## Node access

Cache node references in `@onready` vars. `$Path` and `get_node()` walk the tree by string every call — fine once in `_ready`, wasteful in `_physics_process`.

```gdscript
@onready var sprite: Sprite2D = $Sprite2D          # good
func _physics_process(_d): $Sprite2D.flip_h = true # walks the tree 60×/second
```

For optional nodes use `get_node_or_null()` and check the result. For nodes in another scene entirely, prefer an `@export var target: NodePath` or `@export var node: Node2D` wired in the Inspector over a hardcoded path.

Duck-type across scene boundaries when the connection is optional:

```gdscript
if body.has_method("stumble"):
    body.stumble()
```

This is deliberately not an interface check — GDScript has none. It keeps a level playable when a designer hasn't wired something yet.

## `_process` vs `_physics_process`

- Anything touching `velocity`, `move_and_slide()`, raycasts, or collision → `_physics_process(delta)`.
- Camera smoothing, UI, non-physical visuals → `_process(delta)`.

Never call `move_and_slide()` from `_process`. Reading collision state from `_process` gives you last-physics-tick data at an arbitrary offset.

Always multiply rates by `delta`. A value that is not multiplied by delta is a value that changes with framerate.

## Groups over singletons

`add_to_group("player")` + `get_tree().get_nodes_in_group("player")` decouples lookup from tree structure. Prefer it to a global autoload for "find the thing" problems. Reserve autoloads for genuinely global state (settings, save data, audio bus control).

Godot 4 lets you declare groups project-wide in `project.godot` under `[global_group]`, which gets them autocompleted and documented.

## Async: `await` and tweens

`await` in a method makes it a coroutine. Two consequences that bite:

- The caller continues immediately unless it also awaits.
- If the node is freed while awaiting, the coroutine resumes on a freed object. Guard with `if not is_instance_valid(self): return` after long awaits, or use `get_tree().create_timer(t, false)` and check state on resume.

Tweens created with `create_tween()` are bound to the node and die with it, which is usually what you want. Chain with `.set_trans()` / `.set_ease()`, and use `await tween.finished` rather than a timer that guesses the duration.

## Things that fail silently in Godot

These produce no error. They are worth a specific check on every review:

1. **A renamed `AnimationTree` state or condition.** `state_machine.travel("run-fast")` for a state that doesn't exist does nothing. `animation_tree["parameters/conditions/foo"] = true` for an undeclared condition does nothing. Both are string-matched at runtime.
2. **A renamed node with a `$Path` reference.** Godot updates paths it can see in the editor; it cannot see paths built as strings.
3. **A wrong `collision_mask`.** A raycast that sees nothing looks exactly like a raycast that isn't colliding. Write the layer name in a comment next to the mask value.
4. **`await` on a signal that never fires.** The coroutine just never resumes.
5. **A `queue_free()`d node still referenced.** Check `is_instance_valid()` before using a stored reference that something else may have freed.
6. **An `@export` added to a script after scenes were saved.** Existing instances keep the old default until re-saved; the Inspector shows the new default while the `.tscn` holds nothing.
7. **Integer division.** `1 / 2` is `0`. Write `1.0 / 2.0`.

## Comments

Use `##` for doc comments on `@export`s and public API — they appear in the Inspector and in editor autocomplete, so they earn their place. Use `#` sparingly inside functions, and only for *why*, not *what*. A comment explaining a magic number's origin ("half the collision height difference, keeps feet grounded") is worth more than any amount of restated code.

## Formatting

Tabs for indentation. LF line endings. Two blank lines between top-level definitions, one between methods. Line continuation with `\` at the end, indented once — used heavily for tween chains:

```gdscript
tween.tween_property(self, "global_position", target, 0.09)\
    .set_trans(Tween.TRANS_SINE)\
    .set_ease(Tween.EASE_OUT)
```

## Review checklist

- [ ] Params and returns typed; no bare `var x = ...` where the type isn't obvious
- [ ] Node lookups cached in `@onready`, none in a per-frame function
- [ ] Physics work in `_physics_process`, rates multiplied by `delta`
- [ ] No `get_parent()` reaching upward; children signal, parents call
- [ ] Signal connections guarded against double-connect if the node can be re-wired
- [ ] Every new string-matched name (animation state, condition, group, action) actually exists on the other side
- [ ] `collision_mask` values annotated with the layer they mean
- [ ] Magic numbers promoted to `const` or `@export`, or commented with their derivation
- [ ] Long `await`s guarded for node validity
- [ ] Designer-facing values are `@export` with `##` docs, not constants
