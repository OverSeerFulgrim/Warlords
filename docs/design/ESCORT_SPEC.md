# ESCORT SPEC — The Dead Who Walk With Him (R2)

**Status:** Draft for review, 2026-08-06. Details `ROGUELITE_REWORK.md` §5 (the escort behaves
automatically, built on the Command Undead order model) and covers the R2 piece
`LOOT_SITES_SPEC.md` put out of scope. Nothing here is implemented.

**Scope:** who joins a sortie and how, the standing-order model that drives them, their four
behaviours (follow, haul, engage, cover), what they cost the settlement, and how they die.

**Out of scope, specced separately:** party carry arithmetic and the deposit step
(`SORTIE_SPEC.md` §2–3 — this doc says the escort *hauls*, that one says how much), site loot
(`LOOT_SITES_SPEC.md`), Raven pings (`RAVEN_SPEC.md`), living followers on expeditions (R3+ — the
escort is undead-only in R2, see §2).

**Companion documents:** `ROGUELITE_REWORK.md` (§5, §11), `SORTIE_SPEC.md`, `CLAUDE.md` (the
indirect-control pillar, which this spec exists to not break), and the header comments in
`RallyPoint.gd` / `UndeadCommand.gd`, which already argue most of this.

---

## 1. Design goals

1. **No unit orders, ever.** GAME_OUTLINE pillar 2 survives intact. The player's lever stays a
   *spell with a target*, never a selection box with a move order. `RallyPoint.gd`'s header makes
   the argument: the dead have no will to override, which is the entire difference between a
   skeleton and a recruit. The escort is that same spell, anchored to a man instead of to the
   ground.
2. **Reuse the order model, don't parallel it.** A second follow-the-villain system living beside
   `UndeadCommand` would be two implementations of "the dead do what he says" drifting apart. There
   is one.
3. **The escort is the answer to "carry is too tight" and the reason it stays tight.** Every
   skeleton hauling for you is a skeleton not digging at home. That is the allocation question the
   spell was built to pose (`UndeadCommand.gd`: *"the dead can dig or they can fight, not both"*),
   now with a second thing to spend them on.
4. **Automatic, and legible about it.** The player never micromanages, but must always be able to
   answer *why did they do that* — the rally marker already draws its own radius for exactly this
   reason.
5. **Losing them must sting without being fussy.** An escort death is a real loss (a body, its
   load, and the labour it would have done), resolved by the existing combat code with no bespoke
   death path.

---

## 2. Who joins

**All bound undead, and nobody else.** Casting Command Undead in Escort mode binds every undead
labourer exactly as the existing `_bind_all()` does — `is_undead()` reads `alignment: "Undead"` out
of `races.json`, so the ghouls and wraiths on the roadmap join for free the day they exist.

**Deliberately not a chosen subset.** Picking which three skeletons to take is a selection UI, and a
selection UI is the per-unit control the pillar rules out. `UndeadCommand.gd` already records this
scope call; escort mode inherits it unchanged.

**Living recruits never escort in R2.** They have wills; commanding them is the thing the pillar
forbids, and the honest version — *volunteers*, gated on morale and loyalty — is a reputation-era
feature that belongs after R3's axes exist. Until then the party is the villain and his dead.

**Party size is therefore the roster**, not a cap. Six skeletons means six escorts and an empty
priority list; that is the decision, and putting a `MAX_ESCORT` on top of it would just hide the
cost the spell is supposed to expose. (`LOOT_SITES_SPEC.md` §7's `ledger_of_names` relic declares a
dormant "+1 escort cap" effect — when a cap arrives it lands here, and until then the relic stays
honestly marked dormant.)

---

## 3. The order model

**One new order on the existing enum**, and one new anchor concept.

```gdscript
enum Order { DEFEND, PATROL, ATTACK, ESCORT }
```

`RallyPoint` gains `follow: Object = null`. When set, `_process` copies `follow.position` into its
own `position` each frame. Everything downstream — `UndeadCommand._advance_bound()`, the arrive
epsilon, `_hostile_for()`'s measure-from-the-point rule, the drawn radius ring — works unchanged,
because none of it ever assumed the point was still.

That single field is the whole mechanism. It is why this is a spec of two pages rather than a new
system:

| Existing behaviour | What it becomes when the point follows the villain |
|---|---|
| March to the point, then hold | Follow him, then keep station |
| Engage hostiles within the order's radius, measured **from the point** | Engage what comes near *him*, and never chase past the leash |
| Re-cast moves the point | Re-cast re-anchors: to the ground (dismiss escort) or to him (resume) |
| Newly raised undead fall in automatically | A skeleton raised at a grave (LOOT_SITES §4) joins the escort on the spot |

