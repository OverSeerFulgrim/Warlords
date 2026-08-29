# The world becomes worth walking into — lootable sites, dens, and the dusk gate (R2a)

Prompt **R2a**, against `LOOT_SITES_SPEC.md` (body plus the binding 2026-08-29 amendment block),
`SORTIE_SPEC.md` §4 for remainders, and `ROGUELITE_REWORK.md` §8/§13. P2 was done; this is the
first R2 slice that puts something at the end of the roads P2 built.

The R1 playtest's feel-question answer was *"There was no purpose in leaving currently as the game
is."* This pass is the purpose.

---

## 0. The minimap toggle, first

The P2 human check could not run its second question — *Throne to village by ground alone* —
because there was no way to turn the minimap off; it was tested with the command bar minimised
instead. **M** now toggles the whole minimap column (map and legend together — a legend for an
invisible map is worse than either), default on, one TravelLog line per change and no alert,
because this is the player telling the game something rather than the reverse. The hint under the
minimap says `(M hides)`, which is how anyone finds out.

That check and R2's own exit walk can now both be run properly.

---

## 1. What shipped

**Fifteen active lootable sites**, thirteen types, every band represented:

| Band | Sites |
|---|---|
| 1 | two fresh graves, a hidden cache |
| 2 | the Broken Shrine, the Abandoned Camp, the Standing Stones (a multi-charge ruin pocket), a marked grave, a derelict graveyard, two wolf dens |
| 3 | the village graveyard, the church cemetery |
| 4 | the Old Crypt, the Outlaw Cave, the Cursed Battlefield |

Fifteen is the **top** of `ROGUELITE_REWORK.md` §4's 10–15 active budget, and deliberately so:
every type is placed once so the R2 playtest meets the whole catalog. §2's per-type "per run"
column is the *pool* the R4 shuffle draws from — its maxima sum to ~25 — and `pool` /
`active_count` are authored on every site now so the shuffle will not have to reopen the schema.

The three existing Band-2 landmarks mapped over cleanly, as the spec predicted: the Broken Shrine
became `wayside_shrine`, the camp `abandoned_camp`, the Standing Stones `ruin_pocket`. The
`cemetery` entry kept its id (the road generator and `verify_terrain` both reference it) and became
the `church_cemetery` type.

**A note on the type count.** The amendment says "Twelve types now". Counting the §2 table as
printed — eleven rows including the wolf den the second amendment added — replacing one `cemetery`
with three graveyards gives **thirteen**, which is what is built. The amendment most likely counted
from the pre-den table of ten. Nothing turns on it; flagged so nobody re-derives it later and
thinks a type is missing.

### The interaction model

Reach is touching distance (`interact_radius`, defaulting to the pick radius) — no remote looting,
and a site out of reach still *inspects*, it just offers no buttons. That is the reach rule as a
visible one: the player can read the crypt from a distance and see exactly why the buttons are not
there.

Looting is a **channel** — a delta accumulator on the site, so it inherits `Engine.time_scale` like
every other clock. 4s a grave, 8s a shrine or cache, 12s a crypt or battlefield pull. Moving
cancels it and refunds nothing.

His own idle pacing does **not** cancel it. `Necromancer.is_channelling` exists for exactly one
reason: `step()`'s idle branch would otherwise wander him off a grave eight seconds into a
twelve-second pull, and the bug would have read as "channelling is flaky".

### The four-way grave sheet

`data/site_choices.json`, in the `events.json` grammar, rendered by **the same `EventPanelUI`** —
one renderer, two data sources. What differs is only who resolves the press: a `_resolver` Callable,
cleared whenever an ordinary event opens so the two can never cross. A site sheet also gets a
*Leave it* row; an event does not, because walking away from an open grave is legitimate and
walking away from an event is not.

The gating is the dilemma, and it lives on the site rather than in the UI:

- **Raise-then-steal is allowed** — the corpse and the valuables are separate takings from one
  grave — and doubles the notice.
