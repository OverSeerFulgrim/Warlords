# Terrain connection masks — read off the sheets 2026-08-27

Read by the designer's assistant from the raw sheets (edge-band colour classification, then every
ambiguous tile checked by eye at 3×). Coordinates are **sheet (row, col), 0-indexed, top-left
origin** — convert to atlas coords with `dump_atlas`'s printed "sheet row,col = atlas x,y" table.
Mask = N·1 | E·2 | S·4 | W·8 per TERRAIN_SPEC §4.

**Load-bearing finding:** none of the four sheets is a complete 16-piece set. Cobble and dirt each
carry duplicates and lack 4–5 masks; every missing piece is the mirror of one that exists, so the
table below uses `flip_h` / `flip_v` / `transpose` (TileMapLayer alternative-tile transforms) rather
than art that isn't there. Water and cliff are *shore/face* sets, not *line* sets — a 4-bit
orthogonal mask cannot say which side the water or plateau is on, so a handful of masks are
approximations, all marked `≈`. Every group has all 16 entries; the hard-error rule stands.

## road_cobble (group `road`, cobble cells)

| mask | piece | sheet (r,c) | transform |
|---|---|---|---|
| 0 | isolated | (0,1) | ≈ stub; isolated road cells should not be generated |
| 1 | N stub | (0,1) | flip_v |
| 2 | E stub | (2,0) | |
| 3 | N+E corner | (2,1) | flip_h |
| 4 | S stub | (0,1) | |
| 5 | N–S straight | (1,1) | |
| 6 | E+S corner | (1,2) | flip_h |
| 7 | N+E+S tee | (3,1) | flip_h |
| 8 | W stub | (0,2) | |
| 9 | N+W corner | (2,1) | |
| 10 | E–W straight | (2,2) | |
| 11 | N+E+W tee | (2,3) | |
| 12 | S+W corner | (1,2) | |
| 13 | N+S+W tee | (3,1) | |
| 14 | E+S+W tee | (2,3) | flip_v |
| 15 | cross | (1,3) | (3,2) and (3,3) are variants — use for visual variety if wanted |

Unused / duplicates: (0,0) plain grass; (0,3) S stub with a short E bump (do not use — it reads as
a corner but the arm does not reach the edge); (1,0) S stub dup; (3,0) S+W dup.

## path_dirt (group `road`, dirt-track cells)

| mask | piece | sheet (r,c) | transform |
|---|---|---|---|
| 0 | isolated | (2,1) | a dirt patch touching no edge — exactly right |
| 1 | N stub | (1,0) | |
| 2 | E stub | (0,2) | flip_h |
| 3 | N+E corner | (1,2) | flip_v |
| 4 | S stub | (0,1) | |
| 5 | N–S straight | (1,1) | |
| 6 | E+S corner | (1,2) | |
| 7 | N+E+S tee | (1,3) | |
| 8 | W stub | (0,2) | |
| 9 | N+W corner | (0,3) | flip_v |
| 10 | E–W straight | (2,2) | |
| 11 | N+E+W tee | (2,3) | |
| 12 | S+W corner | (0,3) | |
| 13 | N+S+W tee | (3,1) | |
| 14 | E+S+W tee | (2,3) | flip_v |
| 15 | cross | (3,2) | (3,3) variant |

Unused / duplicates: (0,0) plain grass; (2,0) W stub dup; (3,0) S+W dup.

## water_ice — group `water` (mask bit set = neighbour is water)

Non-connection tiles on this sheet: (0,1) shallows/ford `≈`; (0,2) ice sheet `I` (full);
(0,3) cracked ice (I variant); (2,1) river ford `≈` (N–S river); (2,2) bridge over a N–S river,
crossing E–W; (2,3) bridge over an E–W river, crossing N–S — legend `=` picks by the river's axis.

| mask | meaning | sheet (r,c) | transform |
|---|---|---|---|
| 15 | open water | (0,0) | |
| 14 | shore on N | (1,0) | |
| 11 | shore on S | (1,0) | flip_v |
| 7 | shore on W | (1,1) | |
| 13 | shore on E | (1,1) | flip_h |
| 6 | shore N+W | (1,2) | |
| 12 | shore N+E | (1,3) | |
| 3 | shore S+W | (1,2) | flip_v |
| 9 | shore S+E | (1,3) | flip_v |
| 5 | river N–S | (2,0) | |
| 10 | river E–W | (2,0) | transpose |
| 1, 4 | river stub N / S | (2,0) | ≈ river runs off the map edge, so the straight is right |
| 2, 8 | river stub E / W | (2,0) | transpose ≈ same |
| 0 | isolated pool | (3,3) | ≈ no all-round shore exists; do not generate single water cells |

(3,3) is a second N+W shore variant with a wider curve; (3,0)–(3,2) are the ice shores below.

## water_ice — group `ice` (mask bit set = neighbour is ice)

| mask | meaning | sheet (r,c) | transform |
|---|---|---|---|
| 15 | ice sheet | (0,2) | (0,3) cracked variant |
| 14 | shore on N | (3,0) | |
| 11 | shore on S | (3,0) | flip_v |
| 7 | shore on W | (3,1) | |
| 13 | shore on E | (3,1) | flip_h |
| 6 | shore N+W | (3,2) | |
| 12 | shore N+E | (3,2) | flip_h |
| 3 | shore S+W | (3,2) | flip_v |
| 9 | shore S+E | (3,2) | flip_h + flip_v |
| 5, 10, 0, 1, 2, 4, 8 | channels / stubs / isolated | (0,2) | ≈ no ice-channel art; frozen lakes are convex blobs and never produce these |

## rock_ruins — group `cliff` (mask bit set = neighbour is cliff)

Non-connection tiles: (0,0) boulder field `o`; (0,1) scattered rocks (o variant); (0,2) boulder `O`;
(0,3) fallen log; (2,2) rubble; (2,3) ruin heap; (3,0) paved ruin floor `R`; (3,1) ruin walls `R`;
(3,2) broken wall + log (R variant); (3,3) burnt ground with stumps `X`.

The art draws cliff faces on the **south and inner sides of a snow plateau**. For a 1-cell-thick
ridge that is what you want on the south face; the north face reads as snow meeting snow, which is
acceptable and is the TERRAIN_SPEC §4 "16 tiles, convex only" caveat in practice.

| mask | meaning | sheet (r,c) | transform |
|---|---|---|---|
| 0 | lone crag | (1,0) | isolated plateau — perfect |
| 10 | E–W ridge (face S) | (1,1) | |
| 5 | N–S ridge (face E) | (1,2) | (1,3) is the face-W mirror; use it when the plateau is east |
| 9 | N+W corner | (2,0) | |
| 3 | N+E corner | (2,1) | |
| 12 | S+W corner | (2,0) | flip_v ≈ |
| 6 | E+S corner | (2,1) | flip_v ≈ |
| 2, 8 | ridge end, E / W | (1,1) | ≈ face continues; ends are the ridge's two gaps |
| 1, 4 | ridge end, N / S | (1,2) | ≈ |
| 11, 14 | tees with E+W | (1,1) | ≈ |
| 7, 13 | tees with N+S | (1,2) | ≈ |
| 15 | cross | (1,0) | ≈ |

## Sheets not tabulated

`roads_snow` and `marsh_corrupt` hold no connection groups in P1 (winter road variants and
semantic ground: marsh `,`, farmland `f`/`F`, corrupted `x`, charred `X`). Assign those by eye from
the dump; a wrong pick there is a visible cosmetic, not a silent junction error.
