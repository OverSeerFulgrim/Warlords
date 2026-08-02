# Claude Code Prompts — Foundation Build (Stages 1–3)

Copy-paste these into Claude Code **one at a time, in order**, from this project folder. Each stage is self-contained and leaves the game runnable, so you can playtest between stages. If a stage's smoke test fails, fix that before moving on.

Every prompt starts with the same context line so a fresh session knows where to look. If you run stages in one continuous session, you can drop that line after the first prompt.

---

## Prompt 1 — Data groundwork & the reset

```
Read CLAUDE.md, GAME_OUTLINE.md, FOUNDATION_SPEC.md, and RACES.md before touching anything. Follow the architecture conventions in CLAUDE.md (GameState/EventBus autoloads, data-driven JSON, RefCounted for non-visual objects).

Do the following, keeping the game runnable:

1. Create data/races.json from the roster table in RACES.md: all 16 races with category, alignment, rarity, the 4 character stats (might/guile/influence/loyalty), the 3 labor skills (woodcutting/mining/foraging), walk_speed, food_per_meal, housing_style, and a rivalries list per the rivalry-pairs table. Include the Human Peasant as a non-recruitable reference entry.

2. Add "food" as a fourth mundane resource in GameState (add_resource/spend_resource/can_afford), displayed in the stats bar.

3. Reset the starting state per FOUNDATION_SPEC section 10: Throne of Bones only, 1 Skeleton Worker, wood=8 stone=5 bones=10 food=5 dark_essence=0, zero followers (remove the 3 seeded starting followers Grix/Morra/Vash from _seed_starting_state).

4. Hard-lock the Stage-4 systems: hide (not just log-reject) the Post Bounty, Dispatch Mission, Forge Equipment, and Train Followers buttons. Keep BountyBoard/MissionSystem code intact — just don't surface them. Remove the Dark Altar and the old species-housing buildings (bone_crypt, charnel_pit, haunted_spire, war_camp, burrow_warren) from the build menu by marking them "locked": true in buildings.json and filtering in BuildingCatalog.buildable_ids — do not delete their entries.

5. Update CLAUDE.md with a short section describing what changed and why (foundation reset, races.json, food resource, locked systems).

Smoke test before finishing: game runs, stats bar shows Food, no followers at start, exactly one worker, locked buttons absent, build menu shows only Bone Pile + Workshop-line buildings.
```

## Prompt 2 — Day/night cycle

```
Read CLAUDE.md and FOUNDATION_SPEC.md section 7 first.

Implement the day/night cycle:

1. New system (Main.gd-owned, same convention as WorkerSystem): a game clock with day = 30 minutes and night = 20 minutes of real time. Emit EventBus signals dawn_started and dusk_started, plus a generic phase_changed(is_day). 

2. CRITICAL for testing: add a debug time-scale multiplier (a constant or an on-screen debug button cycling 1x/10x/60x) so a full cycle can be tested in under a minute. All timers in the game (gathering, events, meals) must respect this multiplier — route it through Engine.time_scale or a shared GameClock.scaled_delta helper, whichever fits the codebase better, and document the choice in CLAUDE.md.

3. Visual: a subtle full-screen tint (CanvasModulate) that shifts toward dark blue at night and back at dawn, with a short transition. A small clock/phase label in the stats bar ("Day 2 — Dusk").

4. Nothing else changes behavior yet (meals hook in later) — but berry-grove regrowth and deer spawning (coming in Prompt 3) will listen for dawn_started, so make sure the signal fires reliably even at 60x.

Update CLAUDE.md. Smoke test: run at 60x, watch two full cycles, tint shifts, day counter increments, no errors.
```

## Prompt 3 — Map nodes & the trip-loop work model (the big one)

```
Read CLAUDE.md, FOUNDATION_SPEC.md sections 4-6, and RACES.md before starting. This replaces the flat-tick worker economy with physical gathering.

1. ResourceNode scene/class (Node2D): fields for kind (wood/stone/food/bones), remaining stock, gather action time, position. Subtypes per FOUNDATION_SPEC section 5:
   - Forest: cluster of ~20 Tree nodes (10 wood each, finite, become stumps) + 4 Animal Bones carcasses (5 bones each, finite) scattered inside it, east of the grid.
   - Stone Deposit: 250 stone, finite, south.
   - Berry Grove: 40 food cap, regrows +8 at each dawn_started, west.
   - 2 Graves: 12 bones each, finite — one by a road edge, one at the forest's far edge.
   - Deer: 8 food per kill, hauled home whole; 2-3 roaming near map edges, one new deer wanders in at dawn up to cap. Simple wander movement, no fleeing AI yet.
   Nodes visibly deplete (tree -> stump, empty grave marker). Replace the old fixed forest/stone markers from _build_resource_nodes.

2. Give Worker.gd real stats from races.json (Skeleton Worker row): labor skills, might, walk_speed. Workers stay non-individual (no RNG variance, fixed at baseline).

3. Replace WorkerSystem's flat _gather_tick with a per-worker trip loop state machine: pick target node (from priority list, nearest eligible of that kind) -> walk there (walk_speed * 1 cell/sec) -> gather (per unit: 4.0s * 5 / relevant skill) until carry-full or node empty -> walk home -> deposit into GameState -> repeat. Carry capacity = Might. WorkerToken movement must now BE the real trip (kill the old fake glide loop and its honesty-note comment - the token position and the economy are one system now).

4. Priority list UI (bottom bar, replaces per-worker cycle buttons): ranked rows for Wood / Stone / Food / Bones, each with a threshold spinner. Workers serve the highest-priority resource whose stock is below threshold; when stock >= threshold they fall through to the next. Food routing picks berries or deer by nearest-available (skeletons CAN forage/hunt, Forage 2, slowly).

5. Update CLAUDE.md (this is a big architecture change - document the trip loop and the priority system thoroughly).

Smoke test at 10x time: 3 workers, wood threshold 30 -> all chop until 30 banked, then fall through to stone; trees visibly become stumps; a worker hauls a deer home; bones come from carcasses/graves and run out when depleted.
```