- **Return the belongings** is only offered while the valuables are intact, and finishes the grave
  on the spot. Mercy forecloses profit permanently, which is now true mechanically rather than by
  convention.
- **Destroy the evidence** only appears after something has been taken, costs a second (longer)
  channel, and replaces the looted-sprite swap with the undisturbed one — so a site whose every
  disturbed grave was concealed never swaps at all.

A raised corpse is **recorded, not spawned** (`Necromancer.raised_dead`): §4 says dormant until the
escort lands, then retroactively live, and spawning a skeleton with no order model to stand under
is a unit R2d would have had to unpick.

> **Superseded 2026-08-30** by the playtest fixes at the foot of this file. Ledger-only was per
> spec and completely invisible: the player raised a corpse and the world showed nothing. The entry
> is still the data; a `RaisedDead` node now stands over it. The dormancy is about orders, not
> about existence.

### Loot, gold, arms, relics

`data/loot_tables.json` holds thirteen tables in §5's shape, and **`LootCatalog` owns the roll** —
one implementation, used by the game and by the harness alike. Relic entries name a *tier*, so
`relics.json` can grow without a table edit; the run's already-drawn set is passed in from the
villain, because the catalog is an autoload and must not accumulate run state.

- **Gold** is `GameState`'s sixth resource, in all four resource methods and on the HUD strip.
  Field-only, no worker source, no building cost uses it; its sinks arrive with R3 and R5.
- **Arms** (amendment ruling 2) is a loot *kind* but deliberately **not** a `GameState` resource:
  §9 says GameState gains gold and "nothing else", and arms has no home in the settlement economy
  until `COMBAT_SPEC.md` §9's gear v1. It lives in `Necromancer.carried` and is a dead end on
  purpose. Guaranteed in the outlaw cave, common on the battlefield, a small chance at the camp —
  human sites only, and the harness asserts the negative half too.
- **Ten relics**, six live effects, two honest trinkets, two dormant promises. A relic occupies one
  carry slot, and **in his hands it does nothing**: effects read from `relics_banked`, which R2c's
  deposit will fill. Every reader is written and asserted now so that pass has nothing to invent.

Relic attribute deltas land in `Necromancer.attribute()` rather than on the nine vars, which is what
keeps "computed at use time, never stored" true through the Sermon of Ash: `max_hp()`,
`combat_profile()` and `carry_capacity()` all read through it, so a +1 Intelligence relic reaches
his casting with no second code path.

### Remainder charges

From `SORTIE_SPEC.md` §4, implemented here because the state lives on the site. What does not fit
**stays at the site**: it keeps its actions, keeps its unlooted sprite, is not "spent", and its
inspection payload says what is still there. Coming back with empty hands to collect it is free (no
channel — picking your own haul back up is not a second robbery) and the time is the cost.

**No ground piles, ever.** A dropped-loot entity on a 144×144 map is a second inventory system, a
second set of sprites, and an R5 save-format problem. The site is already a container.

### Deeds and notice — the split, both halves

`EventBus.deed_committed(villain, deed_id, axes)` and a per-villain `deeds: Array`, ordered and
stamped in game-days. R2 consumes none of it beyond a log line; that is the point, and it costs an
array now instead of archaeology in R3.

Notice goes to `GameState.add_threat()` and nowhere near the villain. The derelict graveyard is
authored with `threat: 0` and generates none, ever — which is what retroactively makes the church
cemetery, whose notice escalates per grave, expensive. The harness asserts both directions,
including that `GameState` has no `deeds`.

**Witnesses (amendment ruling 4) were not built.** R2's notice stays an abstract per-site roll, as
the ruling says; R3's patrol-escalation work replaces it with the report-in-transit loop. Haulage
(ruling 5) likewise: backpacks are gear v1+, the hand cart is R3+, and load-slows-the-carrier is
the designated fallback lever at the R2 exit playtest, not something to pre-empt.

---

## 2. The wolf dens, and the dusk gate

