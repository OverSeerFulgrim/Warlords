# Race Roster — recruitable races, stats, alignment, housing

> **C2 LANDED 2026-08-27 — the stat table below is now definitively dead**, not merely scheduled
> to be. The live numbers are in `data/races.json`, derived from `stat_rework_roster.xlsx` by
> `tools/export_roster.gd`; hand-editing either the table below or the JSON's stat blocks puts
> them out of sync with the workbook that owns the formulas. Re-issuing this file with the
> exported numbers, or trimming it to its non-stat content, is still outstanding — a docs task
> rather than an engineering one. The original note follows.
>
> **PARTIALLY SUPERSEDED, 2026-08-06 (C2 adoption).** The **stat table below is dead**: it speaks
> the retired Might/Guile/Influence/Loyalty model. The live statlines — nine attributes per race,
> skill templates, overrides — are authored in **`stat_rework_roster.xlsx`** (COMBAT_SPEC §2, §12)
> and prompt **C2** exports them to `data/races.json`, replacing this table's numbers wholesale.
> **Still live and authoritative here:** alignment, recruitment rarity and the power-attracts-power
> weighting, food/appetite flavour, and house-placement behavior. When C2 lands, this file should
> be re-issued with the exported numbers or trimmed to the non-stat content.

Companion to `FOUNDATION_SPEC.md` (which owns the stat scale, RNG rules, and formulas). This file is the full roster: baselines, alignment, rarity, and house-placement behavior. All values are playtest hypotheses; this table should become `data/races.json`.

Scale reminder: **1–10, Human Peasant = 5 in everything, walk 1.0, food 1.0.** Individual recruits roll `baseline + d3 − d3` per stat (see FOUNDATION_SPEC §3).

## Alignment & rarity

Alignment is data on the race, not a moral system (yet). It drives:

- **Recruitment rarity** — event weighting: **Common 60% / Uncommon 30% / Rare 10%** of recruit offers *at base*. **Power attracts power:** as settlement Power grows, weights shift toward Uncommon/Rare and generated recruits roll better (e.g. at high Power, +1 to the exceptional-roll chance and a rarity shift like 40/40/20). Growth is what brings quality to your door.
- Later hooks (not foundation): good races react worse to cruel acts, good factions may raid you *specifically* to "rescue" them, alignment friction feeds starting relationships.

## The roster

| Race | Category | Alignment | Rarity | Might | Guile | Infl | Loyalty | Wood | Mine | Forage | Walk | Food | Housing style |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| *Human Peasant (ref)* | — | Neutral | not recruitable | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 1.00 | 1.0 | — |
| **Skeleton Worker** | Labor | Undead | player-made | 4 | 2 | 1 | 10 | 3 | 3 | 2 | 0.90 | 0 | none — workers don't take houses |
| **Orc** | Warrior | Evil | Common | 7 | 4 | 4 | 5 | 5 | 4 | 4 | 1.00 | 1.5 | Communal — loose warband circles |
| **Hobgoblin** | Warrior | Evil | Uncommon | 6 | 5 | 5 | 6 | 4 | 4 | 3 | 1.00 | 1.25 | Communal — orderly rows near the Barracks |
| **Ogre** | Warrior | Chaotic | Uncommon | 9 | 2 | 2 | 4 | 6 | 6 | 3 | 0.80 | 3.0 | Spaced — wants room, builds far from neighbors |
| **Troll** | Warrior | Chaotic | Rare | 9 | 3 | 1 | 3 | 5 | 4 | 5 | 0.85 | 3.5 | Spaced — near water if any |
| **Gray Dwarf** | Economy | Evil | Uncommon | 6 | 4 | 4 | 6 | 4 | 9 | 2 | 0.85 | 1.0 | Near-feature — digs in by the Stone Deposit |
| **Kobold** | Economy | Chaotic | Common | 2 | 5 | 2 | 4 | 3 | 6 | 4 | 1.05 | 0.5 | Clustered — burrow warrens near the mine |
| **Minotaur** | Economy | Neutral | Uncommon | 8 | 3 | 3 | 5 | 7 | 7 | 3 | 1.10 | 2.5 | Spaced — likes space, no adjacent houses |
| **Mountain Dwarf** | Economy | **Good** | Rare | 6 | 3 | 5 | 7 | 5 | 8 | 3 | 0.85 | 1.25 | Near-feature — stone, but apart from Gray Dwarves |
| **Gnome** | Research | Neutral | Uncommon | 2 | 7 | 5 | 5 | 2 | 3 | 4 | 0.90 | 0.75 | Near-feature — beside Workshop/Laboratory |
| **Dark Elf** | Research | Evil | Uncommon | 4 | 8 | 6 | 4 | 3 | 2 | 5 | 1.05 | 0.75 | Edge — secluded, rim of the settlement |
| **High Elf** | Research | **Good** | Rare | 4 | 7 | 7 | 5 | 3 | 2 | 6 | 1.05 | 0.75 | Spaced — apart, and never beside a Dark Elf |
| **Goblin** | Foraging | Chaotic | Common | 3 | 6 | 2 | 3 | 3 | 3 | 8 | 1.15 | 0.75 | Clustered — social, pile in next to each other |
| **Gnoll** | Foraging | Chaotic | Common | 5 | 5 | 2 | 4 | 3 | 2 | 9 | 1.20 | 1.5 | Clustered — with their own pack, away from all other races |
| **Halfling** | Foraging | **Good** | Rare | 3 | 6 | 6 | 6 | 3 | 2 | 8 | 0.95 | 1.5 | Clustered — social, plants little gardens |
| **Human Outcast** | Versatile | Neutral | Uncommon | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 1.00 | 1.0 | Communal — anywhere near town |

