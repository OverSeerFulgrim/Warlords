# NECROMANCER SPEC — His Own Two Hands (R2)

**Status:** Draft for review, 2026-08-06. Answers the open tunable `ROGUELITE_REWORK.md` §15 has
carried since the rework was written — *"Necromancer combat stats, and whether a protective aura
applies inside his own lair"* — and gives the villain the one thing R2's world makes urgent:
**a way to fight back.** Nothing here is implemented.

> **Amendment, 2026-08-06 (same day) — written against C2, and he is Arcane.** `COMBAT_SPEC.md`'s
> stat rework was adopted into the build order the day this spec was drafted (its amendment
> block; prompt C2 in `R2_PROMPTS.md`), so this spec now speaks the nine-attribute language:
> the villain gets a full statline (§2) and his profile is **Arcane** — Intelligence-driven,
> 5-cell reach — by designer decision. §3's engagement model is the engage-close/cast-far split
> that decision requires. Where this file says Endurance or Intelligence and the R1 code says
> Might, C2 is the migration point.

**Scope:** what the villain is in a fight — his stats confirmed, how he attacks (and the input
model that keeps it order-free), retaliation, what hunts him once the lair aura goes positional,
what his hp thresholds do, death in R2, and the spell surface his kit hangs off.

**Out of scope, specced separately:** the escort that fights *for* him (`ESCORT_SPEC.md`), what
he loots and carries (`LOOT_SITES_SPEC.md`, `SORTIE_SPEC.md`), damage legibility
(`COMBAT_FEEDBACK_SPEC.md`), new spells and the XP that unlocks them (R5 —
`ROGUELITE_REWORK.md` §9).

**Companion documents:** `ROGUELITE_REWORK.md` (§5 the killable villain, §11 per-villain state,
§15 open tunables), `COMBAT_SPEC.md` / `Combat.gd` (the one formula), `ESCORT_SPEC.md` (§4
cover-the-retreat, which reads the thresholds set here), `CLAUDE.md`.

---

> **Amendment, 2026-08-29 — spec review (designer). Two rulings: regen, and the hot-slot row.**
> Where this block disagrees with the body below, this block governs; prompt R2b builds
> ruling 1 and does not build ruling 2.
>
> **1. He regenerates — slowly afield, strongly at home.** §10's "out-of-combat regen:
> currently none" is struck. Out of combat he heals: a slow trickle outside the lair band,
> **greatly increased inside it** — driven by the *same* §5 position test the aura uses, which
> is the whole implementation: one test, two consequences (protection, and recovery). Regen is
> suppressed entirely while engaged. Rates are tunables; the constraint that sets them is that
> the field trickle must never let a den fight be reset by circling the clearing — waiting to
> heal must cost *daylight* the player feels. This adds the missing push-your-luck dial: a hurt
> villain in the field can now trade sun for health instead of only limping home.
>
> **2. The hot-slot row — designed now, built with R5's spell unlocks.** Above the command
> bar, slots 1–9: press the number or click the slot to select a spell, then aim it where the
> spell takes a target. This is the designed input model for §7's spell surface as it grows —
> recorded now so R5 inherits it designed rather than improvised. **The hard line: a hot slot
> can never hold an attack.** His combat casting stays proximity-engaged (§3) — walk in, he
> fights; walk out, he stops — and no spell that lands damage on a hostile may ever sit behind
> a key. The hotbar is for spells-as-tools (Command Undead today; wards, rituals, and the R5
> kit later). Not built in R2: two spells do not need nine slots.

---

## 1. Design goals

1. **He fights with his own hands only when the player walks him into it.** No attack button, no
   target cursor, no selection box — the input model stays "WASD drives him, the world reacts."
   Walking into a fight and walking out of one are the same verb as everything else he does,
   which is what keeps his combat inside the direct-control carve-out instead of growing a unit-
   order UI beside it.
2. **Command Undead stays his real weapon.** His personal magic is a sidearm: enough to finish a
   lone wolf, clear a Band-2 nuisance, or survive to the treeline — never enough to make the
   escort optional. If solo sorties into Band 3 are winning fights, his numbers are wrong, not
   the guardians'.
