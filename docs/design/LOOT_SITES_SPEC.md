# LOOT SITES SPEC — What the World Gives Up (R2)

**Status:** Reviewed and amended, 2026-08-29 (designer) — the dated amendment block below governs where it differs from the body. Originally drafted 2026-08-06. Details `ROGUELITE_REWORK.md` §8 and the site half of
milestone R2 ("The world is worth exploring"). Nothing here is implemented.

**Scope:** lootable site types, the interaction and choice model, loot tables, the first relic
set, data schemas, and code touchpoints. **Out of scope, specced separately:** carry capacity
tuning, the deposit-at-lair step, the escort, and Raven pings — this document *feeds* loot into
`Necromancer.carried` and stops at the villain's hands. The banking rule (`ROGUELITE_REWORK.md`
§1) governs everything downstream.

**Companion documents:** `ROGUELITE_REWORK.md` (§5 sortie loop, §7 reputation, §8 loot),
`WORLD_MAP_PLAN.md` (§6 danger bands, §7 content density, §9 danger-from-choices),
`CLAUDE.md` (conventions this spec is written against).

> **Amendment, 2026-08-06 — terrain and signposting.** `TERRAIN_SPEC.md` adds ruins, marsh, water
> and cliff terrain plus a generated road network, with three consequences for this document:
>
> 1. **Sites telegraph through terrain, not through paths.** A `ruin_pocket`, `crypt` or
>    `cursed_battlefield` sits on a patch of ruins or charred tiles, so it reads as *something is
>    here* from a distance — satisfying §3's telegraphing requirement without a line leading to it.
> 2. **`signposted: bool` joins the `lootable` block** (§8). Band 1–2 sites may set it and get a
>    worn dirt track branching off the human road network; **Band 3–4 sites may not**, and the
>    generator hard-errors if they do. The crypt, the outlaw cave and the cursed battlefield are
>    found, not followed (`TERRAIN_SPEC.md` §7).
> 3. **§2's density figure is 10–15 active, not 12–20.** `ROGUELITE_REWORK.md` §4 adopted map doc
>    §12's active-per-run number; §7's 12–20 is the *pool* a run draws from. The per-run counts in
>    §2's table cap against 10–15.

> **Amendment, 2026-08-06 (second) — the wolf den.** `TERRAIN_SPEC.md`'s forest amendment (§6b
> there) gives the map dense forest with interior clearings reachable only through corridors —
> the first genuinely isolated locations. This document gains the site built for them: the
> **wolf den** (§2, §3b) — the first *clearable* site, a pack of wolf guardians with a den behind
> them, and the answer to where the settlement's dusk wolf has been coming from all along.
> Clearing every den quiets the dusk raids for the run (§3b), which makes the den the first site
> the player visits for a *systemic* reward rather than a haul. Den yields are in §5; the notice/
> deed split and the `guardian` schema growing a `count` are in §6/§8; the dusk-gate touchpoint
> is in §9.