Notes on the shape of the table:

- Every category now has a good-aligned rare option (Mountain Dwarf/economy, High Elf/research, Halfling/foraging) except Warrior — deliberate: good warriors don't seek out necromancers. If one ever should, it's a *story event* (the fallen paladin), not a roster entry.
- **Human Outcast** is the flat-5 jack-of-all-trades — the peasant reference made recruitable. No specialty, no weakness, "Versatile" category (counts as nothing for the first-run category guarantee).
- Kobold is the cheap-to-feed swarm economy pick (0.5 food) vs Gray Dwarf's elite mining; Troll is the rare chaotic wall of meat that eats you out of the larder (3.5 food).

## House placement styles (the fund-a-house rule, per race)

When you fund a recruit's house, *they* choose the spot by their race's style:

| Style | Rule | Races |
|---|---|---|
| **Clustered** | Builds adjacent to an existing same-race house if one exists, else near town center. Social races. | Goblin, Kobold, Gnoll (own-pack only), Halfling |
| **Communal** | Builds near any existing houses/town center, race-agnostic. | Orc, Hobgoblin, Human Outcast |
| **Spaced** | Enforces a minimum distance (e.g. 2+ empty cells) from any other house. | Ogre, Troll, Minotaur, High Elf |
| **Near-feature** | Builds adjacent to a specific map feature or building. | Gray Dwarf & Mountain Dwarf (stone), Gnome (Workshop/Lab) |
| **Edge** | Builds at the settlement's rim, away from the center. | Dark Elf |

The settlement's final shape emerges from who you recruited: a goblin-heavy town is a dense knot; an ogre-minotaur town sprawls.

## Rivalry pairs (starting relationship penalties)

Rivalries set the *initial* relationship between individuals (see GAME_OUTLINE — shared missions can grind past it; Loyalty to you can override it for work):

| Pair | Flavor |
|---|---|
| Orc ↔ Ogre | Aggressive and territorial with each other |
| Mountain Dwarf ↔ Gray Dwarf | Kin feud — the exiles vs the ones who stayed below |
| High Elf ↔ Dark Elf | Ancient schism |
| Goblin ↔ Gnoll | Compete for the same foraging grounds |
| Kobold ↔ Gnome | Classic burrow-vs-workshop feud |
| Good-aligned ↔ Evil-aligned | Mild blanket starting penalty on top of specific pairs |

## Settled decisions

- **Power attracts power** — recruit-event rarity and quality scale with settlement Power (see Alignment & rarity above).
- **Race passives** (troll regeneration, kobold traps, halfling cooking) — deferred until after Stage 4.
- **Gnoll clustering** is preference-not-guarantee — no enforced minimum distance from other races' houses.
