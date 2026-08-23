---
name: godot-mechanic-design
description: How to architect a gameplay mechanic in Godot before writing it — choosing between per-frame checks, state machines, early-return states, timed lockouts and tweens; where the mechanic's state should live; how to keep 2D platformer movement feeling good. Load when designing or adding a player ability, NPC behaviour, obstacle, or game system, or when asked "what's the best way to build X" / "how should I structure this mechanic".
---

# Designing a mechanic in Godot

Most bad gameplay code comes from picking the wrong *shape* for a mechanic, not from bad syntax. Pick the shape first.

## Step 1: what is the mechanic's lifetime?

This single question determines the implementation pattern. There are four common shapes:

| Lifetime | Pattern | Example |
| --- | --- | --- |
| **Instant, one frame** | A branch in the movement code | Jump impulse, double-jump |
| **Continuous while a condition holds** | Per-frame surface/state check that sets a flag | Sliding on a slope, swimming, being in a wind zone |
| **Exclusive state that suspends normal physics** | Early `return` before gravity and `move_and_slide()`, position driven by tween or manual code | Ledge hang, wall grab, cutscene control, being grabbed |
| **Timed lockout that still obeys physics** | A bool + timer/`await`, checked by the normal movement code | Stumble, hitstun, dash cooldown, roll recovery |

Getting this wrong is what produces the classic bugs: gravity still accumulating during a wall-grab, or a "state" that the player can cancel out of because it was only a flag.

**A mechanic that suspends physics must suspend it completely.** If the player is hanging on a ledge, zero the velocity and return before gravity — do not try to counteract gravity with an equal force, because you will drift.

**A mechanic that is a lockout must not suspend physics.** A stumbling player still falls. Implement it as a multiplier or a branch, not a state that bypasses the loop.

## Step 2: where does the state live?

Ask: *who needs to know?*

- **Only the actor** → a var on the actor's script. Most mechanics. `is_sliding`, `on_ledge`.
- **The actor and the thing it interacts with** → the interactable exposes a method, the actor calls it duck-typed. A ledge exposes `get_grab_position()`; the player calls it if the method exists. Neither knows the other's class.
- **The level orchestrates it** → the level script calls down into the actors. Cutscenes, chase pacing, scripted sequences. The actors expose verbs (`move_to_position()`, `set_pursuit_mode()`, `set_input_enabled()`) and stay ignorant of the story.
- **Genuinely global** → autoload. Save data, settings, audio. Very little qualifies.

Resist putting mechanic state on an autoload because it is convenient to reach. That is how you get a player controller that cannot be instanced twice and a level that cannot be tested alone.

## Step 3: how does it talk to the animation system?

Two mechanisms, and mixing them carelessly causes fights:

- **`state_machine.travel("name")`** — imperative, "go there now". Use for states the code decides definitively: jump, fall, slide, hit reactions.
- **Condition booleans** (`parameters/conditions/x`) — declarative, "the transition may now happen". Use for states the animation graph should ease between on its own terms: idle↔run.

Pick one per transition. A state that is both `travel()`ed to *and* guarded by a condition will stutter, because the graph re-evaluates the condition after you forced the travel.

Give the animation graph authority over *timing* and the code authority over *intent*. If a roll must finish before the player can steer again, ask the graph whether it is still playing (`state_machine.get_current_node() == "roll"`) rather than duplicating the animation length as a constant in code — otherwise the two drift the first time an artist retimes the animation.

## Step 4: what cancels it?

Write this down before implementing. For each new mechanic, answer:

- What can interrupt it? (landing, taking damage, a cutscene starting)
- What does it prevent? (jumping, steering, other mechanics)
- What happens if it is triggered while already active?
- What happens if the actor is freed or the level unloads mid-mechanic?

The third one is the usual bug. Guard re-entry explicitly:

```gdscript
func stumble(duration: float = 0.8) -> void:
    if is_stumbling or on_ledge:
        return
```

The fourth one matters for anything using `await` — check `is_instance_valid()` after a long wait.

## Platformer feel

Feel comes from breaking physics deliberately. Real gravity feels terrible.

**Asymmetric gravity.** Fall faster than you rise. A fall multiplier around 2× the jump multiplier is the standard starting point, tuned by feel.

**Apex float.** Reduce gravity near the top of the arc (when `abs(velocity.y)` is small). This is what makes a jump feel controllable and readable — the player gets extra time to aim at the peak.

**Variable jump height.** Hold to rise longer, release to cut. Two ways: apply extra upward force while held within a time budget, or multiply `velocity.y` by ~0.5 on release while still ascending. Doing both, as this project does, gives the finest control but needs careful tuning so they don't compound.

**Forgiveness windows.** The two that matter most, in order of impact:

- *Coyote time* — allow jumping for ~0.1s after walking off a ledge. Implement as a timer reset when `is_on_floor()`, checked instead of `is_on_floor()` in the jump branch.
- *Jump buffering* — remember a jump pressed up to ~0.1s before landing and fire it on touchdown. Implement as a timer set on `just_pressed`, consumed on landing.

Neither is visible to the player. Both are immediately felt when missing.

**Speed is not one number.** Base, crouched, chased, stumbling, airborne — express them as multipliers over a base so tuning one doesn't require re-tuning all of them.

**Tune in the smallest unit that matters.** In a 160×90 game, jump height is measured in pixels and a 2-pixel change is a design change. Expect to iterate with the player, not to derive values.

## Choosing between a tween and physics

Use a **tween** when the motion is *authored*: a ledge climb that must land exactly on top of the ledge, a scripted camera move, a dash with a fixed distance. Tweens guarantee the endpoint.

Use **physics** when the motion is *emergent*: jumping, falling, knockback. Physics guarantees collision response.

Never mix them on the same axis at the same time. A tween writing `global_position` while `move_and_slide()` also runs will fight, and the tween wins in a way that lets the player pass through walls. This is why an exclusive state returns early.

## NPC behaviour

Start with the simplest thing that reads correctly on screen. For a chase, "move toward a target X coordinate at a speed" plus "the level keeps me within N pixels of the player" is usually more legible — and far more controllable for pacing — than real pathfinding.

Add *organic noise* rather than complexity: jitter the run speed slightly toward a new random target every few tenths of a second and smooth toward it with `move_toward()`. That single trick removes most of the robotic feel without any state machine.

Expose NPC verbs for the level to call (`move_to_position(x, run_fast)`, `stop_movement()`), and keep the decision of *when* in the level script. This keeps cutscene and gameplay behaviour in one readable timeline instead of scattered across the NPC.

## Cutscenes

Simulate input rather than bypassing the controller. Gate every input read on an `input_enabled` flag with `simulated_*` fallbacks, so the cutscene drives the same code path the player does. Any ability that reads `Input` directly without the gate will fire during cutscenes — this is the most common regression when adding a mechanic to a game that has scripted sequences.

Write cutscenes as one linear `async` function with `await`s, not a state machine. A cutscene is a script, and reading it top-to-bottom is worth more than the flexibility of a graph.

## Before you implement, state

1. Which of the four lifetime shapes this is.
2. Where the state lives.
3. Which existing mechanic in the codebase is the closest precedent.
4. What cancels it and what it cancels.
5. What will need feel-tuning and cannot be got right on the first try.
