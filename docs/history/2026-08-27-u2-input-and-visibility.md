# Four input and visibility fixes from the R1 playtest (prompt U2)

Requests #1–#4 from `2026-08-27-r1-playtest-notes.md`, the two design conflicts having been
settled by the designer the same day. No new systems, no map changes, no economy changes.

## The right mouse button now means two things, and one place decides which

Right-drag was camera pan. Right-tap is now "walk there". Both gestures open with the same press,
so the split cannot live in two listeners without both firing on one gesture — the prompt asked
for one place, and the honest one is **`GameCamera`**, because it was already the only node
watching right-button press, motion *and* release. It owns the decision and emits `right_tapped`;
`Main` decides what a tap means, exactly as it already arbitrates left-clicks.

A tap is under **6px of travel and 250ms held**. `_drag_px` accumulates absolute motion rather
than start-to-end distance, so a wiggle that returns to its origin is still a pan. The thresholds
are deliberately generous in the tap direction: a tiny pan misread as a tap costs a short walk the
player can cancel with any key, where the reverse costs a click that silently does nothing.

A tiny pan does move the camera those few pixels before the gesture resolves. That is accepted —
holding the pan until release would make every real pan start with a lurch.

**The harness asserts the split stays in one place**: only `GameCamera` and `Minimap` may name
`MOUSE_BUTTON_RIGHT`. (The minimap is exempt because a drag across it is a click on a different
cell, not a pan — there is no second meaning there to separate out.)

## The click destination feeds the same movement vector, and does not bypass it

`Necromancer.step()` was already documented as the single owner of "where does he end up", with
the controller owning "what did the player ask for". The click target keeps that shape rather than
breaking it:

- `Necromancer.move_target` / `has_move_target` — destination is simulation state for the same
  reason `position` is.
- `Necromancer.target_direction(delta)` turns it into a direction vector, and nothing else.
- `VillainController._movement_input()` returns held keys if any (**clearing the target** — keys
  are the more direct statement of intent), otherwise that vector.
- `step()` receives it and cannot tell a click from a key.

So facing, terrain `speed_multiplier`, the blocking slide, idle-resume and idle pacing all keep
working with no second copy of any of them. Arrival reuses the pacing's own epsilon
(`maxf(stride, 2.0)`) because it is the same problem: a target closer than one frame's stride
would be overshot and then chased back and forth.

**One behaviour beyond the prompt's list, flagged deliberately.** The prompt specified
cancellation "by any key input or arrival". Straight-line movement with no pathfinding also
produces a third case: walking into a cliff corner slides to a halt with the target still
outstanding, and he would then walk on the spot with `is_moving` true until the player pressed a
key. `TARGET_STALL_SECONDS` (0.5) ends it when position stops changing. Progress is measured in
position rather than intent, so sliding *around* a corner survives it.

A right-click while build placement, demolish or Command Undead is armed **cancels that mode and
does nothing else** — the same way those modes already treat a click they did not want. There is
no fog or walkability check on the destination: refusing to walk toward unexplored ground would
make the fog a fence, which is the opposite of what it is for.

## Fog: one disc became a lit set rebuilt from N sources

`update_for()` now takes a list of `[position, radius]` pairs and rebuilds the whole lit set from
it. The villain keeps **7 cells**, unchanged. Every friendly unit — worker, follower, bound undead
— carries `UNIT_REVEAL_RADIUS_CELLS` at **3**. `reveal_permanently()` is untouched: the lair band
is still the only thing that never dims.

**Rebuilding wholesale rather than diffing is the load-bearing choice.** Overlapping discs make
"which cell does this unit still own" a reference-counting problem, and a refcount that leaks by
one leaves a cell permanently lit — precisely the bug three-state fog exists to prevent. A rebuild
cannot leak: what is lit is a pure function of where the sources are this frame.

Sources come from `WorkerSystem.all_units()` rather than `laborers()`. A skeleton bound to a rally
point is off the workforce but still standing in the world with its eyes open, and that is exactly
the playtest's case — 33 bound undead.

### What it costs, measured at the playtest's own 34 sources