3. **One formula, no exceptions.** He already implements the full Combatant contract and
   `Combat.exchange()` already lands on him. This spec adds *policy* (when he swings), never
   arithmetic — there is no villain damage formula, there is `Combat.damage_roll()`.
4. **The aura becomes geography.** "Wolves will not approach the Necromancer" was a settlement-era
   rule. It becomes a *lair* rule literally: protection inside the lair band, a fair fight
   everywhere else — a position test, not a second flag (`ESCORT_SPEC.md` §9 already insists).
5. **Dying must be legible.** He is the run (R4). Every point of damage he takes must be visible
   (`COMBAT_FEEDBACK_SPEC.md`), every threshold announced, and the difference between "hurt,"
   "the dead close ranks," and "dead" unmistakable.

---

## 2. What exists, confirmed as the baseline

The R1 data object (`Necromancer.gd`) carries everything this spec builds on. Under C2 his single
`BASE_MIGHT = 6` becomes a full statline, chosen so that **every number the R1/R2 tuning already
depends on is preserved**, authored in `stat_rework_roster.xlsx` beside the races:

| Attribute | Value | Why this number |
|---|---|---|
| Strength | 4 | he is not a swordsman; a skeleton out-arms him |
| Dexterity | 4 | " |
| Speed | 5 | → walk 1.0 cells/sec via the workbook divisor — **the tuned travel value, untouched** (`TERRAIN_SPEC.md` §9: not a knob) |
| Endurance | **6** | hp `8 + End × 2` = **20** and carry = **6** — both exactly the R1 values `SORTIE_SPEC.md` builds on |
| Intelligence | **7** | his attack stat; highest of Str/Dex/Int → **Arcane profile** by rule 3, no special case |
| Guile | 6 | a hidden villain lies well; Stage-4 stealth reads it |
| Perception | 6 | feeds nothing yet; judgement is C3's and never applies to him (the player is his judgement) |
| Tact | 5 | " |
| Loyalty | — | meaningless on the villain; authored as `—` in the workbook |

Confirmed alongside: the complete Combatant contract (`take_damage()` already emits
`villain_died` on any lethal source — keep death announcement on the data object, not in a policy
layer), and relics may move attributes (`sermon_of_ash` +1 Int) while levels never do (§2 of the
rework).

What is missing is exactly one thing: **nothing initiates an exchange for him.** He can be hit
and cannot hit. `CombatSystem`'s comment block says so out loud — he is not in
`_prey_candidates()`, and no consequence rule has a branch for him. This spec is that branch.

---

## 3. The attack — engage close, cast far

**Model: two radii, one for starting and one for fighting.** Starting a fight is *deliberate and
close*; fighting one is at his arcane reach. Both halves are load-bearing:

- **Engaging:** a fight opens only when the villain closes to `VILLAIN_ENGAGE_PX` (the wolf's
  `ENGAGE_RADIUS_PX` = 26px — one "close enough" number in the whole game) of a hostile, or when
  a hostile attacks him first (§4). **Walking in is attacking.** The panel and log say so
  (*"He raises a hand, and the air goes cold."*).
- **Casting:** once engaged, he exchanges on the shared `Combat.EXCHANGE_INTERVAL` clock at his
  **Arcane reach — 5 cells** (`COMBAT_SPEC.md` §3's profile table), Intelligence against the
  defender's Intelligence, through an ordinary `Engagement`. The escort closes to melee while he
  casts over their shoulders — the class fantasy, produced by the profile table with no bespoke
  code.
- **Why the split matters:** a single 5-cell auto-engage would have him sniping every wolf that
  wandered past — breaking "he never auto-seeks" and turning stealth-by-default into a lie. With
  the split, *starting* a fight still costs the walk into biting distance, but *running* one
  rewards positioning: he can fall back behind the escort and keep casting.
- **Walking out is disengaging.** Unlike every other combatant, `in_combat` never roots him —
  the player can always drive him. Move beyond his 5-cell reach and his exchanges stop; the
  hostile then does whatever its own policy says. Kiting is a real but bounded tactic: a wolf
  chases at 78px/s against his 64 — it *will* catch him, so range buys him two or three free
  casts, not immunity. That arithmetic is the sidearm's whole balance and the harness asserts it.
- **He never auto-seeks.** No target acquisition, no "attack nearest." Standing still beside a
  hostile that hasn't noticed him starts nothing (stealth is the fiction's default state, and a
  future backstab mechanic wants that door left open).
