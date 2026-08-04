# World Map Scale and Exploration Plan

**Warlords — Necromancer, Demonologist, and Human Lordship: initial roguelite map.**

> Converted from `Warlords_World_Map_Scale_and_Exploration_Plan.docx` (user-authored, 2026-08-03) so Claude Code can read it — the .docx is the original and stays in the repo alongside this file. Content is unchanged apart from formatting; the ASCII layout sketch in §4 was rebuilt as a code block after the table conversion mangled it.

> **Core recommendation.** Begin with a 144 x 144 cell map. Keep the world compact and dense, use fog of war, and target a 3-5 minute uninterrupted crossing time. Replayability should come from shuffled locations, encounters, resources, and faction starting positions rather than a huge empty world.

> **Adopted with three amendments** — see `ROGUELITE_REWORK.md` §4, which supersedes this document where they disagree:
>
> 1. **The Demonologist's region ships sealed.** The 20x20 territory stays in the template so the layout never needs rework, but v1 places a dormant/sealed ritual ground there — no AI rival. (Affects §4, §5, §6 Band 3, §11.)
> 2. **The village is static in v1.** No homes/market/inn routines; static buildings plus one or two scripted patrol loops. (Affects §5's "Dense village core" purpose line.)
> 3. **Scouting is passive, not directed.** The "8-12 cells per scouting action" model in §8 and §12 is replaced by the passive Raven ping system (`ROGUELITE_REWORK.md` §6). Fog clears primarily through the Necromancer's own travel.

---

## 1. Design Goal

The first map should feel dangerous, mysterious, and worth exploring without becoming exhausting. The player must have enough space to hide, scout, take risks, and discover other powers, but travel should remain short enough that permadeath feels like the result of a decision rather than lost time.

The map is not a kingdom-sized continent. It is a contained regional lordship: one human estate and village surrounded by unsettled wilderness, with the Necromancer and Demonologist hidden somewhere beyond the lord's effective control.

## 2. Recommended Map Size

Primary target: 144 x 144 cells.

Practical lower bound: 128 x 128 cells.

Practical upper bound for the first complete version: 160 x 160 cells.

A larger map should only be considered after movement speed, encounter density, scouting range, and expedition pacing have been tested in real play sessions.

## 3. Travel-Time Targets

Travel time is a better measure than cell count. These targets assume uninterrupted movement before encounters, combat, scouting, or detours are added.

| Journey | Target Time |
|---|---|
| Lair to nearby resource | 10-20 seconds |
| Lair to first worthwhile encounter | 20-40 seconds |
| Lair to edge of local territory | 45-75 seconds |
| One villain lair to the other | 2-4 minutes |
| Villain lair to the human village | 2-4 minutes |
| Crossing the entire map | 3-5 minutes |

## 4. Overall Map Structure

The three powers should not be placed in a perfectly even triangle. The human road network should organize the map, while both villains begin in rougher terrain outside regular patrol coverage.

```
                    Northern Wilderness
              Ruins - graves - beasts - old shrine

Necromancer Territory     Old Road     Human Farms
forest / marsh                |              |
                              Crossroads - Village
Demonologist Territory        |          Lord's Manor
corrupted woods / ruins       |              |
                       Church and Cemetery
                          Southern Road
```

## 5. Region Allocation

| Region | Approximate Footprint | Purpose |
|---|---|---|
| Human lordship | 35 x 45 cells | Manor, village, farms, church, cemetery, roads, patrol space |
| Dense village core | 18 x 22 cells | Homes, market, trades, inn, and village routines |
| Necromancer starting region | About 20 x 20 cells | Hidden lair, nearby gathering, low-risk discoveries |
| Demonologist starting region | About 20 x 20 cells | Ruined ritual ground, corrupted terrain, summoning resources |
| Contested wilderness | Largest shared region | Encounters, ruins, monsters, clues, moving groups, and high-value sites |

## 6. Exploration and Danger Bands

### Band 1 - Lair Surroundings

The safest region, roughly 15-20 cells around a starting lair. It teaches gathering, scouting, retreat, and basic encounters.

Typical content: Basic resources, weak animals, one or two graves or ritual sites, and introductory discoveries.

### Band 2 - Contested Wilderness

The main exploration zone. Most expeditions and random stories should occur here.

Typical content: Ruins, wounded recruits, camps, monsters, valuable graves, human travelers, and signs of the rival villain.

### Band 3 - Faction Influence

Areas close to the manor, village, church, or rival lair. These regions are more organized, defended, and consequential.

Typical content: Guard patrols, priests, rival scouts, defended resources, and high-value opportunities.

### Band 4 - Deep-Danger Pockets

Small high-risk locations placed throughout the map rather than only at the edge.

Typical content: Cursed battlefield, ancient crypt, demon breach, sealed ruin, outlaw cave, or haunted forest.

## 7. Content Density for a 144 x 144 Map

- 3 primary faction locations
- 8-12 permanent minor locations
- 12-20 possible encounter sites
- 6-10 resource clusters
- 3-5 dangerous lairs or ruins
- 2-4 roads or trails
- Several hidden shortcuts and alternate routes
- Moving groups such as patrols, travelers, monsters, scouts, and bounty parties

Not every possible location should activate in every run. A run may choose only part of the available encounter pool, while unused sites remain empty, become resource nodes, or activate later.

## 8. Fog of War and Scouting

At the beginning, the player should know only the lair, immediate terrain, a few nearby resources, and perhaps a vague direction toward human activity. Exact enemy locations should remain hidden.

- The exact manor and village layout
- The church and cemetery
- The rival villain's lair
- Major ruins and dangerous pockets
- Guarded roads and patrol routes
- High-value resource sites

The raven or demon familiar should reveal an area of approximately 8-12 cells per successful scouting action. Early scouting may reveal clues rather than complete information, such as smoke, maintained roads, patrol colors, graves, unusual winged shapes, or corrupted terrain.

## 9. Making Travel Dangerous Without Making It Tedious

Danger should come from choices, encounters, and changing conditions rather than frequent unavoidable damage during empty travel.

- Roads are faster but increase exposure to guards, travelers, and witnesses.
- Wilderness routes are slower but offer concealment and unexpected discoveries.
- Nightfall, injuries, heavy loot, and pursuit can change a safe return journey into a crisis.
- Danger should be telegraphed enough that scouting and retreat remain meaningful.
- Distant areas should offer clearly better opportunities to justify the additional risk.
- The player should rarely die during uneventful movement; failure should follow an encounter, pursuit, or deliberate gamble.

## 10. How the Map Escalates During a Run

The world becomes more dangerous over time without expanding physically.

Early run: The villains are hidden, humans assume local problems are caused by animals or criminals, and most roads are lightly watched.

Middle run: The human estate notices patterns, the church investigates supernatural activity, patrols increase, and each villain begins finding clues about the other.

Late run: Faction parties cross the same routes, roads become contested, the human lordship fortifies, and the villains must choose alliance, avoidance, sabotage, or war.

## 11. Roguelite Replayability

Use a consistent overall map scale with shuffled contents. Players should learn the world's rules without memorizing the solution to each run.

- Change villain starting regions and approach routes.
- Rotate or relocate the manor, village, church, and cemetery within a valid human territory template.
- Shuffle roads, shortcuts, resource clusters, ruins, and danger pockets.
- Choose a different subset of encounter sites for each run.
- Change which clues reveal the rival villain and which human routes become important.
- Allow weather, patrol schedules, and moving groups to create different risks even on similar terrain.

## 12. Initial Build Recommendation

| Map size | 144 x 144 cells |
|---|---|
| Cross-map travel | 3-5 minutes uninterrupted |
| Human territory | Approximately 35 x 45 cells |
| Villain starting territories | Approximately 20 x 20 cells each |
| Scouting reveal radius | Approximately 8-12 cells |
| Active meaningful locations | Roughly 10-15 per run |
| World structure | One human lordship, two hidden villains, broad contested wilderness |
| Replayability model | Fixed scale with shuffled faction positions, routes, resources, and encounters |

Design Principle: Compact, dense, partially unknown, and increasingly contested.