> **Amendment, 2026-08-29 — spec review (designer). Five rulings: caches, arms, graveyards,
> witnesses, haulage.** Where this block disagrees with the body below, this block governs;
> prompt R2a builds this version.
>
> **1. Exclusivity, tightened at the caches.** §1.1's law is reaffirmed and applied to the two
> sites that leaned on mundane yield: for `small_cache` and `abandoned_camp`, the gold and
> trinket chance IS the point; wood/stone/food are demoted to garnish (low weight, small
> amounts) in their §5 tables. A cache whose best outcome is wood is a bug by the first law.
>
> **2. Arms enter as field loot.** New loot kind `arms` — weapons and armour pieces, generic
> units for now. Field-only, no worker source, and deliberately a dead-end resource until
> `COMBAT_SPEC.md` §9's gear v1 lands (the gold precedent from §5: carrying a dead-end resource
> for one milestone is acceptable; shipping an outlaw cave with no weapons in it is not).
> Found arms are the field-exclusive counterpart to the Workshop's bought gear — the cave and
> the battlefield are where you get it without paying. Table entries: `outlaw_cave` (its hoard
> gains guaranteed arms), `cursed_battlefield` (arms alongside the mass bones),
> `abandoned_camp` (small chance). Human sites only — the wolf den keeps its cloak and carries
> no arms. Crafting materials stay expressed through the existing mundane kinds — wood, stone,
> bones are what the settlement already builds with; a dedicated crafting-material kind waits
> for a crafting spec (`GAME_IMPROVEMENT_REVIEW.md` §13 defers the system).
>
> **3. The cemetery becomes three graveyards.** The single Band-3 `cemetery` row in §2 is
> replaced by a tier of three, distance and watchfulness rising together:
>
> | Type id | Name | Band | Per run | Watcher | Notice |
> |---|---|---|---|---|---|
> | `derelict_graveyard` | A Derelict Graveyard | 2 | 1–2 | none — forgotten | **none, ever** |
> | `village_graveyard` | The Village Graveyard | 2–3 | 1 (village outskirt) | a visiting peasant, sometimes | standard per grave |
> | `church_cemetery` | The Church Cemetery | 3 | 1 (fixed, church grounds) | the priest, resident | escalating per grave (§2's old cemetery rule) |
>
> All three offer the §4 choice sheet per grave. Loot quality rises with the watcher: derelict
> uses Band-2 ratios per grave, village sits between, church keeps §5's Band-3 row (best grave
> loot in the run). Placement follows the telegraph rule (§3): derelict in the wilds off a dead
> dirt track, village graveyard at the village outskirt, church cemetery inside the grounds.
> The derelict graveyard is the school — where a player learns grave-robbing before anyone is
> watching. Twelve types now; the 10–15 active budget holds (pool maxima already deliberately
> sum past it). §2's Band-3 note (notice vs deeds split) applies to the church cemetery.
>
> **4. Witnesses — designed now, built in R3.** The principle behind the tier above, recorded
> so R3 inherits it: **threat from a witnessed crime lands only when the witness reaches a
> guard or guard building.** A human who sees looting, grave-robbing, or violence becomes a
> report-in-transit — they path to the watchtower/guard, and threat is added on ARRIVAL, not
> on sight. The player can prevent the report (intercept, mislead, or kill — killing the
> witness is a Cruelty deed with its own notice risk if itself witnessed). Unwitnessed crimes
> generate no threat at all — which is what retroactively makes the derelict graveyard free
> and the church cemetery expensive. In R2 notice stays abstract (a per-site roll standing in
> for "was someone there"), because civilians don't wander and the guard buildings are inert
> until Era III; R3's patrol-escalation work replaces the abstract roll with this loop. This
> is the bridge §2's Band-3 note gestures at, made diegetic.
>
> **5. Haulage — designed now, scheduled later.** Three designer ideas recorded with homes, so
> nothing lands in R2 (SORTIE_SPEC §1.3's one-number rule and its loaded-return-time assertion
> stand for the R2 playtests): **backpacks** are gear — a carry-raising slot item under
> `COMBAT_SPEC.md` §9's v1+, scarce by design so the escort economy (SORTIE_SPEC §1.4)
> survives; **load slowing the carrier** is the designated fallback lever at the R2 exit
> playtest — if capacity-vs-yield tuning cannot make "one more grave or turn back?" real, it is
> the next thing tried, adopted by striking SORTIE_SPEC §10's loaded-return assertion openly;
> the **hand cart** is R3+ material — a huge haul that only rolls on roads, slow, visible, and
> routed past exactly the places where witnesses and patrols live, so it gets better once the
> witness loop exists.

---

## 1. Design goals

1. **Exclusivity, restated as the first law.** Nothing a lootable site yields may ever become
   worker-gatherable at home. Dark Essence, gold, relics, and deeds exist *only* out there. Bones
   and wood may appear in site loot as garnish, but a site whose main yield duplicates the home
   economy is a design bug — the player stays home and the game collapses back into a colony sim.
2. **Every site is a decision, not a pickup.** The minimum interaction is one choice with a
   trade-off (time, noise, axis, risk). If a site can be fully resolved by walking onto it, it
   belongs in `ResourceField`, not here.
3. **Danger is telegraphed and chosen.** A site's inspection payload says what class of trouble it
   carries *before* the player commits (map doc §9). Surprises live in the ~10% self-found
   discovery budget (`ROGUELITE_REWORK.md` §6) — never in a site the panel called safe.
4. **Distance buys quality.** Band 1 teaches, Band 2 sustains, Band 3 tempts, Band 4 dares. The
   loot tables below are tiered so this is enforced by data, not by vibes.
