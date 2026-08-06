### Day/night, finished — tint, clock readout, and the debug time scale

Completes FOUNDATION_SPEC §7's foundation cycle. All of it is **inside the existing `DayNightCycle.gd`** rather than a second system — the phase clock, the lighting, and the speed control are one concern, and splitting them would mean three things reading the same `elapsed_in_phase`.

**Sub-phases.** `Phase` is `DAWN / DAYLIGHT / DUSK / NIGHT`. Dawn and Dusk are the first `TRANSITION_SECONDS` (90s) of the day and night phases respectively; the rest of each phase is the settled state. The HUD reads `"Day 2 — Dusk"` — the day *number* only advances at dawn, so night 2 is still part of day 2.

**Tint.** A `CanvasModulate` created by `DayNightCycle` cross-fades `DAY_TINT` (white) → `NIGHT_TINT` (`0.52, 0.58, 0.82`) over the transition window, driven off `elapsed_in_phase` so it inherits the time scale for free. Two deliberate choices:

- **Night is a blue-shifted dimming, not a blackout.** Skeleton labour works through the night by design (§7's "undead don't sleep" perk) — making night unreadable would punish the player for a mechanic that's meant to be an *advantage*.
- **The HUD is not tinted.** `CanvasModulate` only affects its own canvas; the HUD lives in a separate `CanvasLayer`, so the settlement darkens and the UI stays legible. That's a consequence of where the node is parented, so don't "tidy" it into the HUD layer.

The fade's `from` colour is captured as the *actual current tint* at the moment the phase flips, not the previous phase's constant — so flipping phases mid-fade (only reachable by cranking the time scale, but still) eases from wherever it got to instead of snapping.

**Debug time scale.** A `1x / 10x / 60x` button at the right of the top bar, cycling via `DayNightCycle.cycle_time_scale()`.

> **How the scaling is applied:** it sets **`Engine.time_scale`**, which multiplies the `delta` Godot hands to every `_process`/`_physics_process` in the game. Every timer in this project is a delta accumulator — the day/night clock, `WorkerSystem`'s trip loop, `Building`'s resource tick, `EventSystem`'s event timer — so they all inherit the scaling with **no per-system plumbing**, and stay in sync with each other by construction. Godot also scales `SceneTreeTimer` and `Tween` by it, so nothing is left running at wall-clock speed. It does *not* scale input or rendering, which is what keeps it usable as a debug control.
>
> The practical consequence for future work: **if you add a timer, use `delta` accumulation or a `SceneTreeTimer` and it just works.** A timer built on `Time.get_ticks_msec()` or `OS.get_unix_time()` would silently ignore the speed control and desync from everything else — don't.

It's labelled debug because it is one: a way to watch a 50-minute cycle or a gathering trip without waiting, not a player-facing game-speed feature.