- **Fighting while escorted is one fight.** If the escort is engaged with the same hostile, he
  joins the existing `Engagement` as another defender — the same pile-in rule three skeletons
  already follow.

---

## 4. Retaliation, and being hunted

- **Anything that hits him is engaged back** automatically from the next exchange — being
  attacked and standing your ground is a fight, no input needed. Driving him away is still the
  player's out, per §3.
- **Outside the lair band he is prey.** `_prey_candidates()` gains the villain (per-villain
  reference, never a lookup) when the aura does not cover him — a dusk wolf, a den pack and a
  site guardian will all hunt him like anyone else. Danger from choices holds: he had to walk
  there.
- **Guardians hold their ground.** `SiteGuardian`s engage him inside their radius and do not
  pursue past it (`LOOT_SITES_SPEC.md` §3) — breaking off from a den fight is always
  geographically possible, which is what makes starting one a choice.

---

## 5. The aura, made positional

`LAIR_AURA_PROTECTS_VILLAIN` stops being a global bool and becomes a position test, exactly as
`ESCORT_SPEC.md` §9 prescribes: **the aura holds while the villain is inside `world.lair_band`,
and nowhere else.** Inside it, the settlement-era promises stand unchanged — wolves fear him,
nothing targets him, and anything in his shadow is invisible to predators. One band-edge, one
rule, no flag.

Consequence worth stating: the lair band is now *mechanically* home. Fleeing a botched sortie
back across the band edge is reaching sanctuary, which gives the return leg (`SORTIE_SPEC.md`)
a finish line the fiction already believed in.

---

## 6. Thresholds, and what they announce

| Threshold | What happens | Who owns it |
|---|---|---|
| hp < 100% | red numbers already told the story per hit | `COMBAT_FEEDBACK_SPEC.md` |
| hp < `FLEE_HP_FRACTION` (30%) | **He does not flee — the player decides.** The escort interposes (*"The dead close ranks."*), the HUD hp readout goes red, one log line fires | `ESCORT_SPEC.md` §4; HUD here |
| hp = 0 | `villain_died` (already emitted by the data object). R2: haul cleared (`SORTIE_SPEC.md` §6), loud log, respawn at the Throne at full hp. The run ending is R4 | `SortieSystem` death handler |

No auto-flee is deliberate and load-bearing: removing player control at low hp would break the
one carve-out the control pillar makes, and panic is the player's job. The game's whole duty at
30% is to make sure nobody dies *uninformed* — the informing is specced, the deciding is not.

**Healing:** dawn at full-band-rest only heals via the existing paths (Throne repair is for
skeletons; he is not one). R2 adds exactly one villain heal: `chipped_censer`'s 2 hp at dawn
(`LOOT_SITES_SPEC.md` §7) once banked. If sorties end up hp-gated rather than time-gated, the
tunable to reach for is a slow out-of-combat regen (§9) — not bigger numbers.

---

## 7. The spell surface — where the kit grows

Formalized so R5's unlocks land somewhere instead of being invented then: **a spell is an
`InspectorActions` entry on the villain, driven by a `spells: Array` on the class.** The
Necromancer's R2 list:

| Spell | Surface | Exists |
|---|---|---|
| Command Undead: Rally | place the point | today |
| Command Undead: Escort | anchor the point to him | `ESCORT_SPEC.md` §3 |
| Raise the Corpse | grave choice sheets, not the panel — a *ritual at a site*, which is what site actions are | `LOOT_SITES_SPEC.md` §4 |

That third row is the pattern for growth: cheap spells live on the panel, ritual spells live at
sites. New spells are R5 unlock material (`ROGUELITE_REWORK.md` §9) and get their own spec when
the XP system exists; nothing in R2 should build a "spellbook" UI for a list of two.

---

## 8. Data schemas

**No new data files** beyond what C2 already exports (his statline rides `stat_rework_roster.xlsx`
→ the class data). Constants and one small refactor:

| Constant | Home | Value | Why |
|---|---|---|---|
| `VILLAIN_ENGAGE_PX` | `CombatSystem` | `Wolf.ENGAGE_RADIUS_PX` (26) | one "close enough to start" number |
| arcane reach | profile table (C2) | 5 cells | `COMBAT_SPEC.md` §3 — his by profile, not by constant |
| aura test | `CombatSystem` | `world.lair_band.has_point(world.cell_at(villain.position))` | §5 — a position, not a flag |
| statline | workbook → class data | §2's table | End 6 / Int 7 preserve every R1 number |

`LAIR_AURA_PROTECTS_VILLAIN` the *flag* is deleted in the same commit the position test lands —
a dead flag beside a live rule is how the next reader flips the wrong one.

---

## 9. Code touchpoints

| Where | Change |
|---|---|
| `CombatSystem.gd` | The policy: the engage check (26px to start, aura permitting) and the 5-cell cast-range check each frame, opening/joining/leaving an `Engagement`; villain added to `_prey_candidates()` when unprotected; a consequence branch for him (never injured-and-flee — he is not a Follower; his zero is `villain_died`). The aura position test replaces the flag everywhere it is read, including `Wolf.get_inspect_data()`'s promise line. |
| `Engagement.gd` / `Combat.gd` | **Unchanged by this spec.** C2 already widened the Combatant contract to profiles (`COMBAT_SPEC.md` §4.1); this spec only *uses* it. If either file needs an edit here, the design has drifted — stop. |
| `Necromancer.gd` | Nothing structural: he already implements the contract. `in_combat`-equivalent state is *not* added — his engagement membership lives in `CombatSystem`, because rooting him is the one thing it must never do. |
| `VillainController.gd` | Unchanged. Movement is movement; disengage-by-walking falls out of the reach check. |
| `EventBus.gd` | `villain_engaged(villain, foe_name: String)`, `villain_disengaged(villain, foe_name: String, reason: String)`. Arity gotcha as ever. |
| `HudTopBar` / `InspectionPanel` | hp readout goes red below 30%; activity row says "Fighting —" with the foe's name. |

---

## 10. Verification and tunables

**Harness** `tools/verify_villain_combat.tscn`, headless as a scene:

- inside the lair band nothing targets him and closing opens no exchange; one step past the band
  edge, both are live (the §5 position test, asserted from both sides)
- walking within 26px of a hostile wolf outside the band starts an `Engagement` within one
  exchange interval; once engaged he lands exchanges from up to 5 cells; walking beyond 5 cells
  stops his swings the next interval
- a hostile that hits him first is engaged back with no input, from range
- kiting is bounded: against a chasing wolf, simulated flat-ground retreat yields at most 2–3
  exchanges before the wolf closes — if it yields more, Speed or chase numbers have drifted
- his death clears the haul before any other handler (cross-check `verify_sortie`) and he
  respawns at the Throne
- Int 7 vs one wolf (Int 2): simulate 1,000 fights, he wins the large majority but averages
  meaningful hp loss (the §1.2 "costly win" shape, asserted as a band not a point — wolf Int is
  the knob if arcane runs hot)
- vs a 3-wolf den pack, no escort: he loses or flees the large majority — the den is not
  soloable at baseline, also asserted as a band

**Needs a human:** whether walking into engage range *feels* like a decision or an accident —
and whether casting-over-the-escort reads on screen, which is the payoff the Arcane profile was
chosen for.

**Tunables:** `VILLAIN_ENGAGE_PX` (26); wolf Intelligence (2 — the arcane-vs-beast damage knob);
whether disengage should have a parting-shot cost (currently no — the chase *is* the cost);
out-of-combat regen (currently none); the 1,000-fight win-rate bands above; whether the aura
should shrink to Throne radius rather than the full band in later eras.

**Exit criterion for this slice** (feeds R2's overall exit): outside his lair, the Necromancer
kills a lone wolf with his own craft and it costs him a third of his health; he starts a den
fight alone, realizes the arithmetic, falls back casting behind his skeletons and still has to
run — and at no point did the game offer him an attack button.