Two dens, in the two interior forest clearings P2 carved — one in the mass south-east of the lair
valley, which is the treeline `CombatSystem`'s spawn comment has always pointed at. Unsignposted,
found through a corridor, with a bone-strewn patch the generator paints inside the clearing.

`SiteGuardian` is a new Combatant-contract fighter parked at a site. For `kind: "wolf"` it wears
**`Wolf.gd`'s own race row, constants and sprite** — 18 hp, Str 5, flee below 5, the one
width-scaled sprite in the project — so a den wolf and a dusk wolf are demonstrably the same
animal. It is not a `Wolf` subclass: `Wolf` owns an exit point, a hunt delay, a fed flag, a dawn
departure and a prey search over the labour pool, and inheriting four behaviours to switch off is
how the next guardian kind ends up being a wolf with the wolf parts commented out.

A pack wolf that drops below its flee threshold **leaves the run** rather than the settlement
wolf's fight-then-return loop. A den's defenders are finite, which is what makes attrition across
two visits a legitimate tactic.

**The dusk gate.** `CombatSystem._on_dusk` now asks `WorldSites.any_den_uncleared()` first — before
the first-dusk guarantee, deliberately, because a player who spent day one clearing the forest has
earned a quiet first night. Both of §3b's guards are kept and both are asserted: the spawn entry
point stays settlement-relative (a wolf pathing 60 cells from its den would arrive at midnight or
never — the den *explains* the wolf, it does not path it), and pack wolves are `SiteGuardian`s that
never enter `wolves`.

Clearing a den emits a Power deed and modest notice, unlocks its one loot action in the same frame,
and leaves each killed wolf's standard carcass **at the site** — a long carry from home, which is
the escort's problem to enjoy.

### The fight loop stopped being wolf-only

`CombatSystem`'s engagement loop was typed `Wolf` throughout. It is now attacker-agnostic: one
`_advance_engagement` runs a dusk wolf, a pack wolf and a crypt sentinel alike, because the
consequence rules are policy and policy is what that file is. Only two things still dispatch on
kind, and both are bookkeeping rather than judgement — what a corpse leaves behind
(`_leaves_a_carcass`) and who owns the despawn (`_remove_attacker`).

Two things fell out of that:

- **Not every defender is a Laborer.** The villain has no `in_combat` and no trip to abandon, so
  the two bookkeeping calls moved behind `_enter_combat` / `_leave_combat` property checks.
- **The villain-loses branch had to exist.** `LAIR_AURA_PROTECTS_VILLAIN`'s header said outright
  that there was no branch for it and that it would be "the run ends" when R4 arrived. A guardian
  can now actually kill him, so `_resolve_defeat` has one — and it is deliberately empty of
  consequence: `Necromancer.take_damage()` already emitted `villain_died`, Main logs it, the run
  lifecycle stays R4's and clearing the unbanked haul stays R2c's.

The lair aura is untouched and still `true`. It is a *lair* rule; guardians simply do not consult
it, because a den whose wolves refused to face him would be a den nobody could clear. Making it
positional is still R2b's.

### Per-pull guardians

The ruin pocket and the cursed battlefield are multi-charge, and §2's Risk column gives each its own
danger: the ruin rolls a guardian on every pull, the battlefield's odds rise per pull. Both are
authored as a `guardian_roll` block and spawn through the same path as a den's pack. The roll
happens **after** the loot lands in his hands — the pull pays out and *then* something objects,
which is the sequence that makes "one more pull?" a question rather than a coin flip you lose
before you win anything.

---

## 3. Terrain, now that P2 exists

Sites telegraph through **ground**, not through paths. The generator's dressing step used to carry
two hardcoded ruin centres, and both had already drifted — one sat in the middle of the frozen lake
and painted nothing, the other missed the crypt by three cells. It now reads `world_sites.json` and
dresses by site *type*: ruins under the ruin pocket and the crypt, boulder field around the cave
mouth, charred ground and bone on the battlefield, gnawed bone inside a den's clearing.

