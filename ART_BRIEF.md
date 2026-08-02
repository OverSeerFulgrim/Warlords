# Art Brief — Undead Empire (working title)

Commission brief for replacing placeholder art. Written to be sent to an artist mostly as-is; bracketed notes are for us, cut them before sending.

---

## The game in two sentences

A villain-power-fantasy settlement builder: the player is a Necromancer growing a hidden settlement of skeletons, orcs, goblins, and worse, in a cold forested mountain hideout, until the "good" nations march on them. Think *Against the Storm* / *RimWorld* structure, but you're the monster the villagers whisper about.

## Art direction

- **Tone: bright villainy, not grimdark.** Stylized, colorful, readable, a little funny. The skeletons are workers with jobs, not horror props. Macabre subjects (bone piles, graves, corpse-hauling) drawn with charm — closer to *The Nightmare Before Christmas* than *Diablo*.
- **Setting:** cold, remote, forested/mountainous hideout (Alps/Alaska feel) — pines, snow-dusted ground, grey stone. Not a barren wasteland.
- **Readability first.** This is a top-down management game; every sprite must be identifiable at a glance at gameplay zoom. Silhouette over detail.
- **Night pass:** the game tints the whole scene toward blue at night (multiply toward RGB 0.52, 0.58, 0.82). Sprites must stay readable under that tint — avoid relying on dark blues/purples for key details.

## Technical specs

- **Style: pixel art.**
- **Grid cell: 64×64 px.** Buildings are currently one cell (multi-cell footprints come later — see asset list for which buildings should be designed with a larger version in mind).
- **Character map tokens: 32×32 px** (workers/recruits walking around the map).
- **Character portraits: 128×128 px** (roster UI, event popups).
- **Resource/UI icons: 32×32 px.**
- Transparent background PNGs, no baked-in drop shadows (engine handles depth), consistent palette and light direction (top-left) across the set.
- Deliver individual PNGs, not packed sheets.

---

## Asset list, in priority batches

### Batch 1 — the settlement core (highest priority)

| Asset | Size | Notes |
|---|---|---|
| Throne of Bones | 64×64 | The player's home and the thing enemies attack. Should read as *the* centerpiece — a dark throne/keep built of bone and stone. Design a 128×128 (2×2 cell) version too if budget allows; it will become multi-cell later. |
| Barracks | 64×64 | Rough-and-ready intake housing for new recruits. Communal, bunkhouse feel. Needs 2–3 upgrade-tier variants later; design tier 1 so it can visibly grow. |
| Bone Pile | 64×64 | Resource building. A worked charnel heap — organized, not gory. |
| Workshop | 64×64 | Mundane crafting hall. |
| Blacksmith | 64×64 | Forge glow, anvil. |
| Dark Altar | 64×64 | Where bodies become Dark Essence and spells get upgraded. The most overtly magical building — green/purple ritual glow reads well under night tint. |
| Ground tile set | 64×64 | Snow-dusted grass/dirt/stone terrain tiles + a road/path tile. Small set (6–10 tiles) is fine. |

### Batch 2 — resource nodes (the map's furniture)

Each needs a **full** and **depleted** state — depletion is a core mechanic the player reads at a glance.

| Asset | Size | States |
|---|---|---|
| Pine tree | 64×64 | full / stump |
| Stone deposit | 64×64 | full / worked-out rubble |
| Berry grove | 64×64 | full / picked-bare (it regrows, so "bare" not "destroyed") |
| Grave | 64×64 | undisturbed / dug-up |
| Animal carcass | 32×32 | intact / picked-clean bones |
| Deer | 32×32 | alive (side view, 2-frame walk if possible) — no corpse sprite needed; it's hauled off whole |

### Batch 3 — characters

Map tokens (32×32) and portraits (128×128) for each. Tokens matter more than portraits for gameplay; portraits can come later or batch-by-batch.

Priority order: **Skeleton Worker** (the player sees dozens of these — 2-frame walk cycle, and a "carrying" variant with a bundle on its back), **the Necromancer** (player avatar: hooded, pale, dark robe with a wicked accent color), then the recruitable races:

Orc, Goblin, Gnome, Gray Dwarf, Ogre, Minotaur, Gnoll, Kobold, Hobgoblin, Dark Elf, Troll, Mountain Dwarf, High Elf, Halfling, Human Outcast.

[Per-race one-line descriptions and stat-personality live in RACES.md — paste the relevant rows into the artist thread when commissioning each batch. Key art notes: each race's silhouette must be distinct at 32px; good-aligned races (Mountain Dwarf, High Elf, Halfling) should look *slightly* out of place among the monsters — cleaner, brighter — that contrast is a story beat.]

### Batch 4 — race housing (after Prompt-5 systems exist)

One 64×64 house per housing style, not per race (race-tinted variants can be palette swaps):

| Style | Feel |
|---|---|
| Clustered hut (Goblin/Kobold/Gnoll/Halfling) | Small, round, crooked, cozy — designed to look good tiled next to its siblings |
| Communal lodge (Orc/Hobgoblin/Human) | Sturdy longhouse |
| Spaced homestead (Ogre/Troll/Minotaur) | Big, heavy, standalone |
| Dug-in stonework (Dwarves) | Built into rock face |
| Elegant spire (Elves) | Slender, slightly aloof |

### Batch 5 — UI icons (32×32)

Wood, Stone, Bones, Food, Dark Essence, Power, Threat, morale (happy/neutral/angry), a "exceptional recruit" star/skull marker, day/night phase icons (sun/moon).

---

## Reference material to send along

- Screenshot of the current game (shows scale, layout, and the night tint).
- Kenney "Roguelike/RPG pack" — current placeholder style; we want the same readability at higher charm.
- Tone references: *Cult of the Lamb* (cute-macabre), *Against the Storm* (readable top-down settlement), *The Nightmare Before Christmas* (friendly spooky).

## What we don't need yet

Animations beyond 2-frame walks, combat effects, spell VFX, UI frames/panels (debug UI is being replaced later), climate variants, other villain classes' assets.
