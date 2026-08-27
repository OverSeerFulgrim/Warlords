# The stat rework: one Might becomes nine attributes (COMBAT_SPEC slice C2)

`COMBAT_SPEC.md` §2–§4, adopted into the roguelite build order by its 2026-08-06 amendment block
and scheduled before the R2 prompts on the grounds that everything from R2a on consumes stats, and
building those on `combat_might()` would mean migrating every harness twice.

The map is untouched. This is combat, labor and data.

## The workbook is the editing surface, and the JSON is derived

`stat_rework_roster.xlsx` already carried all 153 attribute values, six skill templates, 35
overrides and the derivation formula — §12's authoring problem was solved before this prompt
started, which is what made C2 an engineering task rather than a design one.

**`tools/export_roster.gd` reads the `.xlsx` directly.** A workbook is a zip of XML, so `ZIPReader`
plus a little parsing gets there with no conversion step and no second copy of the numbers to
drift. Re-authoring a race is now: edit the workbook, run the exporter, commit both.

It owns exactly the stat blocks — `attributes`, `skill_template`, `skill_overrides`, `walk_speed`,
`category`, `alignment`, `rarity`, plus the `_skill_templates` / `_governing_attribute` /
`_derivation` blocks. It **merges forward** everything else from the existing file: sprites,
housing rules, `food_per_meal`, rivalries. Art paths are not stats and are not the exporter's
business.

Two things it derives rather than copies, so the JSON cannot disagree with itself:

- **Walk speed** from the Speed attribute through the workbook's own divisor.
- **Overrides** as the diff against the template. That is the workbook's own shape (its shaded
  cells), and it keeps a template edit moving every race that did not opt out — §12 step 3's whole
  point.

Templates and the governing map live in `races.json` under `_`-prefixed keys. `RaceCatalog` reads
them **before** its documentation-key strip, because they are comment-keyed by convention but
genuinely load-bearing data.

One parse detail worth recording: the sheets are walked **row by row**, not by scanning for `<c>`
across the file. A first version scanned cells globally and filed values under the wrong rows — the
Legend sheet came out with its columns shifted by one, which looked like a workbook problem and
was not.

## The contract widened, and `is_combatant()` moved with it

```
combat_profile()     -> {profile, attack_attr, defence_key, reach_px}
combat_defence(key)  -> int
```

replacing `combat_might()`. **The asymmetry in those two middle keys is the design**: `attack_attr`
is a *value* — the attacker knows its own number — while `defence_key` is a *name*, because the
defender has to be asked. Passing the attacker's number and the defender's key is what lets one
formula serve three profiles with no branching:

```gdscript
var to_b := damage_roll(pa["attack_attr"], b.combat_defence(pa["defence_key"]))
```

`Combat.is_combatant()`'s method list was updated **in the same commit**, which is the only reason
it can do its job: it exists so a half-migrated unit fails loudly instead of silently dealing
minimum damage forever, and that is exactly what would have happened across this rework if
`combat_might` had been left in the list. The harness asserts it both ways — a unit implementing
only the retired contract is rejected, and one implementing the new contract is accepted.

`EXCHANGE_INTERVAL`, the d3, `MIN_DAMAGE` and both-swings-land are **untouched**. The rework moved
the vocabulary, not the model.

`FLEE_HP_FRACTION` is **deliberately still there**, despite §4.1 deleting it: that deletion is C3,
and the amendment block is explicit that C3 stays post-R2 *because* the R2 escort's interpose
threshold reads the constant.

## Profiles fall out of the rule, and nothing is named

§3.1 rule 3 — highest of Str/Dex/Int, ties to Strength — is the whole of v1, and it cost no new
data. The wolf is Melee because Strength 5 is its highest; the Necromancer is Arcane because
Intelligence 7 is his. **Neither is a special case, and if either had needed one the rule would be
wrong rather than the unit special.** The harness checks the profile of all 17 races plus the
villain and the wolf against the workbook's own profile column, and checks the tie order that the
roster happens not to exercise.

## Nothing shipped moved

The roster was authored so that Endurance 4/5/6 reproduce the old Might values exactly:

| Unit | Before | After | Why |
|---|---|---|---|
| Skeleton Worker | 16 hp, carry 4 | 16 hp, carry 4 | End 4 |
| Wolf | 18 hp | 18 hp | End 5 |
| Necromancer | 20 hp, carry 6 | 20 hp, carry 6 | End 6 |

`measure_travel` reports **every row byte-identical** — that was step 4's gate, and walk speeds
moving would have been a failed export rather than a retune. Walk speed now derives from the Speed
attribute through the workbook divisor, and the tuned 1.0 / 0.9 / 1.3 fall straight out of Speed
5 / 4 / 8.

**Two numbers did move, both sanctioned.** The wolf's chase speed goes 78 → 83 px/s, because
COMBAT_SPEC §7 asks for Speed 8 to mean 1.3 cells/sec and calls out why it matters (without it a
melee-only predator can never close on an archer, and two ranged recruits trivialize the creature
layer). `PROWL_SPEED_PX` stays a hand-tuned constant — ambling is a behaviour state, not a stat.

And **gather times move**, which is the rework paying out rather than a regression: `skill_for()`
now returns the *effective* skill, so a Gray Dwarf's Mining and a Skeleton Worker's are dragged
further apart by their governing attributes, and gather time is `4.0s × 5 / skill`. That is
COMBAT_SPEC's exit criterion 2, visible in the trip loop rather than in a stat panel.

