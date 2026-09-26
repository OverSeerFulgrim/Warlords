# The demo shell (2026-09-26)

The review's §5 list, worked through: key bindings, pause, a title, a confirm step on Surrender, dev
tools out of release builds, and an export that has actually been built and run.

## What was built

- **`scripts/Controls.gd`** — every key the game reads is a named InputMap action: move_* (WASD),
  pan_* (arrows), follow (F), raise_dead (R), minimap (M), pause (Space, P), cancel (Esc) and
  debug_overlay (F3). They are registered at startup by **physical keycode**, so walking follows key
  *position* and works on AZERTY. `ensure()` only adds an action that isn't already defined, so
  anything set in Project Settings → Input Map wins; that is the path a rebinding screen would take.
  `label_for()` asks the OS what the key is called on the player's own layout, so the controls list
  says "Z" to a French player for the key a British player calls "W". `VillainController`,
  `GameCamera` and `Main` no longer read a raw keycode anywhere; the harness scans for one.
- **Pause** (`scripts/ui/PauseMenu.gd`): Space or P, or Esc when there is nothing to close. The
  menu offers Resume, Controls, "Abandon this run…" behind a confirm step, and Quit. It only ever
  clears a pause it set itself, so it cannot unpause the run-end screen, and it won't open over it.
- **Surrender** goes to that confirm step. It used to end the run on one click.
- **Title** (`scripts/ui/TitleScreen.gd`): shown once per session, over a paused world, only when
  Main is the running scene. It shows the level, XP, number of runs and the last epitaph, or "Nobody
  knows his name yet" on a first launch. Its buttons are Begin, Controls (with a four-line how to
  play) and Quit. A new run from the run-end screen goes straight in. The world is built behind the
  title, so it costs nothing, and it avoided changing `run/main_scene` in `project.godot` while
  your editor had it open.
- **The run-end screen** also has a Quit button now.
- **Release builds**:
  - Main frees the three godot_mcp autoloads when `OS.is_debug_build()` is false; they poll
    `user://` every frame and one evaluates Expressions from a file.
  - The 1×/10×/60× button is hidden.
  - F3 was already gated.

## Export

`export_presets.cfg` has **Windows Desktop** and **Linux** presets, writing to `build/`, which is now
gitignored. The file itself stays gitignored, per the existing note that presets can carry keystore
paths, so it lives on disk only. The presets:
- exclude `tools/`, `docs/`, `experiments/`, the two unused GDExtension addons and `_imgtmp*`;
- include `data/*.json`, because the game reads its data with `FileAccess` and a resource-only
  export would ship without it;
- leave `application/modify_resources` off, so no rcedit is needed. The side effect is the
  Windows exe keeps Godot's icon until an icon is set.

**Observed:** both presets exported cleanly with the 4.7.1 templates, the PCK is 44 MB, and the
Linux release build booted clean headless and windowed. Under Xvfb it showed the title with no
debug speed button.

## Harness

`tools/verify_demo_shell.tscn`, 38 assertions:
- every action is registered;
- WASD is bound by physical key;
- no gameplay script contains `is_key_pressed(` or `keycode ==`;
- `move_right` walks him east;
- pause stops the run clock and resuming restarts it;
- pause refuses to open over the run-end screen;
- Esc closes the panel first, then pauses, then resumes, and Space pauses;
- Surrender opens the confirm, backing out keeps the run, and confirming ends it as "abandoned";
- a harness never sees the title;
- the dev bridges and the speed button follow the build type.

## Not done, on purpose

- **The placeholder HUD text** ("Future roadmap goal", "Bounty board — unlocks in Stage 4",
  "Upgrades -- coming soon") stays. The code says each one was your explicit mockup or
  roadmap-promise instruction, so removing them is your call, not housekeeping.
- **Audio**: none yet.
- **A rebinding screen and settings** (fullscreen, volume): the action map is ready for them.
- **Mid-run save.**

## Needs a human

The title, pause menu and controls list at your real resolution. Also check whether Space as pause
fights anything you already do with it; it was only ever reserved in a comment.
