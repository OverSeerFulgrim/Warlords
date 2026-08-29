# SORTIE SPEC — Carrying It, and Getting It Home (R2)

**Status:** Draft for review, 2026-08-06. Details `ROGUELITE_REWORK.md` §1 (the banking rule) and
§5 (the sortie loop), and covers the two R2 pieces `LOOT_SITES_SPEC.md` put out of scope: **carry
capacity** and **deposit-at-lair**. Nothing here is implemented.

**Scope:** the return leg. Party carry capacity and how it is spent, the deposit step and what
banking means in R2, remainder charges left at sites, dropping a load, what death does to an
unbanked haul, and the pressure the day clock puts on all of it. This document *begins* where
`LOOT_SITES_SPEC.md` ends — at `Necromancer.carried` — and stops when the load is in `GameState`.

**Out of scope, specced separately:** what sites yield (`LOOT_SITES_SPEC.md`), who walks with him
and what they haul (`ESCORT_SPEC.md` — this doc defines the *capacity arithmetic* the escort feeds,
not the escort's behaviour), Raven pings (`RAVEN_SPEC.md`), and the run-scale bank (R4/R5).

**Companion documents:** `ROGUELITE_REWORK.md` (§1, §5, §8, §13), `LOOT_SITES_SPEC.md` (§5 loot
tables, §7 relics), `WORLD_MAP_PLAN.md` (§3 travel times, §9 danger from choices), `CLAUDE.md`
(conventions this spec is written against).

---

## 1. Design goals

1. **The banking rule is the whole game, at this scale.** Nothing is yours until it is home
   (`ROGUELITE_REWORK.md` §1). The trip loop already proves this works — resources enter `GameState`
   only on deposit — and the sortie is the same rule at a longer range with a bigger number on the
   line.
2. **The return leg must be a decision, not an errand.** If walking home is dead time, the loop is
   half-built. What makes it live: the load is heavy, the sun is going down, something is following
   you, and there is one more grave forty seconds the wrong way.
3. **Capacity pressure comes from one number, not from a system.** Carry capacity is Endurance,
   the rule every other unit follows (FOUNDATION_SPEC §6; reworded 2026-08-06 per COMBAT_SPEC
   §2.1's adopted rework — was Might, and the values are identical where it matters: skeleton
   End 4, villain End 6). No bespoke villain carry stat, no bags, no encumbrance curve. Scarcity
   is created by *what sites yield*, not by inventing a second stat.
4. **The escort is the relief valve, and it costs the economy.** More hauling capacity means more
   dead walking with you, which means fewer dead digging at home. That trade is the answer to
   "carry feels too tight" — never a bigger number on the villain.
5. **Full hands are a state you can be in, not a wall you hit.** Arriving at a rich site with no
   room must produce a *choice* (drop something, or walk the load home first), never a silent
   no-op. (An earlier draft listed "send an escort back" — struck by designer ruling 2026-08-06:
   the escort model is all bound undead following him, no unit orders, so independent delivery
   has no mechanic. If it ever exists it is a *spell* — R5 unlock material — not R2 plumbing.)

---

## 2. Party capacity

**The villain.** `Necromancer.carry_capacity()` returns Endurance (post-C2; the R1 code says
Might), currently **6** either way, and
`carry_space()` / `add_carried()` / `take_carried()` already implement the fungible half. No change
to that arithmetic — the capacity was built in R1 precisely so that the field and the panel agreed
from the start.

**The escort.** Each bound undead on a sortie hauls with the same rule: its own Endurance, through the
`carrying_kind` / `carrying_amount` pair `Laborer` already owns for the trip loop. **One kind per
escort member**, deliberately: a skeleton is a pair of arms, not a pack, and reusing the existing
single-kind fields means the worker deposit path works on them unchanged.

**Party capacity** is therefore the villain's mixed load plus one kind per escort member:

```
party_space() = villain.carry_space() + Σ (escort_member.endurance - escort_member.carrying_amount)
```

A starting sortie — villain alone — is 6 units. With two skeletons (End 4 each) it is 14. That
spread is the intended shape: **the first sortie of a run is cramped, and widening it is a
settlement decision, not a level-up.**

**Relics take a slot.** Per `LOOT_SITES_SPEC.md` §7 a relic occupies one carry slot and lives in
`relics_carried: Array` rather than the fungible Dictionary. It counts against
`carried_total()` for capacity purposes and against nothing else. **Relics ride the villain only** —
the dead do not carry treasure, which keeps identity-bearing loot out of the single-kind escort
fields and makes "the escort died with the crypt relic" impossible.

**Filling order.** Loot rolls into the villain first, escort second, remainder third (§4). Not the
reverse: the villain is who survives, and if the party is going to lose someone on the way home it
should not be the one holding the haul.

---

## 3. The deposit

**Where.** At the Throne, within `DEPOSIT_RADIUS_PX` — **1.5 cells**, reusing
`CombatSystem.THRONE_REPAIR_RADIUS_PX`'s precedent rather than inventing a second "close enough to
the Throne" number.

**Not the lair band.** `TravelLog` already treats `world.lair_band.has_point(...)` as *home*, and
that is right for measuring a journey — but it is wrong for banking. The band is 20×20; crossing its
edge is not an arrival. Making the player walk the last few cells to the Throne keeps the final
seconds of the return leg real, and it is where the fantasy puts the hoard anyway.

**How.** Automatic on arrival, no button. The worker trip loop deposits without a prompt and the
sortie should read as the same rule at a longer range — a confirmation dialog between the player and
the thing they walked four minutes for is friction, not tension. The escort deposits in the same
frame, through the same path.

```
villain within 1.5 cells of the Throne
  → for each kind in villain.take_carried():   GameState.add_resource(kind, amount)
  → for each escort member with a load:        GameState.add_resource(kind, amount), clear it
  → for each relic in relics_carried:          bank it, activate its effect (LOOT_SITES §7)
  → EventBus.sortie_deposited(villain, load: Dictionary, relics: Array)
  → TravelLog closes the round trip and names the haul
```

**Partial deposits are free.** He can walk home half full, drop it, and go back out. There is no
minimum and no penalty — the tax is the walk, which is the only tax the design wants.

**Relic effects activate here**, per `LOOT_SITES_SPEC.md` §7: banked = real, the §1 banking rule
applied to power. A relic in hand grants nothing, which is what keeps "drop it and run" a live
choice on the return leg rather than a pure loss.

---

## 4. Remainder charges

From `LOOT_SITES_SPEC.md` §5: what doesn't fit **stays at the site as a remainder charge** — not on
the ground, not vaporized.

- A site with a remainder keeps its actions, shows its unlooted sprite, and its inspection payload
  says what is still there (*"You left 3 bones and a gold ring."*). It is not "spent".
- Remainders survive the whole run. Walking home to empty his hands and coming back is a legitimate
  play, and the time cost is the balance.
- **No ground piles.** A dropped-loot entity on a 144×144 map is a second inventory system, a second
  set of sprites, and a save-format problem in R5. The site is already a container; use it.

**The one exception is deliberate drop** (§5).

---

## 5. Dropping, and the honest exit

The player needs a way to arrive at a crypt with full hands and still take the relic.

**`Drop` is an action in the inspection panel on the villain**, one row per carried kind plus one
per relic. Dropping while in reach of a site **returns the units to that site's remainder**;
dropping anywhere else **destroys them**, with the panel saying so before the click.

That asymmetry is the design: littering the wilderness with recoverable caches would turn the map
into a warehouse and make carry capacity advisory. Dropping into a site you are standing at is
reorganising your haul; dropping in open country is a sacrifice, and it should read as one.

---

## 6. Death, and the unbanked haul

R2 has no run lifecycle — `EventBus.villain_died` fires and `Main` logs *"the run would end here"*
(R4 owns the rest). Until then:

- **The load is lost on death.** `carried`, `relics_carried`, and every escort member's load are
  cleared by the death handler, before anything else reads them. This is §1's rule at sortie scale
  and it must be true from the first commit — shipping a version where death is free teaches the
  player the opposite of the lesson the run frame depends on.
- **The escort dies where it stands.** Bound undead are destroyed by `Combat`, not despawned; their
  loads go with them.
- Nothing else happens yet. He respawns at the Throne at full hp, the log is loud, and the chronicle
  line waits for R5.

---

## 7. The clock, which does this for free

No code connects travel to the day cycle; they interact because they share one clock
(`2026-08-world-population-r1.md`). R2 changes nothing here and gets the pressure anyway:

| Fact, measured in R1 | What it does to a sortie |
|---|---|
| Village round trip 4m04s vs a 30-minute day | ~7 round trips fit in a day; leaving late does not |
| Dusk spawns the wolf | A full-handed return leg meets a predator |
| Meal ticks serve while he is away | The settlement's problems accumulate off-screen |
| Roads are 1.35× and exposed (R3) | The fast way home is the watched way home |

**The one thing R2 must add** is legibility: the HUD already shows `Away 2m04s`, and it should also
show **carry state** (`Carrying 6/6 — full`) and, once the sun is low, a dusk warning on the same
readout. The player should never discover they were overloaded at nightfall by dying of it.

---

## 8. Data schemas

**No new data files.** Everything here is constants and code:

| Constant | Home | Value | Why |
|---|---|---|---|
| `DEPOSIT_RADIUS_PX` | `Main` or a new `SortieSystem` | `1.5 * CELL_SIZE` | matches the Throne-repair radius |
| `carry_capacity()` | `Necromancer` (exists) | `Endurance` = 6 (Might until C2 migrates) | FOUNDATION_SPEC §6, one rule |
| escort haul | `Laborer.carrying_*` (exists) | `Endurance` per member | the trip loop's own fields |

`LOOT_SITES_SPEC.md` §8's `loot_tables.json` is where yields get tuned against this capacity. The
carry number itself stays in code because it is a *rule*, not content.

---

## 9. Code touchpoints

| Where | Change |
|---|---|
| New: `scripts/villain/SortieSystem.gd` | Owns the deposit check (villain within `DEPOSIT_RADIUS_PX` of the Throne), the party-capacity arithmetic, the drop action's effects, and the death-clears-the-haul handler. Takes `villain`, `settlement` and `world` as fields — **never looks the villain up** (`ROGUELITE_REWORK.md` §11). One instance per villain. |
| `Necromancer.gd` | `relics_carried: Array` (from LOOT_SITES §7) counted into `carried_total()`. `take_carried()` unchanged — it is already the deposit half. Add `party_space(escort)` as a free function or leave the sum in `SortieSystem`; do **not** give the villain a reference to his own escort's capacity logic. |
| `Laborer.gd` | Unchanged. `carrying_kind`/`carrying_amount`/`abandon_trip()` already do what escort hauling needs. |
| `GameState.gd` | Unchanged beyond LOOT_SITES §9's `gold`. The deposit path is `add_resource()`, same as a worker's. |
| `EventBus.gd` | `sortie_deposited(villain, load: Dictionary, relics: Array)`, `sortie_load_dropped(villain, kind: String, amount: int, to_site)` (`to_site` null when destroyed), `relic_banked(villain, relic_id: String)`. All carry the villain. Mind signal arity — a handler missing an arg connects fine and fails silently at emit (CLAUDE.md gotcha). |
| `WorldSite.gd` | `remainder: Dictionary` alongside LOOT_SITES §9's charge state, on the node, same `ResourceNode` precedent and the same documented split trigger. |
| `InspectionPanel` / `InspectorActions` | Villain panel gains a Drop row per carried kind and per relic, and a "party carry" line. Reuses `necromancer_actions(box)` — no new panel, no new machinery. |
| `HudTopBar` | Carry readout beside the existing `Away` timer; dusk warning when the day cycle is inside the last N minutes and he is outside the lair band. |
| `TravelLog.gd` | The round-trip line names the haul (`"Home. Round trip 4m04s — 4 bones, 2 gold, a Sexton's Ring."`). It already has the round-trip hook; this is a string change plus a reference to the load. |

---

## 10. Verification and tunables

**Harnesses** (repo rule: tools re-derive every number). `tools/verify_sortie.tscn`, run headless as
a scene, not `-s` (autoload gotcha):

- capacity arithmetic: villain alone = 6; with two End-4 skeletons = 14; a relic consumes one slot
- `add_carried()` overflow leaves the exact remainder at the site and the site still offers actions
- deposit at 1.5 cells banks everything and empties villain *and* escort in one frame
- crossing the lair-band edge banks **nothing** (the band-is-not-the-Throne rule)
- drop-in-reach returns to the site; drop-in-open destroys, and the two paths emit different signals
- `villain_died` clears `carried`, `relics_carried`, and every escort load before any other handler
- a full round trip still lands inside `WORLD_MAP_PLAN.md` §3's 2–4 minutes with a full load
  (carry must not silently gate travel time)

Extend `tools/measure_travel.tscn` with one loaded-return row so the return leg is measured, not
assumed.

**Tunables** (§15-style open list):

- **Carry capacity (6) vs per-site yield** — the pair `LOOT_SITES_SPEC.md` §10 flagged, and the one
  that decides sortie length. Tune the *yield*, not the capacity: capacity is a rule.
  *If* that tuning cannot make the exit question real, the designated next lever (designer
  ruling 2026-08-29) is load slowing the carrier — adopted only by striking this spec's
  loaded-return-time assertion openly, never as a quiet tweak. Backpacks and the road-bound
  hand cart are recorded in `LOOT_SITES_SPEC.md`'s 2026-08-29 amendment, ruling 5 — gear v1+
  and R3+ respectively, not R2 answers.
- `DEPOSIT_RADIUS_PX` — 1.5 cells is a guess borrowed from Throne repair.
- Whether a partial deposit should cost a channel (currently free, and probably should stay free).
- Whether dropping in open country should be destructive at all, or merely lossy (e.g. half).
- How loud the dusk warning is, and at what hour it starts.
- Whether relics should be droppable *at all* once carried — currently yes, deliberately, because
  "drop it and run" is the tension §7's deposit-activation rule exists to create.

**Exit criterion for this slice** (feeds R2's overall exit): a sortie that fills the party's hands at
two sites, walks home at dusk with a wolf on the map, and banks the haul at the Throne — with at
least one moment where the player had to choose between one more pull and the light.
