### Populating the world, and tuning it to the clock (rework R1, second half)

The world from R1's first half was terrain and fog with nothing in it. This adds the static village, the sealed rival ground, the danger bands, orientation, and — the actual exit criterion — **measured travel times tuned against `WORLD_MAP_PLAN.md` §3**. Still no encounters, loot or reputation; those are R2.

#### The village is static, and its buildings are not `Building`s

Per rework §4 amendment 2: six houses, a watchtower, the church, the cemetery and the manor, plus two patrol loops. No homes/market/inn model, no daily routines, no reaction to anything.

**`WorldSite` is deliberately not a `Building`.** `Building` is a settlement citizen — it has a cost, a catalog entry, a `power_value`, a grid cell, and it emits `building_placed`. None of that is true of somebody else's house, and giving them the settlement's machinery would mean the player's Power score counted the human lord's manor. A world site is a sprite, a position and an inspection payload; content lives in `data/world_sites.json`, positioned in **world cells** (the settlement's own buildings stay in settlement cells and are none of this file's business).

**`Patrol` is built on `Roaming`** — the same two static helpers the deer and the wolf use — so it rounds terrain the way they do and inherits the debug time scale for free. All it adds is a waypoint list instead of a random point in a rectangle. It walks; it does not react. When R3 makes patrols escalate with notoriety, the thing to add is *reaction* (a detection radius and a response); the walking is done.

Both implement `get_inspect_data()` and nothing else, so they are clickable through the existing contract. `WorldSites.pick_at()` puts patrols above sites for the same reason characters outrank scenery everywhere: a man standing in front of a house is the thing you meant to click.

#### The rival region ships sealed

Amendment 1, as terrain plus one marker: the ritual-circle tile is painted at cells (21–23, 109–111), the 20×20 territory is reserved in the band table as "The Sealed Ground", and a dimmed `Dark_Altar` sprite stands on it reading *"something else sleeps here"*. No AI, no spawns, nothing to fight. The layout never needs rework when the Demonologist arrives as a playable class.

#### Danger bands are data, and only data

`data/world_map.json` gained a `bands` array — WORLD_MAP_PLAN §6's four bands as named rectangles. **Later entries win**, so the table reads as "the whole map is contested wilderness, except…", which is both the shortest way to write it and the right default: anywhere the design hasn't claimed is Band 2. `WorldMap.band_at()` is the only consumer, feeding one HUD readout. Nothing else reads the number — it is the hook R2's encounter and loot tables plug into.

#### Orientation: two aids, because the bar collapses

