# Seven sheets, and roads that know their corners (P1)

`TERRAIN_SPEC.md` §2–§5, in two commits: `3b3fdc2` grew the atlas from one sheet to seven and
built `dump_atlas`; this one adds the connection layer and applies it. **No generation changes** —
the layout is the same cells in the same places. What moved is how they are rendered, plus two
semantic conversions the spec asked for.

## The dump comes first, and it earned its keep twice

`tools/dump_atlas.gd` slices every sheet with the geometry it *measures* for that file and writes a
labelled PNG of all 112 tiles, each stamped with the atlas coordinate the legend names it by.
TERRAIN_SPEC §2 makes reading it a rule, and R1 had already recorded why: *"a margin or separation
off by a few pixels shows up in the dump and nowhere else."*

It found the sheet the spec warned about. **`Terrain_Tileset_Road_Cobble.png` is not nominal** — it
carries a thick outer border, and sliced at margin 5 every one of its sixteen road pieces comes out
with a black frame around it. That is visible in the dump and invisible anywhere else.

Getting the *measurement* right took four attempts, and the three failures are recorded in
`WorldMap.measure_sheet_geometry`'s header because they are about the art rather than the code:
flat-column runs measured 8px gutters as 1, 2 and 7; scoring by mean gutter flatness picked a
gutter's flattest *middle* (0/2/312 on the snow sheet — a geometry R1 had disproved by hand);
requiring flatness and maximising separation drifted the other way, because a wider gutter always
fits inside a real one once its edges are trimmed. **Flatness is the wrong signal — art is often
flat too.** The gutter is the sheet's *background colour*, and that separates cleanly.

The second thing it earned: I tried to derive the mask tables from pixels and **could not**. Three
methods failed — comparing edges against the plain tile (defeated by per-cell snow scatter),
clustering edge colours (snow-on-grass is the same grey as cobble), comparing each edge to its own
tile's centre and corners. The tables in this commit come from `TERRAIN_MASKS.md`, read off the
sheets by hand. That was the right division of labour and the spec says so.

## Semantic in, connection out

`data/world_map.json`'s rows carry only what a cell **is** — `"C"` is cobble road, never "cobble
T-junction". What it *looks like* is derived once at load by `_resolve_connections()`, from a
4-bit mask of the four orthogonal neighbours. That is what keeps 112 tiles from becoming 112 legend
characters.

Two keys, deliberately different:

- **`group`** is connectivity. Cobble and dirt are both group `road`, so a track meeting a road
  forms a junction on both sides rather than two dead ends facing each other.
- **`draws`** is art. Cobble draws from `road_cobble`, dirt from `path_dirt`.

**A missing mask is a hard error**, never a fallback — a silently-wrong corner on one cell of
20,736 is the bug nobody ever finds. Which is also why all sixteen entries exist for every group
even where the art does not.

### The sheets are not complete 16-piece sets

`TERRAIN_MASKS.md`'s load-bearing finding. Missing pieces are supplied as `flip_h` / `flip_v` /
`transpose` of ones that exist — **23 of the 80 mask entries** carry a transform. Godot encodes
those as *alternative tiles*, and the transform bits **are** the alternative id
(`TRANSFORM_FLIP_H` is 4096), so `transform_id()` composing them with OR produces exactly the id
`_register_transforms()` created. All 784 alternatives are registered **once at build**, not per
cell — creating one inside the 20,736-cell resolve loop would allocate in the hot path and do it
repeatedly for the same tile.

**24 entries are marked approximations**, and the `≈` note travels into the JSON so nobody later
mistakes one for art that was drawn for that case. That is §4's 16-tile caveat in practice: water
and cliff are *shore/face* sets, not *line* sets, and a 4-bit orthogonal mask cannot say which side
the water is on.

### The JSON stores sheet cells, not atlas coordinates