| Path | Cost per call | Share of a 16.7ms frame |
|---|---|---|
| Standing still (the early-out) | **23 µs** | 0.14% |
| Full rebuild (34 discs + texture upload) | **1.6 ms** | 9.8% |

The early-out is what makes this affordable, so it is asserted rather than assumed: 34 sources
standing still for 10 frames produce **zero** rebuilds, a sub-cell nudge produces zero, and
crossing a cell boundary produces exactly one. `update_for` is called once per frame, so 1.6ms is
the true worst case — every frame in which *someone* changed cell — not a figure that scales with
how many of them moved.

The comparison key stores each source's cell as an x,y pair rather than a flattened index, so a
unit walking the map rim cannot alias onto another cell's index and freeze the fog on a false
match.

## The minimap rule was never "hide everything"

The header said **"no live contents"**. Amended to **no live *hostile or neutral* contents**: the
wolf, the deer and the patrols stay hidden because seeing them through fog would undo it, but your
own units are not intelligence about the world. The rule the original wording was reaching for was
"the fog must not be readable from the HUD", and a dot on ground your own worker is standing in
reveals nothing the world view was not already showing.

Workers, followers and bound undead draw as 2px dots in `FRIENDLY_COLOR`, a desaturated blue-grey
picked to stay clearly apart from the green lair ring and the warm yellow villain marker at the
3–4px those are drawn at. Dim on purpose — thirty of them must read as "my people are over there"
without out-shouting the two markers that actually orient you. They draw **under** the villain, so
a worker standing on him cannot hide him.

A dot is drawn only where the fog says VISIBLE or REMEMBERED. Since friendly units light their own
ground that is always true today; the check is there so it stays true if that ever changes.

The minimap takes its own clicks now (`mouse_filter` STOP, `_gui_input`), so a click on it never
reaches `Main._unhandled_input` as a world click. Left-click centres the camera; right-click walks
him there. Both convert through `_from_map()`, written as the algebraic inverse of `_to_map()`
rather than re-derived, so the two cannot drift apart.

**Follow is left alone unless it was already on**, in which case a minimap click breaks it exactly
as a manual pan does. It does not bump `manual_pan_ticks` — it calls `stop_following()` directly —
because the tick counter is how *the camera* announces a hand-pan, and the minimap is not one.

## Verification

`tools/check_fog_and_minimap.tscn`, **41 assertions, all passing**, and kept in the repo: the
lit-while-present invariant is invisible until it breaks, and it is the exact bug a refcounted
implementation would introduce.

Covering: both radii unchanged; a worker 20 cells from the villain (outside his disc, and outside
the lair band, or the test would pass regardless) lighting a 3-cell disc that is round rather than
square and ~29 cells in area; that disc returning to REMEMBERED — not UNEXPLORED — when the worker
is removed, with none of it sticking; the early-out and the frame costs above; the minimap's
click filter, its colour separation, and `_from_map` round-tripping through `_to_map`; the
source-scan for hostile unit types (comments stripped first — the R1 version of this check failed
on the header's own prose, which names the units it ignores); and the full input wiring.

The **input wiring is tested at the signal level, not the gesture level**: simulated input reaches
neither `_unhandled_input` nor `Input.is_key_pressed` in this project (CLAUDE.md's first gotcha),
so the harness emits `right_tapped` / `camera_requested` / `move_requested` and asserts on what
they change — target set to the tapped point, thirty `step()` calls actually moving him toward it
with `is_moving` true, arrival clearing it, an armed rally mode eating the tap and *not* also
walking him, the camera jumping and follow dropping, and follow staying off when it already was.

`check_sprite_scales` (40/40) and `measure_travel` (all §3 rows unchanged) both still pass, and
the headless boot is clean.

**Still needs a human at the keyboard:** the two minutes of actual play. Whether 6px/250ms is the
right tap threshold under a real hand, whether the 3-cell disc reads as "my people see a little"
rather than as scouting, and whether a right-tap walk across broken ground feels like a move order
or like a bug — none of that is something a harness can judge. The mechanics are confirmed; the
feel is not.

One eyeball that did happen: a seeded windowed capture confirms the three marker types are
distinguishable on the real minimap at real size — green lair ring, yellow villain, blue-grey
friendly cluster — and the legend now reads `○ lair  ● you  · yours`.
