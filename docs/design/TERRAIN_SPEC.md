# TERRAIN SPEC — Seven Sheets, and Roads That Lead Somewhere

**Status:** Reviewed as-built (shipped in P1/P2), designer review 2026-08-29. Originally drafted 2026-08-06. Extends the terrain layer built in R1
(`docs/history/2026-08-world-map-r1.md`) from one tilesheet to seven, adds a connection-tile
(autotile) layer, and teaches `tools/make_world_map.gd` to lay roads by rule instead of by hand.
Nothing here is implemented. **Sits between P0 and R2a** in `docs/prompts/R2_PROMPTS.md`.

> **Amendment, 2026-08-06 — forests.** Added §6b (dense forest and open woodland as terrain,
> forest corridors, and interior clearings as the map's isolated pockets), two legend rows (§5),
> a forest step in the generation pipeline (§8), a canopy layer in the touchpoints (§10), and the
> matching verification (§12). Motivation: the world has **no trees at all** today — the only
> pines on the map are the lair band's twenty gatherable `ResourceNode`s, and the wolf's
> "treeline" is a comment in `CombatSystem.gd`, not a place. Forests become the third wall (after
> the ridge and the river), the thing that carves paths, and the thing that hides places worth
> finding. `LOOT_SITES_SPEC.md`'s wolf den (its same-dated amendment) anchors into these
> clearings.

**Scope:** the sheet catalog, the semantic-vs-connection split, the bitmask scheme, the extended
legend, forests and the clearings they seal, the road hierarchy and what it is allowed to
signpost, generation rules, and the travel-time risk this carries.

**Out of scope:** run-to-run shuffle (still R4 — §11 explains how this feeds it), site loot
(`LOOT_SITES_SPEC.md`), anything that moves during play.

**Companion documents:** `WORLD_MAP_PLAN.md` (§3 travel targets, §4 structure, §6 bands, §9 roads
vs wilderness, §11 replayability), `ROGUELITE_REWORK.md` (§4 amendments, §13 R4),
`LOOT_SITES_SPEC.md` (§1.4 distance buys quality, §3 telegraphing), `CLAUDE.md`,
`docs/art/SPRITE_SPEC.md` (which does **not** govern terrain — see §2).

---

## 1. Design goals

1. **The map should tell you where to go without a quest marker.** A road that leads to the village
   is the oldest and cheapest wayfinding there is, and it costs no UI. Terrain is the tutorial.
2. **But not everywhere.** If every path leads to loot, exploration collapses into route-following
   and `LOOT_SITES_SPEC.md` §1.4's "distance buys quality" stops meaning anything. The signposting
   hierarchy in §7 is what keeps the deep stuff worth finding.
3. **Connection tiles are computed, never authored.** A cobble T-junction is not a terrain *type*,
   it is a terrain type plus its neighbours. The legend stays semantic; the renderer picks the
   corner. Otherwise 112 tiles become 112 legend characters and the layout becomes unmaintainable.
4. **No layout knowledge in GDScript.** R1's rule holds: `WorldMap` reads a legend and rows and does
   not know where the village is. The bitmask→tile table is data too.
5. **Walls need doors.** The ridge taught this in R1 — *a wall with a door is a route decision; a
   wall without one is a smaller map*. Rivers get fords and bridges for exactly the same reason.
6. **The generator is the thing being built, not the map.** Every rule here is authored once in
   `make_world_map.gd` and baked. That is what makes R4's shuffle a change of inputs rather than a
   rewrite.
7. **Forests are walls made of trees, and their gaps are the paths.** The ridge and the river are
   the map's first two walls; dense forest is the third, and the cheapest to shape — a corridor
   through trees needs no bridge art and no pass tuning, just an absence. And unlike rock, a
   forest can hold something *inside* it: a clearing with one way in is the strongest "found, not
   followed" telegraph the map can make (§6b).

---

## 2. The seven sheets

All seven are **1254×1254, 4×4, 305px tiles, 5px margin, 8px separation** — measured, not assumed.
`WorldMap._build_atlas_texture()` slices them with the existing code path; only the atlas grows.

| Sheet | Contents | Primary role |
|---|---|---|
| `Terrain_Tileset_Snow.png` | the R1 set — grass, snow, dirt, cobble, scree, ice, ritual, bone-strewn | base ground, unchanged |
| `Terrain_Tileset_Road_Cobble.png` | grass + 15 cobble connection pieces | **human roads** (autotile) |
| `Terrain_Tileset_Path_Dirt.png` | grass + 15 dirt connection pieces | **worn tracks** (autotile) |
| `Terrain_Tileset_Roads_Snow.png` | snowy dirt and cobble connection pieces, cart ruts | winter variants of the above |
| `Terrain_Tileset_Water_Ice.png` | deep water, shallows, ice, cracked ice, shore edges, river, ford, **two bridges** | water, and the doors through it |
| `Terrain_Tileset_Rock_Ruins.png` | boulders, fallen log, **cliff faces and corners**, snow-topped plateau, rubble, **stone ruins**, burnt ground with stumps | real mountains; ruins that telegraph sites |
| `Terrain_Tileset_Marsh_Corrupt.png` | **marsh with reeds**, dark forest floor with roots, dry/dead grass, **plowed and stubble farmland**, charred ground with embers, cracked black earth, sickly moss, **ritual circle** | marsh, farms, corrupted ground |

**Two placeholders close here**, both flagged in R1's own write-up:

- *"Rocky scree stands in for mountains — the sheet has no mountainside tile. It is the one terrain
  placeholder; a real cliff/mountain tile belongs in the art brief."* → the rock sheet.
- *"Adding 'marsh: walkable but slow' is a JSON edit, not a new branch."* → the marsh sheet, and it
  is still a JSON edit (§4).

**Four things the map doc asked for and R1 shipped without:** human farms (§4's sketch), corrupted
terrain and a real ritual ground for the Demonologist's region (§5), water that is a route problem
rather than a wall, and ruins-as-terrain so a lootable site reads as one before you are on top of it
(`LOOT_SITES_SPEC.md` §3's telegraphing requirement).

**`SPRITE_SPEC.md` does not apply.** It governs 256px-canvas character and building sprites with a
y=224 baseline. Terrain sheets are already an exception and stay one — full-res in
`assets/official/terrain/`, sliced and resampled at load. Note this in SPRITE_SPEC so the next reader
doesn't try to "fix" it.

**There is no eighth sheet, and forests don't need one.** A forest is two things layered: a
*floor* (the marsh sheet's dark forest floor with roots — already commissioned, already in the
catalog above) and a *canopy* of individual tree sprites drawn over it (§6b). The trees are the
existing commissioned `Pine_Tree.png` — a 256px-canvas node sprite, which **is** governed by
SPRITE_SPEC, unlike the ground it stands on. One asset family for every pine in the game: the
lair's gatherable trees and the world's impassable ones are the same tree at different sizes,
which is what makes the forest read as *more of the thing you already chop* rather than as new
scenery.

> **Cell coordinates are deliberately not tabulated in this document.** Which of a sheet's sixteen
> cells holds which connection case must be read off **the dumped atlas**, not off a description.
> R1 already recorded the practice: *"Dump the sliced atlas to a PNG when tiles look wrong — a margin
> or separation off by a few pixels shows up there and nowhere else."* The wiring pass produces that
> dump first and fills in §5's table from it. Guessing here would bake a silent off-by-one into
> every road on the map.

---

## 3. Semantic terrain vs connection tiles

The load-bearing distinction.

**A semantic type** is what a cell *is*: `road_cobble`, `path_dirt`, `water`, `cliff`, `marsh`,
`farmland`, `grass`. It has a category (`ground` / `road` / `blocking`), a speed multiplier, and a
name. It is what the legend character means and what `make_world_map.gd` decides.

**A connection tile** is what a cell *looks like*, derived from the semantic types of its four
orthogonal neighbours. It is never authored and never appears in the legend.

```
data/world_map.json  rows:  semantic characters only  ("C" = cobble road)
        ↓  WorldMap._resolve_connections()  (once, at load)
TileMapLayer cells:  atlas coords with the right corner/T/cross
```

This is why the sheets are 4×4: **sixteen tiles is exactly the number of four-neighbour
combinations.** The art is shaped for a bitmask, so use one.

---

## 4. The bitmask scheme

For any *connecting* type (road, path, water, cliff), a cell's tile is chosen by which orthogonal
neighbours share that type:

```
mask = (N ? 1 : 0) | (E ? 2 : 0) | (S ? 4 : 0) | (W ? 8 : 0)     # 0..15
```

- **Roads and paths** connect to *themselves and to each other* — a dirt track meeting a cobble road
  should form a junction, not a dead end. Connectivity is by **connection group**, not by exact
  type, so `road_cobble` and `path_dirt` share the group `road`.
- **Water** connects to water; the mask picks the shore edge. Ice is its own group (an ice shelf
  meets water with a different edge than land does).
- **Cliffs** connect to cliffs. **Caveat, stated honestly:** proper cliffs need inner *and* outer
  corners, which is a 47-tile blob set. Sixteen tiles gives faces and outer corners only, so inner
  corners will approximate. Generate cliff ranges with **convex outlines** and the seam never shows;
  if a concave notch is ever needed, that is a request for more art, not a code problem.
- Out-of-bounds counts as **not connecting**, so the map rim terminates roads cleanly.

**The mapping is data:**

```json
"connections": {
  "road": {
    "sheet": "road_cobble",
    "masks": { "0": [0,1], "1": [1,0], "2": [2,0], "3": [3,0], "...": "16 entries" }
  },
  "water":  { "sheet": "water_ice",  "masks": { "...": "..." } },
  "cliff":  { "sheet": "rock_ruins", "masks": { "...": "..." } }
}
```

Filled from the dumped atlas (§2). A missing mask entry is a **hard error at load**, not a fallback —
a silently-wrong corner on one cell of 20,736 is exactly the bug nobody finds.

**Cost:** one pass over 20,736 cells at load, four neighbour lookups each. The same order of work as
the existing `set_cell` loop, which measured 52 draw calls and 1.3ms average frame. No per-cell
nodes, same as before — the trap R1 documented has not moved.

---

## 5. The extended legend

The legend stays one character per cell. New semantic entries:

| Char | Name | Category | Speed | Notes |
|---|---|---|---|---|
| `~` | Open water | blocking | — | connecting group `water` |
| `≈` | Shallows / ford | ground | **0.7** | the door through a river |
| `=` | Bridge | road | 1.2 | walkable over water; a route decision |
| `I` | Ice sheet | ground | **0.85** | walkable, slick; group `ice` |
| `^` | Cliff | blocking | — | connecting group `cliff`; replaces scree as the real wall |
| `,` | Marsh | ground | **0.6** | the doc's own example, finally real |
| `f` | Plowed farmland | ground | 1.0 | human territory dressing |
| `F` | Stubble field | ground | 1.0 | " |
| `x` | Corrupted ground | ground | 0.9 | Demonologist region |
| `X` | Charred ground | ground | 1.0 | battlefield / burnt sites |
| `R` | Stone ruins | ground | 0.9 | **telegraphs a site** — see §7 |
| `o` | Boulder field | ground | 0.8 | soft cover, not a wall |
| `O` | Boulder | blocking | — | single-cell obstacle |
| `T` | Dense forest | blocking | — | the third wall — see §6b; canopy drawn over it |
| `u` | Open woodland | ground | **0.85** | forest edges and carved corridors; sparse canopy |

**Marsh at 0.6 is the first sub-1.0 speed in the project.** `WorldMap.speed_multiplier()` returns the
float and `Necromancer.terrain_speed()` / `Roaming.step()` already multiply by it, so this needs **no
code change** — which is the R1 architecture paying off exactly as its write-up predicted. It does
have consequences for travel time; see §9.

`m` (Rocky scree) stays in the legend as decorative walkable ground rather than blocking, since `^`
is now the real wall. Scree-as-blocking was always the placeholder.

---

## 6. Water, and the doors through it

Rivers are the second wall, and they get the ridge's treatment.

- **A river is generated as a connected water path** from the northern range to the map edge, one to
  two cells wide, crossing the contested wilderness.
- **Every river gets 2–3 crossings**, and they are the whole point: a **bridge** on the human road
  network (fast, exposed — patrols will use it in R3) and a **ford** in the wilderness (slow, 0.7,
  unwatched). That is `WORLD_MAP_PLAN.md` §9's roads-vs-wilderness tradeoff expressed in terrain
  rather than in a speed number.
- **A crossing is never further than ~25 cells from another**, or the river stops being a route
  decision and starts being a detour tax.
- The two existing frozen lakes become `I` (walkable, slick) rather than blocking — **a frozen lake
  you can cross is a shortcut with a flavour of risk**; one you can't is just a hole in the map. If
  ice-breaking is ever wanted it is an R3+ hazard, not terrain.

---

## 6b. Forests — the wall, the paths, and the places inside

**Two semantic types, one asset family.**

- **`T` Dense forest** is **blocking**. Not slow, not spooky — impassable, exactly like the cliff,
  because a forest you can shuffle through at 0.5 speed is not a wall and creates no paths;
  it's a big marsh. The wall is what makes the gap mean something.
- **`u` Open woodland** is ground at **0.85** — the ragged edge every dense mass wears (1–3 cells
  deep), and the surface of every carved corridor. It exists so forests have a soft silhouette
  instead of a hedge-maze edge, and so walking the treeline reads differently from walking the
  open snow.

**The floor and the canopy.** `T` and `u` cells lay the marsh sheet's forest-floor tile as their
ground. The trees themselves are a **canopy layer**: `Pine_Tree.png` sprites scattered over
forest cells with deterministic per-cell jitter (hash the cell coordinate, same trick as
`_patch_pick` — never `randf` at load, or the forest reshuffles every boot). Density ~2 per `T`
cell, ~0.3 per `u` cell; scale jittered between **1.9 and 2.6 tiles of content height** (122–166px
via `Anchoring.scale_for_content_height`) so the canopy has depth. These are *bigger trees than
anything on the map today* — the lair's gatherable pines draw at 1.5 tiles, and §10 raises them
to 2.0 in the same pass so the two populations read as one species. World-canopy trees are
**pure paint**: no `ResourceNode`, no charges, not choppable, not inspectable, no per-tree node —
one `MultiMeshInstance2D` draws the whole canopy in one draw call (performance rules in §12).
If chopping a path through the world's forests is ever wanted, that is an R3+ mechanic with real
economy questions; it is not this pass.

**Corridors — trees create the paths.** 2–4 large dense masses are painted into the contested
wilderness and the northern belt (the wolf's "treeline" east of the lair valley finally becomes a
real place). The generator then carves **corridors**: 1–2 cell wide lanes of `u` cut through each
mass along cost-cheapest lines between its sides, the same A* the roads use. A corridor is *not*
a road — no speed bonus beyond `u`'s 0.85 being better than not existing, no signposting, no
patrol exposure. It is simply the way through, and finding it is navigation gameplay the open
snow can't offer. The wall-with-a-door rule (§1 goal 5) applies verbatim: **every dense mass
must be crossable, and no two corridor mouths on the same side further than ~25 cells apart** —
the river's own numbers, reused.

**Clearings — the isolated places.** Each large mass holds **1–2 interior clearings** (radius
2–4 of ordinary ground), connected to the outside *only* through a corridor. This is the map's
first genuinely isolated location type, and it is what the loot layer has been waiting for:
`LOOT_SITES_SPEC.md`'s wolf den lives in one, and ruin pockets, caches and the odd Band-3+ site
can too. A clearing satisfies "found, not followed" (§7) *structurally* — there is no line on the
ground because there is no ground until you're through the trees. Rules the generator enforces:
every clearing has **exactly one corridor mouth** (two makes it a crossroads, zero makes it a
softlock — flood-fill asserted, §12); no cobble or dirt path may enter a clearing (hard error,
same as §7's Band-4 rule); the lair band stays forest-free (`_clear_lair_band` learns `T`/`u`
alongside `m`/`i`).

**Roads and forests.** In the road A* cost grid (§8), dense forest is **∞** — human roads go
around the woods, which is both how real roads behave and what keeps every forest's interior
quiet. Open woodland costs 1.5: a road may clip a treeline, reluctantly. The one sanctioned
meeting point: a dirt track may end at a corridor *mouth* (a Band 1–2 signposted site inside the
woods is "the camp by the forest path"), but the track never continues inside.

**Decided: Band 4 sites get no paths. Found, not followed.**

| Tier | Tile | Leads to | Speed | Exposure (R3) |
|---|---|---|---|---|
| **Cobblestone** | `road_cobble` | village, manor, church, crossroads | 1.35 | High — patrols walk it |
| **Worn track / dirt** | `path_dirt` | Band 1–2 minor sites: camps, graves, shrines, the lair's own approach | 1.2 | Low |
| **Nothing** | — | **Band 3 cemetery excepted; all Band 4** | — | — |

Rules the generator enforces **by construction**, so nobody has to remember them:

1. The cobble network connects only entries in the `human_landmarks` list. Band 4 sites are not in
   that list and cannot be.
2. The dirt network connects only sites tagged `signposted: true` in `world_sites.json`, and the
   generator **refuses to signpost anything in Band 3 or 4** — a hard error at generation time, not
   a convention.
3. **The lair's worn track stays.** It already exists and it is the player's own approach, not a
   signpost to loot.
4. **Ruins terrain (`R`) is the exception that is not a path.** A collapsed ruin site sits on a patch
   of ruins tiles, so it reads as *something is here* from a distance without a line leading to it.
   That satisfies `LOOT_SITES_SPEC.md` §3's telegraphing without violating the no-paths rule —
   telegraphing is about what a site *is* once seen, not about being led there.

The design intent in one line: **the human world is legible and dangerous; the wild world is
findable and quiet; the deep world is neither.**

---

## 8. Generation rules

`tools/make_world_map.gd` (356 lines today) gains a road pass. The order matters:

```
1. base terrain      regions per WORLD_MAP_PLAN §4-§5, patch-hashed ground cover (R1, unchanged)
2. relief            cliff ranges with convex outlines; the central ridge keeps its two gaps
3. hydrology         river path + 2-3 crossing points reserved before any road is laid
4. forests           2-4 dense masses + open-woodland fringes, then corridors carved and
                     clearings reserved (§6b) -- before landmarks, so nothing human is ever
                     painted inside a wood by accident
5. landmarks         lair, crossroads, village core, manor, church, cemetery  (positions still fixed)
6. cobble network    A* between human landmarks over a cost grid
7. dirt network      A* from the cobble network to each signposted Band 1-2 site
8. dressing          farmland around the village, corrupted ground in the sealed region,
                     ruins patches under ruin sites, marsh in the Necromancer's lowlands
9. bake              write semantic characters to data/world_map.json rows
```

**The road A* cost grid** is what makes roads look deliberate rather than drawn with a ruler:

| Terrain | Cost | Effect |
|---|---|---|
| existing road | 0.5 | roads merge and share trunk sections — a *network*, not spokes |
| open ground | 1.0 | |
| open woodland | 1.5 | a road may clip a treeline, reluctantly |
| marsh / boulder field | 4.0 | roads route around bad ground, which is why real roads bend |
| cliff / **dense forest** | ∞ | roads never climb and never enter the woods; forest interiors stay quiet (§6b) |
| river cell | ∞ except at a reserved crossing | forces every road over the bridges hydrology already placed |

Step 6 running before step 7 is deliberate: the dirt tracks branch **off the cobble network** rather
than radiating from the lair, so the world reads as a human landscape the Necromancer is hiding
inside — which is the fiction (`ROGUELITE_REWORK.md` §0). Step 4 running before step 5 is the same
kind of load-bearing: forests are laid before anything human exists, so landmarks and roads treat
the woods as terrain to route around, never the reverse.

**Seed stays fixed.** Same layout every run. This pass changes *how* the layout is produced, not how
often. Re-run the generator and commit the JSON, exactly as now.

---

## 9. The travel-time risk — read this before running the prompt

R1's travel numbers were hard-won: `MOVE_SPEED_CELLS` 1.4 → 1.0, the ridge moved from x40 to x74,
its northern pass from y56–66 to y36–46, and the village core from x108 to x120 — four deliberate
changes to land every row of `WORLD_MAP_PLAN.md` §3 inside its band.

**Everything in this spec pushes those numbers up.** Marsh at 0.6, a river that must be crossed at a
bridge, cliffs that are genuinely impassable where scree was only decorative, dense forest that is a
third impassable mass with its own detours — each adds distance or time to routes that are currently
in band, and the village trip at 2m02s has only two minutes of headroom before it leaves §3's 2–4
minute window. Forests carry the extra risk of *stacking* with the ridge: a mass placed against the
ridge's flank quietly closes a route the ridge's gaps were tuned to leave open. Keep the masses off
the two pass approaches and off the lair track's line.

So the generation pass is **not done until `tools/measure_travel.tscn` is re-run and every row is
back in band.** If rows fall out, the knobs in priority order:

1. **River crossing placement** — move a bridge, not the village. Cheapest, most local.
2. **Forest mass placement and corridor mouths** — slide a mass off a main route, or add a
   corridor; forests are the newest arrival and the most movable.
3. **Marsh extent** — marsh is flavour with a speed cost; less of it on main routes.
4. **Cliff outlines** — widen a pass.
5. **Landmark positions** — last resort, and it means re-doing R1's tuning.
6. **Walk speed** — **not a knob.** It was tuned against the map crossing and the village trip and
   moving it breaks two rows to fix one. If the map has genuinely become too big, the honest fix is a
   smaller map, exactly as R1 concluded.

---

## 10. Code touchpoints

| Where | Change |
|---|---|
| `WorldMap.gd` | `TILESET_PATH` becomes `TILESET_PATHS` (a Dictionary, sheet id → path). `_build_atlas_texture()` loops sheets into one larger atlas (112 tiles, e.g. 8×14 at 64px) — the per-sheet slicing maths is unchanged, only the destination offset moves. New `_resolve_connections()` runs once after `_apply_data()`. `connection_group_at(cell)` for the mask. Still one `TileMapLayer`, still zero children. |
| `data/world_map.json` | `legend` gains §5's entries and an optional `group` per type; new top-level `connections` block (§4). `rows` stay one semantic char per cell. |
| `tools/make_world_map.gd` | §8's nine-step pipeline, forests included. The A* cost grid is the substantial new part; `AStarGrid2D` is already used in `measure_travel` so the pattern exists in-repo. |
| `data/world_sites.json` | `signposted: bool` per site, default false. The generator hard-errors if a Band 3–4 site sets it. |
| `tools/measure_travel.tscn` | Unchanged code, **mandatory re-run** (§9). |
| `tools/dump_atlas.gd` | **New, and run first.** Slices every sheet and writes a labelled PNG grid so §4's mask table can be filled from what is actually there. Keep it committed — every future sheet needs it. |
| New: canopy layer in `WorldMap.gd` | One `MultiMeshInstance2D` child drawing every world-canopy pine (§6b) from the `T`/`u` cells at load — deterministic per-cell jitter for position/scale, **zero per-tree nodes**. Sits above terrain, below units; the y-sort question is settled by fiat (canopy over blocking cells no unit can enter, so nothing is ever behind a tree it could be occluded by — put that in the header comment). |
| `ResourceField.gd` | `NODE_SIZE_TREE` 96 → **128** (1.5 → 2.0 tiles) and `NODE_SIZE_STUMP` proportionally (32 → 42), so the lair's gatherable pines are the same species as the canopy at a working size. `check_sprite_scales`' tree assertions update in the same commit — they re-derive, that is their job. |
| `Minimap.gd` | `minimap_color_at` samples the atlas, so new terrain colours come free — but the *canopy* is not in the atlas, so `T`'s minimap read comes from the forest-floor tile alone. Verify forest, water and cliff read distinctly at one pixel per cell; if forest floor reads as marsh, darken `T`'s sampled colour in code and comment why. |
| `docs/art/SPRITE_SPEC.md` | One line recording that terrain sheets are outside its rules (§2). |

---

## 11. How this feeds R4's shuffle

`WORLD_MAP_PLAN.md` §11 does not ask for procedural generation. It asks for **a consistent overall
map scale with shuffled contents**: rotate the manor, village, church and cemetery within a valid
human-territory template; shuffle roads, shortcuts, resource clusters, ruins and danger pockets;
choose a different subset of the encounter pool. That is a far more controllable thing than noise
procgen, and it is what protects the travel-time targets §9 is so anxious about.

After this spec, R4's shuffle is **a change to steps 4–5 only** (forest masses and landmarks).
Steps 6–9 already derive everything downstream from wherever those landed: move the village and
the roads follow it, the tracks re-branch, the farms move with it, corridors re-carve, and the
bitmask pass repaints every junction. Steps 1–3 stay fixed, which is what keeps every run
recognisably the same region. (Whether forests shuffle at all in R4's first pass is R4's call —
holding them fixed and shuffling landmarks alone is a legitimate v1.)

That is the entire argument for doing this now rather than after R2: hand-authoring 144 row strings
of roads is work that R4 would throw away.

**Still R4, not now:** per-run seeds, the valid-placement templates, encounter-pool subsetting, and
re-validating travel times across many seeds rather than one.

---

## 12. Verification and tunables

**Harnesses.** `tools/verify_terrain.tscn`, headless as a scene (not `-s`):

- every sheet slices at 5/8/305 — **asserted per file**, since one sheet measured a different outer
  border and assumption is how the atlas silently shifts
- the atlas contains 112 distinct tiles and no all-black cell (an all-black tile means a slicing
  off-by-one, and it is the failure this catches)
- every legend character resolves to a real atlas coord; every connection group has all 16 masks;
  a missing mask is a load error, not a fallback
- no road cell is orphaned (mask 0) except deliberate dead ends
- every road network is **connected**: A* finds a path from the lair to the village, manor, church
  and cemetery entirely on `road` cells
- **no path of any kind terminates within 3 cells of a Band 4 site** — the §7 rule, asserted
- every river has ≥2 crossings and no two crossings are >25 cells apart
- cliff ranges are convex (no inner-corner mask is ever requested)
- **flood fill from the lair reaches every walkable cell** — no forest mass, cliff line or river
  bend may seal off a region the generator didn't mean to seal; the only unreachable cells are
  inside blocking masses
- every dense mass is crossable, corridor mouths on a side ≤25 cells apart, and **every clearing
  has exactly one corridor mouth** (§6b) — zero is a softlock, two is a crossroads
- **every active site has a walkable cell within its own interaction reach that flood-fill-connects
  to the lair** *(added 2026-08-30)* — the flood fill above proves every walkable *cell* is
  reachable and the clearing rule proves every *clearing* has a mouth, but neither proved a **site**
  was standing anywhere the villain could get to; a site on a mountain or one cell outside its own
  clearing passed both
- **a clearing holding a site has a mouth ≥2 cells wide** *(added 2026-08-30)* — one cell is
  topologically a mouth and practically a wall: with the canopy over both sides a playtester walked
  the perimeter of the valley den and reported it "literally impossible to reach", and every
  assertion above passed, because it *was* reachable through a single 64px gap. A door nobody can
  find is not a door. Asserted only where a site is at stake; §6b's 1–2 cell lanes stand elsewhere
- no cobble or dirt cell inside a clearing or a dense mass (the §6b hard error, asserted)
- the canopy is **one MultiMeshInstance2D** — instance count within budget (~1.5× the `T`+`u`
  cell count), zero per-tree nodes
- **the draw-call budget is TERRAIN-ONLY**, measured by hiding everything that is not the terrain
  layer or the canopy. It is not "R1's 52 plus one": the whole-viewport count drew 52 at R1 and
  **71 on 2026-08-27**, and eighteen of that difference is UI added since (the combat-feedback
  label pool, the minimap's friendly dots, HUD additions) with **one** of it terrain. Gating
  terrain work on a number the HUD moves would mean trimming UI to make a terrain test pass,
  which is the wrong repair every time. The thing the budget protects is R1's trap — no node per
  cell — and one TileMapLayer plus one MultiMesh is what that looks like from the outside.
- still one `TileMapLayer`, still zero children, frame time no worse than R1's 1.3ms
- **`measure_travel` re-run, every row in band** (§9) — this is the gate, not a nice-to-have

**Needs a human:** whether roads actually *read* as leading somewhere at world zoom, and whether the
snowy road variants and the plain ones sit together without a visible seam.

**Tunables:** river width and crossing count; marsh extent and its 0.6; ford 0.7 and ice 0.85; the
A* cost weights in §8 (especially existing-road at 0.5, which is what decides whether roads merge
into a network or fan out as spokes); how large a ruins patch has to be before it reads as a
landmark rather than as rubble; forest mass count (2–4) and coverage (aim 8–14% of the map dense —
enough to shape routes, not enough to turn navigation into hedge-mazing); corridor width (1–2) and
`u` at 0.85; canopy density and the 1.9–2.6-tile scale band; clearing radius (2–4).

**Exit criterion:** starting at the Throne with no minimap, a player who follows the worn track out
of the lair reaches the cobble network, and following that reaches the village — while the crypt,
the outlaw cave and the cursed battlefield remain unmarked by any line on the ground. And the
forest half: a player who walks the treeline of a dense mass finds a corridor mouth inside 25
cells, and what is inside a clearing cannot be known — or reached — without walking the corridor.