## Prompt 4 — Barracks & recruitment

```
Read CLAUDE.md, FOUNDATION_SPEC.md sections 3 and 9, RACES.md (roster, rarity weights, power-scaling), and GAME_OUTLINE.md Stage 3 before starting.

1. Add Barracks to buildings.json: cost 8 wood / 6 stone, category "housing_intake", capacity 5, power_value 4, unique (only one can ever be built - filter in buildable_ids once placed). Clicking it opens a Barracks panel listing residents. Include an Upgrade button in that panel that is visibly present but hard-locked: greyed out, label "Locked", no cost, no handler.

2. Recruitment events: gate the event timer on Barracks existence (replace the old EVENTS_ENABLED const - events on when Barracks built AND has a free slot). Rework recruit generation to roll from data/races.json instead of followers.json templates:
   - Pick race by rarity weight: base 60/30/10 common/uncommon/rare, shifting with Power ("power attracts power"): at Power >= 25 use 50/35/15, at Power >= 40 use 40/40/20. Make the tiers a data table, not hardcoded branches.
   - Roll each stat/skill as clamp(baseline + randi_range(1,3) - randi_range(1,3), 1, 10). 5% exceptional chance: +1 to the race's category-defining stat (warrior=might, economy=best labor skill, research=guile, foraging=foraging). Exceptional recruits get a marker in UI.
   - First-run guarantee: the first three recruit offers must span three different categories including at least one warrior, one economy, one research race.
   - Recruits arrive INTO the Barracks (occupy a slot). Full Barracks = offer event still fires but the only choices are turn-away variants.
3. Followers keep working through the existing roster row; new recruits should also gather if assigned by the priority system using their (usually better) labor skills - a settled dwarf out-mines every skeleton you own.

4. Update CLAUDE.md. Smoke test at 10x: build Barracks from gathered resources, receive 3 recruits spanning the category guarantee, see varied stats between two recruits of the same race, fill the Barracks to 5 and see the turn-away behavior.
```

## Prompt 5 — Food, morale & fund-a-house

```
Read CLAUDE.md, FOUNDATION_SPEC.md sections 7-9, RACES.md housing styles, and GAME_OUTLINE.md Stage 3 before starting.

1. Meals: on dawn_started and dusk_started, every living recruit (not skeletons) eats their race's food_per_meal from GameState. Feeding order: highest Loyalty first. 

2. Morale: per-recruit morale int 1-10, starts 7, shown in the roster/Barracks panel. A recruit who misses a meal loses 1 morale; a full day with food regains 1 (cap 10). At morale <= 3, fire theft/rule-breaking flavor events (small resource loss, logged). At morale 1, a departure warning event, then the recruit leaves at the next missed meal. Store departed recruits with a disposition value for the future departure-memory system - data only, no return events yet.

3. Fund-a-house: button per Barracks resident, cost 6 wood / 4 stone. The recruit picks their own spot by race housing_style per RACES.md: clustered (adjacent to same-race house, else near town center), communal (near any houses), spaced (>= 2 empty cells from any house), near-feature (adjacent to stone deposit or workshop per race), edge (settlement rim). Gnoll clustering is preference-not-guarantee - if no valid preferred cell exists, fall back to communal placement rather than blocking. House placement frees the Barracks slot; the recruit's token idles near their house. Houses are small sprites from the existing Buildings/House pack, tinted or varied per race.

4. Update CLAUDE.md, including a "foundation exit criteria" checklist copied from FOUNDATION_SPEC section 11 with checkboxes for manual playtesting.

Smoke test at 10x: recruit an ogre (3.0 food/meal) and watch food drain; starve him -> morale drops, theft event, departure warning; recover with food -> morale climbs; fund houses for a goblin (clusters), a minotaur (spaced), and a dwarf (by stone); Barracks slots free correctly.
```

---

## After all five

Run the full exit-criteria checklist (FOUNDATION_SPEC §11) at 1x speed in one unbroken session. Anything that fails goes back to Claude Code as a targeted bug prompt — include the exact log output and which criterion failed.

Two standing reminders for any prompt you write yourself:

- Real mouse input can't be verified over MCP (see CLAUDE.md "Known constraint") — anything involving clicks needs a human hand on the actual window.
- The project still isn't in git. Before Prompt 3 (the big rework), seriously consider: move the folder somewhere durable, `git init`, commit. Cheap insurance.
```
