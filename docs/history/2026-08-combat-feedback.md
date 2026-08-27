# Red numbers, in real time (COMBAT_FEEDBACK_SPEC)

Floating damage numbers over every combatant, built to `docs/design/COMBAT_FEEDBACK_SPEC.md`.
Changes no gameplay: combat resolves exactly as it did, and deleting the new node leaves the
simulation bit-identical. It only makes what already happens visible.

## One signal, and the two files that must never see it

`EventBus.damage_shown(unit, amount: int, kind: String)` — `kind` is `"damage"` or `"heal"`,
`amount` is always positive and always the hp *actually* applied rather than the roll.

**`CombatSystem` is the only emitter.** `Combat.gd` (the formula) and `Engagement.gd` (the clock)
are untouched, which is the spec's hardest constraint and the one a later change is most likely to
breach for convenience — it is one line to emit from inside the exchange, and it would quietly
demolish the three-layer split both files' headers describe. The harness asserts it against the
source: neither file may contain the string `EventBus` or `damage_shown`.

Emission is a **read** of the Dictionary `Engagement.tick()` already returns. `damage_to_b` is the
defender's, `damage_to_a` is the wolf's — both directions, because the half most easily forgotten
is that the wolf is taking damage too, and a fight where only your own losses show is a fight you
read backwards.

They are emitted *before* the consequence checks in `_advance_engagement()`, deliberately: a unit
that dies on this exchange must still show the number that killed it, and `_resolve_defeat()`
removes it from the engagement.

Both sites funnel through one private guard:

```gdscript
func _show_hp_change(unit, amount: int, kind: String) -> void:
    if unit == null or amount <= 0:
        return
    EventBus.damage_shown.emit(unit, amount, kind)
```

`Combat.MIN_DAMAGE` is 1, so a landed swing cannot be zero — but a Throne repair on a full-hp
worker can be, and a future damage source might be. Stating the invariant once, in one place,
beats stating it at each call site and getting it right twice.

`unit` is the **data object**, never a token. The layer reads `unit.position` when it draws,
because a token's position is a frame stale — the same rule the click hit-test had to learn.

## The float: a pool of 32 and one clock

`scripts/ui/CombatFeedback.gd`, a Node2D in the settlement's coordinate space, sibling of the
token layers, `z_index` 10 — above the units (the wolf's 6 is the highest) and far below the fog's
100, so a number over a unit standing in fog is hidden along with the unit, which is right.

It subscribes to the signal itself and is handed **no references at all**. A view of an event
needs none, and that is what makes the next damage source — a trap, the crusade, a spell — draw
through it for free.

- **32 `Label`s, created once in `_ready`, reused forever.** Past the cap the oldest float is
  recycled, so a mass battle becomes a churn of numbers: reads fine, and bounds the node count at
  exactly `MAX_FLOATS` no matter what happens in front of it. "Oldest" needs no spawn counter —
  every float has the same lifetime, so the largest `_elapsed` *is* the oldest.
- **One `_process` loop over the pool**, not a `Tween` or `SceneTreeTimer` per float. Less
  machinery, and — the load-bearing reason — `_process(delta)` is already time-scaled, so the
  floats inherit `Engine.time_scale` by construction. A per-float `SceneTreeTimer` would have been
  CLAUDE.md's timer trap in a new costume.
- Red `-N` in the panel's `Color(1.0, 0.35, 0.35)`; heals `+N` in `Building.gd`'s muted repair
  green. The wolf label's 4px black outline, unchanged — legibility of small text on snow was
  solved there once and there was no reason to solve it differently a second time.
- Font 13, ±6px horizontal jitter (the two halves of one exchange are emitted in the same frame
  and must not print on the same pixel), rise 0.5 cells over 0.8s, full opacity for the first half
  then out. A number that starts fading immediately is one you have to catch rather than read.
- Floats **do not follow the unit**. They mark where the hit landed; a recruit fleeing out from
  under its own pain number is correct and reads well.
- `set_process(false)` while nothing is animating, so the idle cost is zero.

**Head height comes from the token classes' public size constants** (`Wolf.TOKEN_SIZE`,
`NecromancerToken.TOKEN_SIZE`, `WorkerToken.SPRITE_TARGET_SIZE`), with one cell as the fallback
the spec allows. Those constants are the content heights fed to
`Anchoring.scale_for_content_height()`, so they *are* the drawn height by definition — and reading
them means the layer never reaches into another view's children and **no token needed changing**.
The wolf's is a content width (the project's one width-scaled quadruped), which is what is wanted
here: its hp label is placed off the same constant, so measuring from it is exactly what keeps the
float above that label rather than through it.

## Verification

`tools/verify_combat_feedback.tscn`, **31 assertions, all passing**, headless as a scene (`-s`
compiles before the autoloads register, and this whole slice hangs off `EventBus`).

Covering the spec's §5 list: `Combat.gd`/`Engagement.gd` signal-free; a real `spawn_wolf()` fight
announcing once per landed swing with amounts equal to the hp that actually moved, on both sides;
the Throne's `+1` announced as a `heal`; 200 emits into a 32-slot pool leaving the child count
untouched while the cap is genuinely reached; null, undrawable and freed units and 0/negative
amounts drawing nothing and erroring nothing; and 1,000 exchanges leaking zero pool nodes, zero
nodes anywhere in the tree, and zero orphans.

**Two harness bugs worth recording, because both were the game working correctly and the test
being wrong.**

1. The Throne-repair test kept seeing no heal. Instrumenting it showed the victim leaving at
   `stage 1` and 50px out: repair only reaches a worker that is IDLE and by the Throne, and the
   trip loop hands an idle worker a job within a frame. Pausing `WorkerSystem` for the duration is
   less fragile than re-pinning the worker every frame and racing node order. It *still* saw no
   heal, because `_tick_throne_repair` skips anyone flagged `in_combat` — and **an engagement
   outlives the wolf that started it**: `Wolf.depart()` sets the wolf leaving, `CombatSystem` ends
   the fight on its own later tick. The fix was ordering: end the fight, then test the repair.
2. The pool and leak counts were reading two live floats that this harness never spawned. They
   were real: a wolf still biting a real skeleton through a departed-but-unfinished engagement,
   and the chewed-on worker being knitted back together beside the Throne at +1 every six seconds.
   `_quiet_the_settlement()` now waits on `is_fighting()` rather than assuming `depart()` did it,
   and heals everyone to full — removing the reason rather than suppressing the symptom.

## Visual read

Captured windowed from a scripted `spawn_wolf()` fight, shot on the frame a number is emitted.

At **1×** both halves of the exchange are legible at once — `-3` above the wolf's `15 hp` label,
`-5` beside it on the worker, the jitter keeping them apart, the black outline holding on both
snow and dirt.

At **60×** each float lives 0.8s of game time — about **13ms of wall clock, under one rendered
frame**. Captured on the emit frame the numbers are there and correct; a frame later they are
gone. That is the spec's "blur, and that is correct": they flicker rather than pile up, and the
pool never approaches its cap.

**Still needs a human:** the exit criterion is that a player who never opens the log can narrate a
dusk wolf fight from the numbers alone — who got hit, roughly how hard, when the tide turned. The
mechanics and the legibility are confirmed; whether the red number is the first thing your eye
finds when the wolf bites is a judgement a screenshot cannot make. Best asked in the same session
as the R1 feel playtest.