That last row matters: **`raise the corpse` at a grave produces an escort member with no extra
code**, because the standing order is on the dead as a class and the `_process` loop re-binds every
frame. `LOOT_SITES_SPEC.md` §4 anticipates this ("dormant until escort lands, then retroactively
live") — this is the landing.

**Escort radius:** `ESCORT_RADIUS_PX = 2.5 cells`, between DEFEND's 1.2 and PATROL's 3.0. Tight
enough that the party reads as a group on screen at world zoom, loose enough that they don't
conga-line through a mountain pass.

**Casting it.** One action on the villain's inspection panel — *"Command Undead: Escort"* — beside
the existing rally placement. No targeting mode, because the target is him.

---

## 4. The four behaviours

`ROGUELITE_REWORK.md` §5 names them: *defend the Necromancer, carry loot, engage nearby enemies,
cover the retreat.*

**Follow.** `Roaming.step()` toward the moving point, exactly as the existing bound units do. They
route around terrain through `Roaming`'s `world` parameter, so predator, prey, worker and escort all
round a boulder the same way. Skeleton walk speed is 0.9 cells/sec against the villain's 1.0 — **the
escort is slightly slower than the man it follows**, which is correct: outrunning your guard is a
real decision on the return leg, and the leash makes it visible.

**Haul.** Loot overflow fills escort members via `Laborer.carrying_kind`/`carrying_amount`
(`SORTIE_SPEC.md` §2). A laden escort is unchanged in every other respect — no speed penalty, since
the trip loop doesn't have one and inventing one here would be a second encumbrance rule.

**Engage.** Unchanged from `_advance_bound()`: nearest valid hostile inside the radius, measured
from the point, then `combat_system.engage()`. In R2 the hostile pool grows from wolves to include
`SiteGuardian` (`LOOT_SITES_SPEC.md` §9) — `_hostile_for()` must stop iterating `combat_system.wolves`
specifically and iterate a **hostiles list** instead. That is the one real refactor in this spec.

**Cover the retreat.** The only genuinely new behaviour. When the villain drops below
`Combat.FLEE_HP_FRACTION`, escort members **interpose**: they target the position between him and
the nearest hostile rather than the hostile itself, and they do not break off. Undead don't rout —
the living-recruit flee rule explicitly does not apply to them — so "cover" is positioning, not
morale. It ends when he heals past the threshold or the hostiles are dead.

---

## 5. What it costs

**The labour pool, structurally.** `Laborer.can_labor()` already returns `not rallied`, so a bound
escort leaves the priority list the moment it is bound, with no new bookkeeping. The player watches
wood income stop when the party leaves. That is the feature.

**Anything half-carried is dropped.** `_bind_all()` already calls `abandon_trip()` and zeroes the
load, which also releases the node claim so a living recruit can pick the job up. Escort binding
inherits this unchanged.

**The settlement keeps running.** Meals, morale, housing and the wolf all tick while he is away
(`2026-08-world-population-r1.md` verified it mechanically). Taking every skeleton on a four-minute
sortie means coming home to a settlement that spent four minutes not gathering — and possibly to a
wolf.

---

## 6. Death

Escort members die through `Combat.exchange()` with **no bespoke path**. `worker_destroyed` already
exists and already fires; the escort adds nothing to it except that the body is a long way from
home.

- Their load dies with them (`SORTIE_SPEC.md` §6). No dropped pile — see that doc's §4 for why the
  map does not get ground loot.
- A destroyed escort member leaves the roster, which the priority list notices the way it always has.
- **No corpse recovery in R2.** Re-raising your own fallen escort is a good idea and it is a *spell*,
  which makes it R5 unlock material rather than R2 plumbing.
- If the whole escort dies the spell stays cast and simply binds nobody — `bound_count` goes to zero
  and the marker says so. Walking home alone with a full pack is the honest consequence.

---

## 7. Legibility

The player must be able to answer *why did they do that* without reading source:

- **The rally marker follows him**, drawing its radius ring as it always has — so the leash is
  visible at all times, and "why didn't they chase it" has the same visible answer it already had.
- **The villain's panel** shows escort count (it already does), plus each member's load and hp once
  there is an escort to show.
- **Cover state is announced**, not silent: one log line when they interpose (*"The dead close
  ranks."*), because it is the one behaviour the player didn't ask for.
- **Escort members stay individually inspectable** through the existing `get_inspect_data()`
  contract. Clicking a skeleton in the field is how you find out it is carrying your gold.

---

## 8. Data schemas

**No new data files.** Constants only:

| Constant | Home | Value | Why |
|---|---|---|---|
| `Order.ESCORT` | `RallyPoint` | new enum member | one order model, not two |
| `ESCORT_RADIUS_PX` | `RallyPoint` | `2.5 * CELL_SIZE` | between DEFEND and PATROL |
| `follow` | `RallyPoint` | `Object`, default null | the entire mechanism |

Escort membership is **not** persisted content: it is derived every frame from
"undead ∧ rallied ∧ the point follows the villain". `Necromancer.escort: Array` (which exists,
empty, since R1) becomes the cached view of that, written by `UndeadCommand` each frame and read by
the panel and `SortieSystem` — never the source of truth.

---

## 9. Code touchpoints

| Where | Change |
|---|---|
| `RallyPoint.gd` | `Order.ESCORT`, `ESCORT_RADIUS_PX`, `follow: Object`. `_process` tracks `follow.position` when set. `radius_for_order()` and `order_name()`/`ORDER_BLURB` gain their entries. Marker colour: a fourth, distinct from the existing three. |
| `UndeadCommand.gd` | `cast_escort(villain)` sets `rally_point.follow = villain` and binds as usual. `_advance_bound()` gains the interpose branch. **`_hostile_for()` stops iterating `combat_system.wolves` and iterates a hostiles list** so site guardians are targetable — the one real refactor here. Writes `villain.escort` each frame. |
| `CombatSystem.gd` | `hostiles() -> Array` unioning `wolves` and `WorldSites`' live guardians, so nothing downstream hard-codes a creature type again. The lair aura goes **positional in prompt R2b** (`NECROMANCER_SPEC.md` §5): a position test against `lair_band`, and the `LAIR_AURA_PROTECTS_VILLAIN` flag is deleted there. By the time this spec builds, the aura is already geography — escort code reads the same position test if it ever needs to, and never reintroduces a flag. |
| `Necromancer.gd` | `escort` becomes a written-each-frame cache with a comment saying so. `escort_count()` unchanged. No escort *logic* on the villain — he is data. |
| `Laborer.gd` | Unchanged. |
| `EventBus.gd` | `escort_bound(villain, count: int)`, `escort_member_lost(villain, unit, cause: String)`, `escort_covering(villain, bool)`. All carry the villain (`ROGUELITE_REWORK.md` §11). Watch arity. |
| `InspectorActions.gd` | An Escort action in `necromancer_actions(box)`; `rally_actions(box)` gains the fourth order and says when the point is anchored to him. |
| `Main.gd` | Wiring only. Input-mode arbitration unchanged — escort needs no placement mode, which is precisely why it is cast on him rather than targeted. |

---

## 10. Verification and tunables

**Harness** `tools/verify_escort.tscn`, headless as a scene:

- casting escort binds every undead and **only** undead; living followers are untouched and stay in
  `laborers()`
- bound escorts leave the labour pool (`can_labor()` false, workforce summary drops) and return to
  it on dismiss
- the point tracks the villain within one frame across 60s of simulated walking, including through
  a blocking-terrain slide
- escorts keep station inside `ESCORT_RADIUS_PX` and never exceed it chasing a hostile
- a skeleton raised at a grave joins the escort within one frame with no explicit add
- overflow loot fills escort members and banks on deposit (cross-check with `verify_sortie`)
- below `FLEE_HP_FRACTION` they interpose and do not break off; above it they resume
- an escort death removes it from the roster and destroys its load, via the ordinary combat path
- guardian targeting works through `hostiles()`, not through `wolves`

**Needs a human:** whether the party *reads* as a party at world zoom, and whether the leash feels
like protection or like a tether. Simulated input reaches neither `_unhandled_input` nor
`Input.is_key_pressed` (CLAUDE.md known constraint).

**Tunables:**

- `ESCORT_RADIUS_PX` (2.5 cells) — the single number that decides whether the party reads as a group
- skeleton 0.9 vs villain 1.0 cells/sec — deliberately a hair slower; if outrunning the guard proves
  merely annoying rather than tense, close the gap rather than removing the leash
- whether covering should also slow the villain (currently no — that is a control-removal, and the
  pillar carve-out is that *he* is always the player's to drive)
- whether a whole-escort wipe should force anything (currently no)
- when `LAIR_AURA_PROTECTS_VILLAIN` flips: at the band edge, or on the first sortie

**Exit criterion for this slice** (feeds R2's overall exit): a sortie leaves with three skeletons,
loses one to a site guardian, comes home with the other two hauling loot the villain had no room
for — and the player never issued a single unit order.