Only **ordinary ground** is ever overpainted — never blocking terrain, water, a road or a wood.
That is what keeps it a dressing step rather than a second terrain generator: the battlefield at the
foot of the northern range chars the walkable cells *between* the scree and leaves the range alone,
and a den's bone patch stays inside its clearing because open woodland is not on the list. A site
whose ground refuses every cell warns rather than silently failing to telegraph.

**The road promise** (designer ruling, 2026-08-27): *a road always has something at its end, even
minor loot.* Enforced twice, because the two halves catch different things. The generator
hard-errors if a `signposted: true` site has no `lootable` block, beside the existing Band-3
signposting error. `verify_terrain` then reads the finished map: every dead end in the dirt network
must be a lootable site with a loot action at generation time, or the lair's own gate (§7 rule 3).
Four dead ends, all satisfied.

Signposting is Band 1–2 only, unchanged and still a hard error otherwise. The derelict graveyard is
the one new signposted site — a track to a place nobody has walked in years, which is exactly what
the amendment asks the derelict graveyard to be.

**The Band-4 assertion now has real sites to check.** `verify_terrain` kept its four region cells
*and* gained the placed Band-4 sites by name: until the loot layer landed there was nothing in a
Band-4 rect for a road to lead to, so the check could only guard the ground. It now catches a site
moved onto a road, which the region check never could.

---

## 4. Dark Essence finished moving

`ROGUELITE_REWORK.md` §8 already carries the correction that field-only was a *goal* rather than an
existing convention. It is a fact now, and asserted:

- **`BountyBoard`** paid Dark Essence for harvest bounties. **Re-pointed to bones** — "Harvest
  Corpses" paying bones is what the fiction said all along, so the bounty layer keeps working and
  the exclusivity rule becomes true. `Bounty.reward`'s comment records the change.
- **`MissionSystem` and `EventSystem`** effect handlers: **retired as a source, kept as a sink.** An
  event may still *charge* Dark Essence — spending is the thing it has always lacked, and two
  events do — but neither may print it, and both `push_warning` loudly rather than silently
  ignoring, so a re-added grant in JSON surfaces.
- The content followed: eight positive grants across `events.json` and `missions.json` re-pointed
  to mundane resources that fit the fiction (a robbed trader's goods, a plague's bodies, a ruin's
  stone). The two negative entries are untouched. Neither file has a top-level object to hold a
  `_comment`, so the record is here and in the two loaders.

The harness asserts the rule directly: a mission and an event are both handed
`{"dark_essence": 10}` and `GameState.dark_essence` does not move.

---

## 5. Verification

`tools/verify_loot_tables.tscn` — **468 assertions**, run as a scene. Its centre is the ratio
simulation: every table rolled 10,000 times through the real `LootCatalog.roll()` and compared
against §5's band table. There is deliberately no second, simplified roll in the harness — one that
reimplements what it checks only proves that two authors agreed.

The first version exempted four whole tables as "authored exceptions", which quietly stopped
checking eleven numbers to excuse four: the crypt's guaranteed relic says nothing about its gold,
and the den's cloak says nothing about its bones. Exceptions are **per column** now, and a table may
only appear with the column a spec names in words:

| Table | Exempt | Because |
|---|---|---|
| `small_cache` | all four | amendment ruling 1 — gold-first, mundane demoted to garnish |
| `wolf_den` | relic | §5's one authored exception — best cloak odds in the game |
| `crypt` | relic | §2 — a guaranteed relic, which no percentage describes |
| `outlaw_cave` | relic | ruling 2 — what it guarantees is arms, not a relic |

Each exempt column is then asserted against the rule that authorised it: the cache pays more than
twice as much gold as mundane, the den's cloak beats the Band-2 relic rate and no other table names
it, the crypt pays a rare-or-better on 10,000 rolls out of 10,000, the cave has weapons in it every
time. Nine tables meet their band on all four columns with no exemption at all.