5. **Looting takes time, on purpose.** Standing still at a site while the sun moves is the whole
   push-your-luck engine. Dusk, the wolf, and a full pack turn "one more grave" into the game.

---

## 2. Site type catalog

The binding density budget is the one the rework adopted (`ROGUELITE_REWORK.md` §4: **~10–15
active meaningful locations per run**) — not map doc §7's raw possible counts (12–20 / 3–5),
which this draft originally cited. The ranges below are per-type *pool* bounds the R4 shuffle
draws from (`pool` + `active_count`, §8), not additive targets — their maxima deliberately sum
past the budget (~22) so shuffles differ, but `active_count` totals, and R2's fixed hand-authored
layout, must land inside 10–15 active lootable sites.

| Type id | Name | Band | Per run | Yields | Risk profile |
|---|---|---|---|---|---|
| `fresh_grave` | A Fresh Grave | 1 | 2–3 | bones, trinket chance | None. The tutorial loot. |
| `small_cache` | A Hidden Cache | 1 | 1–2 | wood/stone/food, gold chance | None. Raven-ping fodder. |
| `wayside_shrine` | A Wayside Shrine | 2 | 1–2 | gold offerings, Dark Essence | Desecration is *loud* (threat). |
| `abandoned_camp` | An Abandoned Camp | 2 | 2–3 | mixed mundane, relic chance | Sometimes not abandoned (occupant roll). |
| `valuable_grave` | A Marked Grave | 2 | 2–4 | bones, gold, relic chance | The four-way choice (§4). Noticed. |
| `ruin_pocket` | A Collapsed Ruin | 2 | 1–2 | stone, Dark Essence, relic chance | Multi-charge; each pull rolls a guardian. |
| `wolf_den` | A Wolf Den | 2 | 1–2 | bones, food, wolfhide relic chance | **Clearable** (§3b): 2–3 wolf guardians; while any den stands, dusk raids continue. |
| `cemetery` | The Cemetery | 3 | 1 (fixed) | best grave loot in the run, repeatable | Consecrated, patrol-adjacent, escalating notice per grave. |
| `crypt` | An Ancient Crypt | 4 | 0–1 | guaranteed relic, heavy Dark Essence | Guardian fight, no exceptions. |
| `outlaw_cave` | An Outlaw Cave | 4 | 0–1 | gold hoard, weapons relic chance | Occupied by definition; fight or leave. |
| `cursed_battlefield` | A Cursed Battlefield | 4 | 0–1 | mass bones, Dark Essence, relic chance | Multi-charge with rising guardian odds per pull. |

Existing placed sites map cleanly: the three Band-2 landmarks already in `world_sites.json`
become `wayside_shrine` (Broken Shrine), `abandoned_camp` (the camp), and `ruin_pocket`
(Standing Stones); the Cemetery becomes the one Band-3 lootable. The manor, church, houses, and
watchtower stay inert in R2 — they are Era-III business.

**Band 3 note:** in R2 the cemetery is the *only* lootable inside faction influence. Its risk is
not a guardian but *notice*: each grave robbed there adds escalating threat, so the third grave in
one sortie is a genuinely reckless act. This is the bridge to R3's patrol escalation, and the two
halves live in different places on purpose (reputation-ownership decision, 2026-08-06): the
escalation half lands in `GameState.add_threat()` — threat is world state and stays in the
autoload — while the reputation-facing half is recorded on the villain's deeds ledger (§6), which
is what R3 reads as notoriety. Nothing reputation-shaped is ever reread out of `GameState`.

---

## 3. Interaction model

