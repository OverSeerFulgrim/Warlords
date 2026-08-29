# COMBAT FEEDBACK SPEC — Red Numbers, in Real Time

**Status:** Reviewed as-built (shipped in F1), designer review 2026-08-29. Originally drafted 2026-08-06. Small by design and independent of every other R2
slice — it can be built the day after P0 and makes every combat that follows (guardians, dens,
the villain's own melee) legible for free. Nothing here is implemented.

**Scope:** floating damage numbers over combatants, the one signal that feeds them, and the view
layer that draws them. **Out of scope:** hp bars beyond what exists (the wolf keeps its label),
hit sounds/screen shake (later polish, same signal), any change to the damage formula.

**Companion documents:** `Combat.gd` / `Engagement.gd` / `CombatSystem.gd` (the three-layer
split this slots under), `NECROMANCER_SPEC.md` (whose fights this makes readable), `CLAUDE.md`
(tokens are pure views; timers are delta accumulators).

---

## 1. Design goals

1. **Every point of damage is visible where it landed, when it landed.** Combat currently
   resolves in the log and in hp labels — accurate, but nobody watches a label during a fight.
   A red number above the head is the oldest legible answer there is.
2. **Views only.** Floats are a *view of an event*, not state. No sim object gains a field, no
   token gains a timer that matters. Kill the layer entirely and combat is untouched.
3. **One signal, every source.** The exchange loop is the only thing that deals damage today,
   but Throne repair heals and future traps/crusades will hurt. The signal carries
   *combatant, amount, kind* — anything that changes hp can emit it, and the layer never knows
   who called.
4. **Time-scale honest.** Floats animate on the same scaled clock as everything else
   (`Engine.time_scale` at 60× means a blur of numbers, and that is *correct* — a debug session
   at 60× is not a cinematic).

---

## 2. The signal

```gdscript
# EventBus
signal damage_shown(unit, amount: int, kind: String)   # kind: "damage" | "heal"
```

Emitted by **`CombatSystem`**, the policy layer, as it walks each `Engagement.tick()` result —
one emit per swing that dealt > 0, both directions of the exchange (`damage_to_a` and
`damage_to_b` are already in the result Dictionary; this is a read, not a change). Throne repair
emits `heal` for its +1s. `Combat.gd` and `Engagement.gd` are **not touched** — the formula and
the clock stay signal-free, per their headers.

`unit` is the data object (Laborer / Necromancer / Wolf / SiteGuardian), never a token — the
layer reads `unit.position` at emit time, the same the-view-is-a-frame-stale rule the click
hit-test learned. Mind the arity gotcha, as always.

---

## 3. The float

**New: `scripts/ui/CombatFeedback.gd`** — one Node2D in the settlement's coordinate space,
sibling of the token layers, subscribing to `damage_shown`. It owns a small pool of `Label`
nodes (cap **32**; past the cap the oldest float is recycled — a mass battle becomes a churn of
numbers, which reads fine and bounds the node count).

Per float:

- **Text `-N`** in the project's damage red — `Color(1.0, 0.35, 0.35)`, the same red the hp rows
  and the wolf's label already use, with the standard black outline (the wolf's 4px settings —
  legibility on snow was solved there once). Heals are `+N` in the muted repair green the panel
  uses. Font size ~13, a step up from the wolf's 11 — a number that exists for 0.8s must be
  read in 0.8s.
- **Spawn above the head**: at `unit.position`, lifted by the unit's drawn content height
  (`Anchoring.drawn_content_size()` where a sprite is reachable; one cell as fallback) plus a
  little clearance — above the wolf's hp label, not on top of it. ±6px horizontal jitter so the
  two halves of a simultaneous exchange never print on the same pixel.
- **Rise and fade**: ~0.5 cells upward over `FLOAT_SECONDS = 0.8`, alpha to zero over the last
  half. Driven by a delta accumulator in `_process` — **not** a Tween or SceneTreeTimer created
  per float; 32 pooled labels and one loop is the whole implementation, and it inherits the time
  scale by construction.
- Floats do not follow the unit after spawning. They mark where the hit landed; a fleeing
  recruit outrunning its own pain number is correct and reads well.

**What deliberately does not exist:** crit styling (no crits), damage type colors (no damage
types), stacking/merging of rapid hits (the jitter and the churn handle it), numbers over the
minimap, and any float on a 0-damage swing (cannot happen — `MIN_DAMAGE` is 1, but the emit
guard says `> 0` anyway so the invariant is stated twice).

---

## 4. Code touchpoints

| Where | Change |
|---|---|
| `EventBus.gd` | `damage_shown(unit, amount: int, kind: String)`. |
| `CombatSystem.gd` | Emits per exchange result in `_advance_engagement()`, and `heal` from `_tick_throne_repair()`. ~6 lines total. |
| New: `scripts/ui/CombatFeedback.gd` | The pooled layer, per §3. Built by `Main` beside `TokenLayer`; z above units, below fog and HUD. |
| `Main.gd` | Wiring only. |
| `Wolf.gd`, tokens, `Combat.gd`, `Engagement.gd` | **Unchanged.** |

---

## 5. Verification and tunables

**Harness** `tools/verify_combat_feedback.tscn`, headless as a scene: a scripted
`Combat.exchange()`-driven fight emits `damage_shown` once per landed swing with the right
amounts and signs; the pool never exceeds 32 children; emits with a dead/never-shown unit do not
error; 1,000 exchanges leak zero nodes (child count returns to baseline). Visual read —
*is the red number the first thing your eye finds when the wolf bites?* — needs a human, ideally
in the same session as the R1 feel playtest if this lands before P1.

**Tunables:** `FLOAT_SECONDS` (0.8), rise distance (0.5 cells), font 13, the 32-float cap,
whether heals should float at all (default yes, muted — watching the Throne knit skeletons back
together is quiet pleasure), whether the villain's own incoming damage deserves a louder
treatment (default no; `COMBAT_FEEDBACK` treats him like anyone — the HUD hp readout is his
special channel).

**Exit criterion:** during one dusk wolf fight at 1× speed, a player who never opens the log can
narrate the fight — who got hit, roughly how hard, and when the tide turned — from the numbers
alone.