**Eight tables needed tuning** to get there, all of it in `loot_tables.json` and none of it in code.
The measured table is printed on every run, which is what a designer reads when tuning yield against
carry capacity (§10's flagged pair).

Also asserted: the schema and every id join (a table renamed in one file and not the other used to
fail silently at the first loot), relics whole and unique per run, no table able to drop a legendary
(§7 reserves them for feats), the density budget and the graveyard tier, signposting from the data
side, the grave sheet's three gating rules as *transitions*, remainder overflow and collection, the
notice-vs-deeds split, every live relic effect as a before/after change plus dormant ones changing
nothing, the channel (time passes, moving cancels, pacing does not, reach is required), one real
den fight through the live systems, and the dusk gate at 1,000 dusks each way — 56% with a den
standing, exactly zero with none.

`check_sprite_scales` gained a section for the looted states. The assertion is **the pairing**
rather than a pixel size, and the reason is `WorldSite`'s documented canvas-width exception: a
looted sprite on a different canvas silently resizes the site the moment it is looted, and nothing
errors. So: both sprites resolve, same canvas, the looted one is not blank, and it is not
pixel-identical to its partner — a looted state that reads the same tells the player nothing, which
is the whole job of the swap. 122 assertions, up from 40.

Full suite, all green:

| Harness | Result |
|---|---|
| `verify_loot_tables` | 468 passed |
| `verify_terrain` | 261 passed (was 254) |
| `check_sprite_scales` | 122 passed (was 40) |
| `verify_stats` | 505 passed |
| `verify_combat_feedback` | 31 passed |
| `check_fog_and_minimap` | 41 passed |
| `measure_travel` | every row in band |
| headless boot | clean |

**`measure_travel`'s PENDING row is green.** The derelict graveyard was seeded at (40, 64) —
17 cells out, Band 2, just outside the lair band — which is the 10–20 cell ring P0 left pending:
`lair -> sortie-scale resource  17s  in band (10s-20s)`. No other row moved.

---

## 6. New art

Nine placeholder pairs (base + looted) at 128×128, generated by `tools/make_site_sprites.gd` and
kept in the repo like the deer's and the wolf's so they stay tweakable: graveyard, cache, shrine,
camp, ruin, den, crypt, cave, battlefield. The single graves reuse the commissioned
`Grave_Undisturbed` / `Grave_Dug_Up` pair, which is already exactly the right two states on the
right canvas.

Two rules made them usable. **128×128 everywhere**, matching the commissioned grave pair, because
of the canvas-width sizing above. And **the looted state is a different silhouette, not a darker
one** — at world zoom a tint is invisible, while a toppled pillar or an open black doorway reads
from across the valley.

---

## 7. What this pass deliberately did not do

- **Witnesses and haulage** — amendment rulings 4 and 5, both explicitly R3+/gear material.
- **The deposit, the escort, the Raven, drop-in-reach** — R2c, R2d, R2e and `SORTIE_SPEC.md` §5.
  `bank_relics()` exists and is asserted so R2c only has to call it.
- **The villain's own combat** — R2b. He fights guardians today because `Combat` was already
  complete on him and `Engagement` swings both ways; deliberate attacking, kiting, and the
  positional lair aura are R2b's.
- **The R4 shuffle** — `pool` / `active_count` are authored and unused, exactly as §8 asks.
- **`CLAUDE.md`'s ~8KB budget** is now overrun at ~11KB. It was already at 10.3KB before this pass;
  this added roughly 900 bytes and trimmed some back. A slim pass is owed, and is its own job.

---

## 8. Needs a human

The R2a exit criterion is a feel question and cannot be answered headless. Three things to check:

1. **Does a sortie present real decisions?** §10's criterion: one Band-1 and one Band-2 site should
   produce at least three (route, choice sheet, one-more-pull), fill the carry, and log a deed line.
2. **Is "one more grave, or turn back?" a real question?** This is the capacity-vs-yield pair
   (§10, `SORTIE_SPEC.md` §10). Carry is 6 and roughly one Band-2 site fills it. Tune the *yield*,
   not the capacity — and if tuning cannot make the question real, the designated next lever is
   load slowing the carrier, adopted only by striking SORTIE_SPEC §10's loaded-return assertion
   openly.
3. **Throne to village by ground alone, minimap off (M).** The P2 check that could not be run, plus
   whether the dressed ground actually telegraphs — does a patch of ruins or charred earth read as
   *something is here* from a distance, without a line leading to it?

Also worth watching: a lone caster against a 2–3 wolf pack is meant to be a real gamble and may be
outright lethal until the escort lands in R2d. If the near den reads as impossible rather than
risky, pack size is the tunable (§10 lists it), not the wolf.

Wire-level UI paths — the action buttons and the choice sheet — are `InspectorActions` and
`EventPanelUI` and cannot be exercised headless (`godot-mcp` simulated input never reaches the
game). They need a mouse.

---

# Playtest fixes — two invisible actions (2026-08-30)

First playtest of R2a (`2845d75`), at "A Fresh Grave" in the lair surroundings. Two symptoms, both
reported as *"clicking it appears to do nothing"*, and they turned out to be one of each kind: one
genuinely refused, one genuinely worked. Neither was click wiring.

Diagnosed with a throwaway probe scene that reproduced the exact screenshot state — full hands, a
remainder at the grave — before anything was changed. That is the only reason the second one was
not "fixed" by chasing the input path.

## Symptom 1 — Collect: a silent refusal, offered lit

The chain was fine end to end. `InspectorActions` built the button, the signal reached
`Main._begin_site_action`, `begin_action` ran and returned **true**, `_collect_remainder` ran, and
`Necromancer.add_carried()` **refused every kind** because he was 6/6 full.

Which is the trap: a remainder exists *precisely because* his hands were full when the site paid
out, so the single most likely moment to press Collect is the moment it cannot work. The row was
authored `"enabled": true` unconditionally.

Two things made it invisible rather than merely disallowed. The top bar shows **banked `GameState`
resources only** — carried loot has no HUD until R2c — so a successful collect and a failed one
look identical. And the probe caught the log actively lying: `_collect_remainder` emitted
`site_looted` with an empty haul, so Main printed *"A Fresh Grave gives up nothing he can carry"*
followed by *"He leaves 3 Bones behind"* — describing a fresh robbery, about bones the player had
left there himself a minute earlier.

Fixed, and the legibility is not waiting for R2c:

- `actions_for()` computes `enabled` and `reason` for the collect row from the villain's actual
  carry space. Full hands ⇒ disabled, with *"His hands are full — 6 / 6. Empty them at the lair and
  come back; it stays here."*
- **A greyed button now says why it is greyed**, on the panel, under the row it belongs to.
  `GAME_IMPROVEMENT_REVIEW.md` §9 asks for "clearer explanation of why an action is unavailable",
  and a tooltip does not satisfy it — nobody hovers a control that looks dead.
- `_collect_remainder()` returns a bool. A refusal reaches `Main` as `false` and raises a specific
  alert instead of reporting success.
- A successful collect writes its own TravelLog line — *"Collected: 2 Gold, 1 Dark Essence —
  carrying 3/6."*, naming what is still at the site if anything is — and no longer borrows
  `site_looted`, which is a signal about a site paying out and was making Main narrate nonsense.
- `Main._begin_site_action` refreshes the inspector **either way**. A press that changes nothing on
  screen is the entire bug.

## Symptom 2 — Raise: per spec, and invisible

`LOOT_SITES_SPEC.md` §4 says a raised corpse is dormant until the escort lands, and R2a implemented
that literally: an entry appended to `Necromancer.raised_dead` and nothing else. The probe confirmed
it — ledger entry written, Forbidden Knowledge deed emitted, notice applied, **zero nodes at the
graveside, sprite unchanged**. The only evidence anywhere was one line in the history log.

The dormancy is about what it can be *ordered to do*, not about whether it is there. So:

- **`RaisedDead`** — a Node2D standing where the corpse came up, wearing the Skeleton Worker's own
  art at `WorkerToken.SPRITE_TARGET_SIZE`, clickable and inspectable. It is a **pure view over the
  villain's ledger entry** (the Dictionary itself, not a copy), which is CLAUDE.md's data/view rule
  and also what lets R2d bind these into the escort by walking `raised_dead` with nothing to
  reconcile.
- It is deliberately **not** a `Worker` — handing it to `WorkerSystem` would put it on the
  gathering rota and it would walk off to chop wood — and **not** a `SiteGuardian`, so it can never
  enter `CombatSystem`'s target lists. It stands there.
- `WorldSites` owns them and spawns them through a `dead_riser` Callable, the same pattern the
  guardian spawner already uses so the site still cannot reach into its container.
- **The grave now looks disturbed as soon as it is disturbed.** `_refresh_sprite()` swapped only on
  `is_spent()`, so a grave with the body dug out and the valuables still in it showed undisturbed
  art. It now swaps on disturbance; destroy-the-evidence still reverts it, which is the rule that
  actually matters.
- Plus the TravelLog line: *"A Derelict Graveyard — it climbs out and stands there, waiting."*

The corpse charge behaviour was already right and is now asserted: raising consumes the *corpse*,
not the grave, so "steal" is still offered afterwards (§4's separate takings) and "raise" is not.

## Verification

`verify_loot_tables` gained three sections and is now **500 assertions**: a refused collect is
disabled with a reason and changes nothing while a permitted one writes its log line; raising
produces a live node over the villain's own entry, dormant, clickable, with the charge taken, the
sprite swapped, the deed emitted and the threat raised; and a grave holding only a remainder offers
Collect *and nothing else* (confirmed from the screenshot, asserted so it stays true).

One of the new assertions was wrong on first run and worth recording: it demanded the collect take
the **exact** remainder, which fails legitimately when the remainder is larger than his hands — the
battlefield leaves ten units against a capacity of six. Restated as the real invariant: a collect
neither creates nor destroys anything (`carried + still-there == was-left`, kind by kind), he takes
as much as fits, and repeated trips empty it.

**New: `tools/smoke_site_actions.tscn`** — 26 assertions, and the thing that was missing. The loot
harness calls `begin_action()` directly, which is right for rules and useless for the bug that
produced this report: everything between the click and `begin_action` was untested. This drives
`Main._inspect_at()` — the real click handler — finds the real `Button` by its text, checks no later
sibling `Control` overlaps it (the layering that has eaten HUD clicks twice), and emits its
`pressed` signal. Then the same for the choice sheet: open it, press *Raise the corpse*, run the
channel out, and assert a body is standing there.

It taught us two things about the game while being written, both correct behaviour that a test has
to respect:

- **Standing on a site inspects the villain, not the site** — characters outrank scenery in the
  pick order. The test stands *beside* the site, at an offset derived from the two radii rather
  than hardcoded, which doubles as an assertion: if a site's reach were ever smaller than the
  villain's own click radius there would be no point from which it is both in reach and clickable.
- **`_inspect_at` refuses anything under fog.** A placed villain has not been seen by the fog yet,
  so the test waits for the reveal to catch up.

Suite: `verify_loot_tables` 500, `smoke_site_actions` 26, `verify_terrain` 261,
`check_sprite_scales` 122, `verify_stats` 505, `verify_combat_feedback` 31,
`check_fog_and_minimap` 41 — all 0 failed. Headless boot clean, `measure_travel` every row in band.

`project.godot`'s `[rendering]` comment block was stripped again by the playtest run — the block
predicts this in its own last paragraph — and is restored.

## Still needs a human

Both fixes are the kind only a mouse can finally confirm: godot-mcp's simulated input never reaches
the game, so the smoke test covers everything except the OS event itself. Worth checking in the
next session:

1. Press Collect with full hands — the row should be visibly greyed with the reason *underneath*
   it, not hidden in a tooltip.
2. Empty his hands at a site with a remainder and press it — one log line, the row disappears.
3. Raise a corpse — a skeleton should be standing at the graveside before the channel bar clears,
   and the grave should look dug up.