**Reach.** The Necromancer interacts with a site when within `interact_radius` (default: the
site's `pick_radius`, i.e. roughly touching it). No remote looting; his physical presence is the
point. The escort never initiates site interactions — sites answer to the villain who walked up,
passed as a parameter, never looked up globally.

**Surface.** Clicking a site in reach shows its actions in the InspectionPanel via the existing
`InspectorActions` pattern (Command Undead already works this way — no new UI machinery). A site
out of reach inspects as today: description, details, no actions.

**Choices.** An action either resolves immediately (single-outcome sites) or opens an
`EventPanelUI`-style choice sheet (the grave model, §4). Choice sheets are data-driven with the
same shape as `events.json` choices — label + effects — extended with the effect vocabulary in §7.
One shared renderer, two data sources.

**Time.** Looting is a channel: a delta-accumulated timer (`Engine.time_scale`-safe, per
CLAUDE.md — never wall-clock) with a progress readout in the panel. Moving cancels and refunds
nothing. Defaults: 4s for a grave, 8s for a shrine/cache, 12s per crypt/battlefield pull —
tunables, all. The channel is what makes dusk and the guardian roll matter.

**Charges.** Sites are one-shot (`charges: 1`) or multi-pull (`charges: N`, the cemetery,
battlefield, and ruin). A spent site swaps to its `looted_sprite`, keeps its inspection payload
(with a past-tense description), and stops offering actions. Spent is spent for the run.

**Occupants and guardians.** `abandoned_camp` rolls occupancy at *activation* (run start, hidden
until approached — this is the honest-telegraph exception budget). Band-4 guardians are declared
in the site's subtitle and details: the crypt *says* something is inside. Guardians use the
existing Combatant duck-type and `CombatSystem` policy; a dead guardian's site unlocks its actions.
Guardian corpses follow the wolf precedent (`wolf_killed` → gatherable remains).

---

## 3b. The wolf den — the first clearable site

The den is deliberately unlike every other site in the catalog: its value is only partly in the
loot. It is **where the dusk wolf comes from**, and clearing it is how the player buys quiet
nights.

**Where it sits.** In a forest clearing (`TERRAIN_SPEC.md` §6b) — behind trees, at the end of a
corridor, never signposted. The den *telegraphs* the way every site should: gnawed bones on the
approach (a `B` bone-strewn patch at the corridor mouth), and the inspection payload names the
risk class before the player commits, per §1.3. At least one den sits in the mass east of the
lair valley — the treeline `CombatSystem.gd`'s spawn comment has always pointed at, made real.

**The pack.** 2–3 wolf guardians (`guardian: {"kind": "wolf", "count": N}`, §8). They are
`SiteGuardian`s wearing the wolf's stats and art (Str 5 / End 5 — 18 hp — and the flee-below-5 rule) — the
existing `Wolf.gd` numbers, not a new creature — parked on a small prowl radius around the den,
engaging anything that enters it. They fight through the ordinary `CombatSystem` policy;
escort-vs-pack works the day `hostiles()` exists (`ESCORT_SPEC.md` §4's refactor). Pack wolves
that flee (below 5 hp) **leave the run**, not the fight-then-return loop — a den's defenders are
finite, which is what makes attrition across two visits a legitimate tactic.

**Cleared.** When the last pack wolf is dead or fled, the site unlocks its one loot action
(charges 1): the den itself — bones, meat gone rank but food nonetheless, and the best
`wolfhide_cloak` odds in the game (§5). Each killed wolf also leaves the standard gatherable
carcass (`wolf_killed` precedent — but at the *site's* location, a long carry from home, which is
the escort's problem to enjoy). Clearing emits a **Power deed** (§6: "battles won, monsters
slain") and modest notice — wolves have no lord, but a silenced forest gets talked about.

**The dusk gate.** Today `CombatSystem._on_dusk` rolls a flat 55% forever. It becomes:
**while at least one uncleared den exists, the roll stands (first-dusk guarantee included); when
the last den is cleared, dusk raids on the settlement stop for the run.** The fiction and the
mechanics finally agree about where wolves live. Two guards on the design: the spawn *entry
point* stays the settlement-relative one (a wolf that had to walk 60 cells from its den would
arrive at midnight or never — the den explains the wolf, it does not path it), and whether a
small floor chance (~10%) should survive full clearance is a tunable (§10) — default no, because
"I earned the quiet" is the stronger reward.

**What the den is not.** Not repeatable (cleared is cleared, the spent-site rule), not a spawner
that repopulates, not a Band-4 fight — it is the *teaching* fight for guardians, tuned so a
villain with two escorts wins it and a villain alone (one caster vs a pack) is making a real
gamble. Harder dens — a den with something worse than wolves in it — are pool material for R4's
shuffle, same schema, bigger `count`, different `kind`.

---

## 4. The grave-robbing choice model

Canonical four (from `ROGUELITE_REWORK.md` §7), presented as one choice sheet on `fresh_grave`,
`valuable_grave`, and each cemetery pull. Axis effects are **recorded as deeds** (§6) — the
five-axis system itself is R3; R2 writes the ledger it will read.

| Choice | Immediate effect | Deed axes | Notice (threat) |
|---|---|---|---|
| **Raise the corpse** | +1 escort-eligible skeleton at the site (caps at carry party rules; dormant until escort lands, then retroactively live) | Forbidden Knowledge + | + |
| **Steal the valuables** | Roll the grave's loot table into `carried` | Wealth + | + |
| **Return the belongings** | No loot; consumes the grave's valuables | Mercy + | none |
| **Destroy the evidence** | Available *after* raise/steal, replaces the looted-sprite swap with an undisturbed one | Cruelty + | removes this grave's notice |

Rules that make it a real dilemma: raise-then-steal is allowed (the corpse and the valuables are
separate charges) but doubles notice; return-the-belongings is only offered while the valuables
are intact — mercy forecloses profit, permanently; destroy-the-evidence costs a second channel
and only conceals *this* grave. The cemetery offers the same sheet per grave with better tables
and worse notice.

---

## 5. Loot tables and the two new resources

**Gold enters the game here.** `ROGUELITE_REWORK.md` §8 lists it as mundane loot; it does not yet
exist in `GameState`. R2 adds it as the sixth resource — field-only like Dark Essence, no worker
source, no building cost uses it yet. Its sinks arrive with R3 (the Wealth axis reads hoarded
gold) and R5 (stash value). Carrying a dead-end resource for one milestone is acceptable; the
alternative — shipping loot without the loot — is not. Dark Essence simultaneously completes its
move to field-loot-only: its current in-run sources (harvest bounties) are re-pointed or retired
in the same pass, per §8's "exclusively found in the world."

**Table shape.** A loot table is named, lives in `data/loot_tables.json`, and is a list of
weighted entries rolled `rolls` times without replacement of the `unique` entries:

```json
{
  "valuable_grave": {
    "rolls": 2,
    "entries": [
      {"kind": "bones", "min": 2, "max": 4, "weight": 6},
      {"kind": "gold", "min": 2, "max": 5, "weight": 5},
      {"kind": "dark_essence", "min": 1, "max": 2, "weight": 3},
      {"relic_tier": "uncommon", "weight": 1, "unique": true}
    ]
  }
}
```

**Tier targets** (per resolved site, before tuning — the point is the *ratios*):

| Band | Mundane units | Dark Essence | Gold | Relic odds |
|---|---|---|---|---|
| 1 | 2–4 | 0–1 | 0–2 | trinket-tier only, ~10% |
| 2 | 3–6 | 1–2 | 2–5 | ~15% uncommon |
| 3 (cemetery) | 4–6 per grave | 1–3 | 3–6 | ~25% uncommon, ~5% rare |
| 4 | 6–10 | 3–5 | 6–12 | crypt: guaranteed rare+; others ~40% |

One authored exception to the band ratios: the `wolf_den` table carries the game's best
`wolfhide_cloak` odds (~20% against the band's ~15%, `unique` as ever) — the cloak comes from
somewhere, and a player who wants it can go pick the fight that drops it. That is the model for
thematic drops generally: bias the *site's* table, never invent a bespoke drop system.

Everything rolls through `Necromancer.add_carried()` and respects its return value: what doesn't
fit **stays at the site as a remainder charge**, not on the ground and not vaporized — walking
home to empty his hands and coming back is a legitimate (and time-taxed) play. With carry capacity
= Endurance = 6, one Band-2 site roughly fills him; that pressure is deliberate and the escort's
carry-hauling (out of scope) is the relief valve. Flagged as a tunable pair in §10.

---

## 6. Deeds: the ledger R3 will read

Every choice with axis consequences emits `EventBus.deed_committed(villain, deed_id,
axes: Dictionary)` — e.g. `{"wealth": 1, "cruelty": 0}` — and appends to a per-villain
`deeds: Array` on the `Necromancer` object (per-villain state, never in an autoload). R2 consumes
none of it beyond the TravelLog line. R3 replays or subscribes; either works because the ledger is
ordered and timestamped in game-days. This costs a signal and an array now and saves R3 from
archaeology later.

---

## 7. Relics

**Rarity tiers:** `trinket`, `uncommon`, `rare`, `legendary`. Trinkets are pure treasure —
no effect, gold value only, they exist so Band 1 can pay off without power. Legendary does not
drop from loot tables in R2 (reserved for feats: the crypt guardian, the manor, R4+).

**Carry rule:** a relic occupies **1 carry slot** in `carry_capacity()` like any resource unit,
held in `Necromancer.relics_carried: Array` (identity matters; the `carried` Dictionary is for
fungibles). A relic in hand grants nothing — **effects activate on deposit at the lair** (banked =
real, the §1 banking rule applied to power, and it keeps "drop it and run" a live choice on the
return leg).

**Effect vocabulary R2 implements:** flat attribute delta (`{"attribute": "intelligence", "delta": 1}` — any of COMBAT_SPEC §2.1's nine, so future relics need data only), move-speed multiplier, carry-capacity
delta, heal-at-dawn, fog-reveal-radius delta. **Declared but dormant** (data present, no-op until
their system lands, marked `"dormant": true` so the panel can say so honestly): escort size,
XP multipliers (R5), axis-gain multipliers (R3). Dormant effects are how relics avoid blocking on
other systems without shipping lies.

**The first set** (`data/relics.json`):

| Id | Name | Tier | Effect |
|---|---|---|---|
| `tarnished_locket` | A Tarnished Locket | trinket | None. Somebody's whole world, worth 4 gold. |
| `grave_coins` | Coins for the Ferryman | trinket | None. 2 gold, taken from under a tongue. |
| `sextons_ring` | The Sexton's Ring | uncommon | Grave/cemetery channels 25% faster. |
| `wolfhide_cloak` | A Wolf-Hide Cloak | uncommon | +10% move speed off-road. |
| `pallbearers_gloves` | The Pallbearer's Gloves | uncommon | +2 carry capacity. |
| `chipped_censer` | A Chipped Censer | uncommon | Heal 2 hp at dawn. |
| `noble_seal` | A Noble's Seal | rare | Dormant: +Wealth-axis gains (R3). Worth 10 gold meanwhile. |
| `sermon_of_ash` | The Sermon of Ash | rare | +1 Intelligence — a heretical sermon makes a better caster. |
| `barrow_lantern` | A Barrow Lantern | rare | +2 cells fog reveal radius. |
| `ledger_of_names` | The Ledger of Names | rare | Dormant: +1 escort cap (escort pass). |

Ten relics, six live effects, two honest trinkets, two dormant promises. Effects are additive and
unstacked in R2 (a second `pallbearers_gloves` cannot drop: relics are `unique` per run).

---

## 8. Data schemas

**`data/world_sites.json`** — each lootable entry gains one optional block; inert sites are
untouched and the loader's behavior for them is unchanged:

```json
{
  "id": "broken_shrine",
  "...": "existing fields unchanged",
  "lootable": {
    "type": "wayside_shrine",
    "band": 2,
    "charges": 1,
    "channel_seconds": 8.0,
    "loot_table": "wayside_shrine",
    "choices": "shrine_choices",
    "looted_sprite": "res://assets/placeholder/kenney/shrine_toppled.png",
    "guardian": null,
    "notice": {"threat": 2}
  }
}
```

**The `guardian` block** is `null`, or `{"kind": String, "count": int}` — `{"kind": "wolf",
"count": 3}` for a den, `{"kind": "crypt_sentinel", "count": 1}` for the crypt. `kind` selects
stats/art from a small guardian table (same file, top level); `count` is how many
`SiteGuardian`s the site parks. A bare string in older drafts reads as `{kind, count: 1}` at
load, so nothing already written reopens.

**`data/loot_tables.json`** — §5's shape. **`data/relics.json`** — id, name, tier, description,
gold value, effects array, `dormant` flags. **`data/site_choices.json`** — choice sheets in the
`events.json` grammar plus the new effect keys (`loot_table`, `deed`, `notice`, `raise_corpse`,
`conceal`). New *values* are JSON edits; new effect *keys* are code, in whichever system owns the
key — the CLAUDE.md content rule, unchanged.

Pool/activation fields (`pool`, `active_count`) are **specified now, honored in R4** — R2 authors
concrete placed sites only, but the schema won't need reopening for the shuffle.

---

## 9. Code touchpoints

| Where | Change |
|---|---|
| `WorldSite.gd` | Gains loot state (charges left, chosen flags) *on the node*, following the `ResourceNode` precedent — its position and appearance are its gameplay content. Documented split trigger, same wording as the Laborer one: the moment any off-map system needs site state, it splits into data + view. Channel timing is a delta accumulator on it. |
| `WorldSites.gd` | Loads the `lootable` block; answers `lootable_in_reach(villain)`; owns guardian spawn/despawn per site. Nothing reaches into `sites` directly, as now. |
| `Necromancer.gd` | `relics_carried: Array`, `deeds: Array`, relic-effect readers folded into `carry_capacity()` / `move_speed_px()` / `max_hp()`-adjacent paths on deposit-activation. `add_carried()` already does the fungible half. |
| `GameState.gd` | `gold` as the sixth resource (all four resource methods). Nothing else — loot never touches GameState until the deposit step, which is the other spec's business. |
| `EventBus.gd` | `site_looted(villain, site, loot: Dictionary)`, `site_choice_resolved(villain, site, choice_id: String)`, `relic_found(villain, relic_id: String)`, `deed_committed(villain, deed_id: String, axes: Dictionary)`, `site_guardian_engaged(villain, site)`. All carry the villain object — never assume one of him. Mind signal arity on handlers (CLAUDE.md gotcha). |
| `Main.gd` | Wires site actions into `InspectorActions` and the choice sheet into the `EventPanelUI` renderer. Input-mode arbitration order unchanged. |
| `InspectionPanel` | Renders channel progress and a "Looted" state row. No new panel. |
| New: `scripts/world/SiteGuardian.gd` | Combatant-contract fighter parked at a site; `Roaming.gd` + wolf patterns reused. Not a Laborer, not commandable (living guardians) — undead guardians *are* commandable via alignment, which is a feature, not a bug: Command Undead flipping a crypt's dead sentinel is exactly the fantasy. Takes `{kind, count}` from the site's `guardian` block; the wolf kind wears `Wolf.gd`'s stats and sprite so a den wolf and a dusk wolf are visibly the same animal. |
| `CombatSystem.gd` | **The dusk gate** (§3b): `_on_dusk` asks `WorldSites.any_den_uncleared()` before rolling; when it answers no, dusk raids stop for the run. The spawn entry point stays settlement-relative — do not path wolves from dens. `MAX_WOLVES` and the dawn-departure rule are unchanged; den pack wolves are `SiteGuardian`s and never enter `wolves`. |
| New art | Looted-state sprites per type. Placeholders land in `assets/placeholder/`, named per SPRITE_SPEC, deleted in the commits that replace them. World sites keep canvas-width sizing (the documented `WorldSite` exception) until the joint re-tune pass. |

---

## 10. Verification and tunables

**Harnesses** (repo rule: tools re-derive every number): `tools/verify_loot_tables.tscn` —
loads every table, asserts ids resolve, weights are positive, tier ratios in §5's bands hold in
10k-roll simulation, and every relic referenced exists exactly once; run headless as a scene (not
`-s`, per the autoload gotcha). Den assertions ride the same harness: with an uncleared den, 1,000
simulated dusks spawn at roughly the 55% rate (first guaranteed); clear the last den and 1,000
dusks spawn **zero** wolves; killing or routing the full pack unlocks the den's loot action in the
same frame. Extend `tools/check_sprite_scales.tscn` for looted-state sprites.
Headless boot after every schema change. A seeded `capture_settlement`-style screenshot of the
cemetery pre/post looting for the sprite-swap eyeball.

**Tunables** (§15-style open list): channel durations; carry capacity (6) vs per-site yield —
the pair that decides sortie length; cemetery notice escalation curve; occupancy odds for the
camp; guardian statlines per band; whether destroy-the-evidence should also cost bones or time enough
to hurt; relic drop rates per band; gold values pre-sink; pack size per den (2–3) and whether a
fled pack wolf should count toward "cleared" (currently yes); the post-clearance dusk floor
chance (default 0 — the quiet is the reward); den notice size.

**Exit criterion for this slice** (feeds R2's overall exit): a sortie that visits one Band-1 and
one Band-2 site presents at least three real decisions (route, choice sheet, one-more-pull), fills
the carry, and produces a TravelLog line per §6 — before the deposit step even exists.