A deliberate deviation from the prompt's example. Atlas coordinates are a function of the sheet
*order*, so storing them means every legend entry and all 80 mask entries silently repaint
themselves the day a sheet is inserted — which is exactly what happened when the atlas grew from
one sheet to seven and the generator's legend still held 4×4 coordinates. Storing `{"sheet": ...,
"cell": [row, col]}` makes the JSON diffable against `TERRAIN_MASKS.md` line by line and makes a
reorder a re-derivation. `WorldMap.atlas_coord_for_cell()` is the single conversion, and it is the
same arithmetic `dump_atlas` prints from.

## Applied to what already exists

- **The central ridge is a cliff.** Closes the one terrain placeholder R1 flagged. **Its two gaps
  are untouched** — a wall with a door is a route decision.
- **Both frozen lakes are walkable ice at 0.85**, with proper shore edges all round. A frozen lake
  you can cross is a shortcut; one you cannot is a hole in the map.
- The roads pick up real junctions and corners from their own sheets.

**Only the central ridge converts.** The map rim, the western range, the northern range and the
spur stay `m`, and **`m` stays blocking** — §5 retires scree to walkable decoration once cliffs are
the real wall, but *the rim is made of scree*, and a walkable rim is a hole in the world.
Converting the rest is a generation pass, which this is not.

Marsh (0.6), the ford (0.7) and ice (0.85) are the project's first sub-1.0 speeds and needed **no
code change** — `speed_multiplier()` already returned a float and everything multiplies by it,
exactly as R1's write-up predicted. Verified rather than assumed: the harness reads 0.85 back
through the same call the villain and the roamers use.

`T` and `u` are legend entries with a forest-floor tile and **zero cells using them**. The masses,
corridors and canopy are P2's, where generation lives.

## Travel: two rows moved, both still in band

| Journey | Before | After |
|---|---|---|
| lair → the village | 2m02s | **2m03s** |
| crossing the entire map | 3m20s, 167 cells | **3m14s, 154 cells** |

The crossing is 13 cells shorter because it now routes **across a frozen lake** — slower per cell
at 0.85, shorter overall, net six seconds faster. That is the shortcut the spec asked for, showing
up in the measurement. Every other row is unchanged and every row is in band.

## Performance: +1 draw call, and an honest note about the baseline

Still **one TileMapLayer with zero children**. The connection pass is one extra loop over 20,736
cells at load with four neighbour lookups each, and adds no nodes.

R1 measured **52 draw calls**. The scene now draws **70 before this pass and 71 after**, measured
by A/B with the terrain change stashed. So this pass costs **exactly one** draw call — the second
atlas page the flipped alternatives reference — and the other eighteen accumulated between R1 and
here (the combat-feedback label pool, the minimap's friendly dots, the HUD additions). Worth
knowing, worth watching, not something this pass caused or can fix.

**Frame time is not asserted.** A windowed run is vsync-bound, so wall-clock frame time reads
~16.6 ms whatever the game is doing — the first version of the check "failed" at 18.61 ms and was
measuring the display. The A/B showed process time identical to two decimal places with and without
the change. What guards R1's trap is structural, and that is what is asserted.

## Verification

`tools/verify_terrain.tscn`, **229 assertions, all passing** (windowed; 228 headless, where the
draw-call gate is skipped because headless draws nothing).

Per-file slicing that spans each sheet exactly; 112 distinct atlas tiles with none all-black and no
duplicate fingerprints; every legend character resolving to a real sheet and a coordinate inside
the atlas; all five connection tables carrying all sixteen masks; **every mask entry's tile inside
the atlas and every transform resolving to a registered alternative**; the ridge's two designed
gaps still open with the wall between them intact; no orphaned road cell; the ice convex enough for
the art; the speeds reading back through the real call; one TileMapLayer, zero children.

Three notes the harness prints rather than fails on, each a real finding:

- **`road_cobble` (18/10/297) and `path_dirt` (9/8/303) are not nominal.** The first is the sheet
  with the black frame; the second differs by a few pixels and slices cleanly either way.
- **8 cliff cells request an inner-corner mask.** §4 permits faces and outer corners only. They
  draw the declared `≈` approximation.
- **8 ice cells fall back to an `≈`.** `TERRAIN_MASKS.md` predicts convex lakes "never produce
  these"; they do, a little — an ellipse's extreme cells have one orthogonal neighbour, so each
  lake's left and right tips ask for a stub. Invisible in the capture: they draw the plain ice
  sheet, which is what an ellipse tip should look like anyway.

Also green: `measure_travel` (above), `verify_stats` 505/505, `check_sprite_scales` 40/40,
`check_fog_and_minimap` 41/41, `verify_combat_feedback` 31/31, headless boot clean.

## The flake in verify_combat_feedback: the harness, not the game

About one run in three failed on *"a throne and a worker exist for the repair test"*. Instrumenting
it showed `workers=0` — **the roster was empty**.

The cause: the harness called `Wolf.depart()`, a raw state setter, and then waited up to 600 frames
for `is_fighting()` to go false. But `depart()` does not end an engagement —
`CombatSystem._advance_engagement` keeps running an exchange every 1.5s until the wolf despawns or
its defender dies. So the wait was ten seconds of the wolf still biting, which killed the skeleton
it was fighting and then the next one, until the roster was empty by the time the Throne-repair
test asked for a worker.

**The harness was wrong and the game was not changed.** A wolf told to leave while its teeth are in
something does keep biting for a moment, and in play that state is only ever reached *through*
`should_flee()` or dawn — both of which finish the engagement on the spot. The harness now drops
the wolf below `FLEE_BELOW_HP` and lets the game's own path end the fight, which is the only way it
ends in play. 8 runs, 8 clean.

## Needs a human

Whether roads actually *read* as leading somewhere at world zoom, and whether the snowy road
variants sit against the plain ones without a visible seam.

And one thing worth a designer's eye: **the ridge is seven cells thick, and `TERRAIN_MASKS.md`'s
cliff table was authored for a one-cell ridge** ("for a 1-cell-thick ridge that is what you want on
the south face"). Every interior cell of a 7-wide ridge has all four neighbours as cliff — mask 15,
which the table maps to the lone crag as an `≈`. The result is a legible wall, but a repeating one:
each cell draws its own south face, so the band reads as a grid rather than as a plateau. Mapping
mask 15 to a plain snow tile would fix it in one line; that is a design call about the table, not a
code change, so it is flagged rather than made.