## The derivation formula, and two floors that are not cosmetic

```
effective_skill = clamp(skill + floor((attr − 5) / 2), 1, 10)
```

Computed at use time, **never stored** — a stored copy goes stale the moment gear, training or a
trait moves the attribute, which is the same reasoning that keeps `max_hp()` computed.

The float division is not incidental: integer division truncates toward zero, so `(2−5)/2` would
give −1 where the formula wants −2, and every below-average attribute would quietly round in the
unit's favour. The harness asserts the edges directly (attr 2 → −2, attr 4 → −1, attr 5 and 6 → 0,
attr 10 → +2) rather than inferring them from the roster.

The floor of 1 is the workbook's own note and worth repeating: gather time divides by skill, so a 0
divides by zero, and a low template value plus a −2 modifier reaches 0 easily — a Skeleton Worker's
Research lands at −1 before the clamp.

**One discrepancy with the prompt, resolved in the workbook's favour.** The order gave the spot
checks as "Gray Dwarf mining 9+1=10 capped, Ogre 6+2=8". The Ogre is right (Mining 6, Str 9, +2).
The Gray Dwarf is not: its Strength is 6, so `floor((6−5)/2)` is **0**, and its effective Mining is
**9** — which is what the workbook's own Effective skills sheet shows. The harness asserts 9. No
attribute would make 9+1 come out of that row; the parenthetical was simply mistaken.

## Recruit generation, and where the star lands

Nine attributes and twelve skills, each rolled independently off the race baseline with the same
`baseline + d3 − d3` spread. What widened is the number of things it rolls, not how any one rolls.
Walk speed is *not* rolled — it derives from Speed now, so rolling it would put a recruit's legs at
odds with their own statline.

The 5% exceptional roll moved from a stat to the **category-defining attribute**: Warrior →
Strength, Research → Intelligence, Foraging → Perception, Economy → whichever attribute governs
that individual's best labor skill. Bumping the attribute rather than the skill is what makes the
star mean something beyond one job — +1 Strength is a better miner *and* a harder hit, which is the
whole reason attributes and skills are separate layers. Rarity weights, the Barracks gate and the
offer machinery are untouched.

## What the rework had to rename rather than keep

- `_will_fight`'s `might >= 6` becomes `strength >= 6` — the *shape* of the emergent-defence rule
  is unchanged, exactly as §6.2's note asks. The judgement/guidance layer that eventually replaces
  the threshold is C3.
- The Barracks trains +1 **Strength**; the Blacksmith's gear moves a physical attribute. Real
  equipment slots that set the attack profile are §9 and unbuilt.
- `Follower` stopped declaring `guile` and `loyalty` — they live on `Laborer` with the other seven
  now, and redeclaring would have shadowed the base class.
- **`influence` is retired, not moved.** §2.1 is explicit: it was vague, barely read, and Leadership
  (Tact) and Mercantile (Guile) cover what it gestured at as *trainable skills* rather than a fixed
  attribute. `missions.json`'s court-infiltration mission reads `mercantile`; the two `might`
  missions read `strength`. `mission_check()` now resolves any of the nine attributes or twelve
  skills by name.

## Verification

`tools/verify_stats.tscn`, **505 assertions, all passing**, headless as a scene.

Every race carries nine attributes on the 1–10 scale (the Necromancer eight — his Loyalty is
authored as an em-dash in the workbook, loyalty to whom?, and is kept out of the block rather than
faked as a number). Every race resolves all twelve skills to a legal effective value; the two
creature rows deliberately resolve none, because a wolf does not mine. Twelve spot checks against
the workbook's Effective skills sheet. Profile assignment for all 19 rows against the workbook's
profile column, plus the tie order. `damage_roll` reading the right pair for all three profiles,
the reach values, the d3 span and `MIN_DAMAGE`. The hp/carry table above. `is_combatant` accepting
the new contract and rejecting the old one. And the Might grep as an assertion, over every script
in `scripts/`, with comments **and string literals** stripped first — both exclusions earn their
place: headers legitimately explain what Might used to be, and `ThreatSystem`'s escalation flavour
text contains the ordinary English "a witch hunter might sniff around".

Also passing unchanged: `check_sprite_scales` 40/40, `check_fog_and_minimap` 41/41,
`verify_combat_feedback` 31/31, headless boot clean, and `measure_travel` on every row.

**One pre-existing harness bug fixed on the way through.** `verify_combat_feedback`'s Throne-repair
test went intermittent under this branch. The cause was mine, from the F1 commit: `_wait()` counts
*game* seconds (`get_process_delta_time()` is already time-scaled), so dividing the wait by the
time scale asked for 0.9s of game time against a 6s timer. It passed only when an earlier test had
left the repair accumulator nearly full — an intermittent green that had nothing to do with the
code under test. The wait is now the full `THRONE_REPAIR_SECONDS`, with the time scale deciding
only how fast that arrives.

## Still outstanding

`RACES.md`'s stat table is now definitively dead and its header says so, but re-issuing that file
with the exported numbers — or trimming it to its non-stat content — was not in this slice's scope
and remains a docs task. C3 (morale routing, judgement, guidance, wolf packs) is unchanged and
still post-R2: it deletes `FLEE_HP_FRACTION`, which R2's escort reads.