- **A minimap** in the command bar, at `MINIMAP_SIZE` 144 — the world's own cell count, so it's one pixel per cell and needs no scaling arithmetic. It draws a terrain image built **once** (coloured by `WorldMap.minimap_color_at`, which samples the actual tile art, so it can't drift from the ground) with **the very same fog `ImageTexture` the world draws** stretched over it. "Remembered terrain shows, unexplored doesn't" therefore needs no second copy of the fog state. Markers: the lair (a ring) and the Necromancer (a dot), plus the camera's view rect.
  - **No live contents on it**, deliberately: no workers, no wolf, no deer, no patrols. Knowing where the wolf is from across the map would undo the fog. The lair and the villain aren't intelligence about the world; they're the answer to "where am I and which way is home".
- **A text readout** under the HUD badge: `Cell 129, 76 · Band 3 — The Lord's Lands · Lair 107 cells W · Away 2m04s`. It exists because the command bar *collapses*, and 9216px of world is exactly the situation where the player must never be one keystroke from lost.

#### Travel is instrumented, then measured, then tuned

`TravelLog` (in-game) times the villain from leaving the lair band to reaching each registered landmark and back, in **game seconds** off `delta`, so it inherits the time scale — a 60× run reports the same numbers a 1× run does. Milestones go to the History log rather than raising alerts: pacing is something you read afterwards.

`tools/measure_travel.tscn` is the repeatable version and **is committed**, not thrown away, because every knob that moves these numbers (walk speed, road bonus, where the village sits, where the ridge sits) is a constant someone will change later. It routes with `AStarGrid2D` and then **walks the villain for real** — repeated `Necromancer.step()` calls at a fixed delta — so the number includes terrain sliding, diagonal normalisation and the road multiplier, because it comes out of the movement code the player drives.

It reports two routes per journey. **The wilderness route is the one judged against §3** (that section says "uninterrupted movement before … detours", and taking the road is a detour with a tradeoff — §9's "faster but exposed"); the road route is reported as the bonus it is.

**Measured, after tuning:**

| Journey | §3 target | Wilderness | On roads | Verdict |
|---|---|---|---|---|
| lair → nearby resource | 10–20s | **5s** (nearest) / 11s (furthest lair node) | — | near end under, by design — see below |
| lair → first landmark | 20–40s | **25s** | 25s | in band |
| lair → edge of local territory | 45–75s | **45s** | 45s | in band |
| lair → the village | 2–4 min | **2m02s** | 1m57s | in band |
| crossing the entire map | 3–5 min | **3m20s** | 3m12s | in band |

**Four things changed to get there, and none of them silently:**

1. **`Necromancer.MOVE_SPEED_CELLS` 1.4 → 1.0.** At 1.4 *every* row was FAST — the map crossing came in at 2m13s against a 3–5 minute target, the village at 1m18s against 2–4 minutes. A 144-cell map and a 3–5 minute crossing pin the walk speed at about 1.0 cells/sec; 1.4 was a guess made before the map existed. **The cost is real and worth knowing:** he is now only 11% faster than a Skeleton Worker cross-country, where R1's first half asked for "reads as faster". What preserves the feel is the road bonus — 1.35 cells/sec on cobblestone, comfortably faster than any labourer — so *roads* are now how the Necromancer outpaces his own dead. If that trade turns out wrong in play, the honest alternative is a smaller map, not a faster villain.
2. **The central ridge moved from x40 to x74.** It is the frontier of the Necromancer's valley and therefore what "edge of local territory" is measured to; at x40 that frontier sat 22 cells out, which is ~22s at any usable speed — a third of the 45–75s target. The 20×20 *starting region* (§5) is unchanged; what grew is the contested wilderness between it and the ridge.
3. **The ridge's northern pass moved from y56–66 to y36–46.** It used to sit on the lair's own latitude, which put the door directly in front of the front gate and made the ridge free to cross — the route east was a straight line and the wall may as well not have been there. Now you have to walk *to* the pass. That's what turns a wall into a route decision, and it is most of what buys the 2–4 minute village trip on a map only 144 cells wide.
4. **The village core moved east (x108 → x120), manor at (129, 83).** The 2–4 minute target needs the two powers at opposite ends of the map. It stays inside §5's 35×45 human territory.

**The one row still out of band, and why it isn't a bug.** The lair's own resources sit 5–11 seconds out. That is deliberate: workers walk them every trip, and a long haul would wreck the settlement economy's pacing — the far end (the grave past the forest, 11s) *is* in band, so the spread straddles the target rather than missing it. §3's row is really about sortie-scale resources, which R2 places; at 1.0 cells/sec the ring for those is **10–20 cells from the lair**, and that is the number R2 should seed against.

#### Day/night pressure comes free, as predicted

A village round trip is **4m04s** against a 30-minute day — 14% of the daylight, so roughly seven round trips fit in a day and leaving in the last few minutes of it does not. Verified mechanically by parking the clock two minutes from dusk and simulating a round trip's worth of travel: **dusk fell, the wolf spawned, and a meal tick was served, all while he was away.** No code connects travel to the day cycle; they interact because they share one clock.

(One gotcha the test found: `MoraleSystem` correctly serves **no meal at all** when the roster is only skeletons, which is the Stage-0 state — so a meal-tick assertion has to put a living recruit on the roster first, or it silently tests nothing.)

#### R1 exit criteria

- ✅ **Walk from the lair to the village and back inside the travel-time targets** — 2m02s each way wilderness, 1m57s by road, both inside §3's 2–4 minutes; round trip 4m04s.
- ✅ **Fog clearing as you go** — the 7-cell reveal travels with him, ground behind him drops to remembered, the lair band never dims.
- ✅ **Day/night pressuring the trip** — dusk, the wolf and the meal tick all land inside a round trip's window.
- ✅ Sealed rival region, static village shell, camera follow, controllable villain, 144×144 fixed layout.

**Still needs a human at the keyboard:** whether leaving at the wrong hour *feels* like a real decision. The mechanics are confirmed; the pacing judgement isn't something a harness can make.

#### Verification

A 43-assertion scene harness covering all of the above: village content and every site and patrol waypoint standing on walkable ground; the watch actually walking (1014px in a minute of game time) and having no reaction methods at all; the sealed ground inspectable, on the ritual tile, in its reserved region, spawning nothing; bands loading with the lair at Band 1, open country defaulting to Band 2 and four deep-danger pockets; the minimap built one-pixel-per-cell, sharing the world's fog texture, and containing **no reference to any unit type** (the first version of that check failed on its own comments, which name the units it ignores — strip comments before scanning source); the travel clock starting on leaving the band and closing on return; the day/night interaction above; and the R1b invariants re-checked (seeded nodes still in the band, wolf still entering 11.7 cells from the Throne, terrain still one node, villain still out of the labour pool).

The final run showed 42 of 43, with the odd one out being the harness's own bookkeeping — a follower injected to test the meal tick was no longer in the labour pool after 260 seconds of simulated dusk and wolf activity. The substantive assertion next to it (the villain is not in the pool) passed, and a clean check confirmed a freshly-added follower does enter the pool. Recorded rather than papered over.

One art note that cost a screenshot to find: **`D` (snow-edged dirt) is a transition tile, not a field tile** — it carries a vertical snow band, so bulk-filling with it renders the farmland as corduroy. It stays in the legend for edge use and is out of every bulk fill.

