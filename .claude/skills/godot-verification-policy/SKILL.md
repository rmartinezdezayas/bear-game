---
name: godot-verification-policy
description: This project's rule for how changes get verified — the user tests everything manually in the Godot editor. Load before finishing any change to a .tscn, .gd, project.godot or import setting, and any time you are about to run the Godot binary, a headless parse check, an import pass, or otherwise "confirm it works". Also load when deciding whether a feature can be called done or ready to commit.
---

# Verification policy: the user tests, you don't

**Roberto tests every change manually in the Godot editor before it is committed or called ready.** That is the whole verification pipeline for this project. It is deliberate, not a gap to fill.

## Do not run

Nothing you can run tells you what matters here — how it feels at 160×90. Do not run, and do not offer to run:

- `godot --path . --headless --quit` or `--quit-after N` as a parse/verification step
- `godot --path . <scene>.tscn` to "check the scene loads"
- Any import/reimport pass to "make sure the assets resolve"
- Any lint, formatter, or script that exists only to confirm your own edit landed

The Godot binary is not on PATH in this environment; the fact that you *could* find it at `Godot_v4.7-stable_win64.exe` is not a reason to.

This also means: no "let me just confirm it parses" after hand-editing a `.tscn`, and no re-reading a file you just wrote to check the edit applied. The edit tools error when they fail.

## Run only when asked

If the user explicitly says "run it", "open the editor", "check that it imports" — do exactly that. Their ask overrides this policy every time. Outside of that, launching the editor takes over their machine for something they were going to do themselves anyway.

## What to do instead

Spend the effort you would have spent verifying on **reading**. Read the file you are about to change in full, read the neighbouring mechanic you are copying, map a `.tscn` with `grep -n "^\[node"` before editing it. In a project with no tests, careful reading is the check.

Then hand the testing over properly. End every piece of work with a short, concrete list of what to try — actions in the game, not abstractions:

> - Jump onto the 40° slope from the left; you should slide, not stick at the seam.
> - Walk into the scene_04 trigger, then walk back through it — it should not re-fire.
> - Open `player.tscn` and confirm the `crouch-walk` state still has its transition from `crouch-idle`.

Flag separately anything you tuned by guess and expect to need feel iteration.

## Language

Never write "verified", "confirmed working", "tested", or "this works" about something you have not seen run — which is everything. Say what you changed and what it should do.

"Done" means **the code is written and ready for you to test**, and say it that way. The feature is ready when the user says it is, not when you finish typing.
