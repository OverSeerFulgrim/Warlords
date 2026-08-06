# Terrain expansion concepts

These 1254 x 1254 concept atlases were generated against
`Official Sprites/Terrain_Tileset_Snow.png` as the style, scale, palette, and
camera reference. They are intentionally **not connected to `WorldMap` yet**.

## Route candidates

- `terrain_dirt_paths_16mask_candidate_v1.png`
- `terrain_cobblestone_roads_16mask_candidate_v1.png`

Each route atlas contains the complete visual vocabulary for a four-neighbour
route: empty ground, four endpoints, two straights, four corners, four
T-junctions, and a crossroads. Image generation did not preserve the requested
compass ordering perfectly, so the cells must be identified and reordered
before they become runtime atlases. Edge width is visually consistent.

`terrain_routes_concept_v1.png` is the earlier mixed-material exploration sheet
and should not be treated as an autotile candidate.

## Regional ground concepts

`terrain_regions_concept_v1.png` is arranged by terrain family:

1. Marsh, bog, blackwater, reeds, and muddy hummocks
2. Winter forest floor, roots, leaf litter, moss, and snow remnants
3. Dormant grassland, trampled plains, tilled soil, and crop stubble
4. Scorched earth, cracked soil, corruption, and ritual-scarred ground

## Water and crossings

`terrain_water_crossings_concept_v1.png` explores deep water, shallows, ice,
cracked ice, shorelines, a stream, a ford, wooden bridges, and frozen banks.
It is a visual vocabulary sheet, not yet a complete shoreline autotile set.

## Natural barriers

`terrain_barriers_concept_v1.png` explores scree, boulders, berms, cliffs,
rubble, collapsed masonry, and burned stumps. Cliff topology and prop-like
obstacles should be separated before runtime use.

## Next production step

Slice selected cells to the game's 64 px tile size, normalize their ordering,
verify seams in a repeated test map, then extend the terrain legend and movement
values. Keep the current live atlas unchanged until those checks pass.
