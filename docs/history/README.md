# Development history

The narrative that used to live in `CLAUDE.md` (137KB, loaded into every session). Carved out
verbatim on 2026-08-05 — nothing was summarised or dropped, only split at the file's own section
headings. Read the one file that covers the system you're touching.

Newest at the bottom; the order below is the order the passes happened in.

| File | Sections it holds |
|---|---|
| [2026-08-pre-slim-orientation.md](2026-08-pre-slim-orientation.md) | The pre-slim head of CLAUDE.md: What this is · Current phase · Engine & tooling · Known constraint · Architecture conventions (intro) |
| [2026-07-early-passes.md](2026-07-early-passes.md) | Buildings, housing, and the main building · Worker economy: the original flat-tick version · The "small test space": the Keep-click menu |
| [2026-07-foundation-reset.md](2026-07-foundation-reset.md) | Foundation reset: back to Stages 1–3 |
| [2026-07-physical-gathering.md](2026-07-physical-gathering.md) | Physical gathering: the trip loop, resource nodes, and the priority list |
| [2026-07-day-night-cycle.md](2026-07-day-night-cycle.md) | Day/night, finished — tint, clock readout, and the debug time scale |
| [2026-08-art-provenance.md](2026-08-art-provenance.md) | Art provenance — what's commissioned and what's still placeholder (incl. sizing, anchoring, filtering, the three measurement tools) |
| [2026-08-deer-and-wolf-sprites.md](2026-08-deer-and-wolf-sprites.md) | The deer sprite (and the wolf) — the generated placeholders |
| [2026-08-stage3-barracks-and-recruits.md](2026-08-stage3-barracks-and-recruits.md) | Stage 3: the Barracks, and recruits who are actually individuals (incl. `RecruitGenerator`, the `Laborer` base class) |
| [2026-08-meals-morale-and-housing.md](2026-08-meals-morale-and-housing.md) | Meals, morale, desertion, and fund-a-house |
| [2026-08-camera-and-necromancer-avatar.md](2026-08-camera-and-necromancer-avatar.md) | Camera framing and the Necromancer avatar (Core Feel Prompt A) |
| [2026-08-inspection-panel.md](2026-08-inspection-panel.md) | One panel for everything clickable — `InspectionPanel` and the `get_inspect_data()` contract (Core Feel Prompt B) |
| [2026-08-combat-and-wolf.md](2026-08-combat-and-wolf.md) | Combat: the minimal primitive, and the wolf (Core Feel Prompt C) |
| [2026-08-command-undead.md](2026-08-command-undead.md) | Command Undead — the Necromancer's first spell |
| [2026-08-hud-layering-and-playtest-bugs.md](2026-08-hud-layering-and-playtest-bugs.md) | HUD layering, and four playtest bugs worth remembering |
| [2026-08-villain-split.md](2026-08-villain-split.md) | The villain splits: data object, direct control, and a camera that follows (rework R1, first task) |
| [2026-08-world-map-r1.md](2026-08-world-map-r1.md) | The world the Necromancer walks (rework R1: the 144×144 map, fog, terrain) |
| [2026-08-world-population-r1.md](2026-08-world-population-r1.md) | Populating the world, and tuning it to the clock (rework R1, second half) |
| [2026-08-foundation-exit-criteria.md](2026-08-foundation-exit-criteria.md) | Foundation exit criteria (manual playtest checklist) and the known gaps against it |
| [2026-08-pre-slim-file-map-and-backlog.md](2026-08-pre-slim-file-map-and-backlog.md) | The pre-slim File map and the "Next milestones (not yet built)" backlog |
| [2026-08-27-u2-input-and-visibility.md](2026-08-27-u2-input-and-visibility.md) | Four input and visibility fixes from the R1 playtest: minimap clicks, right-click-to-move, friendly units lighting fog, friendly dots (prompt U2) |
| [2026-08-combat-feedback.md](2026-08-combat-feedback.md) | Red numbers, in real time — pooled floating damage numbers over every combatant (COMBAT_FEEDBACK_SPEC) |
| [2026-08-stat-rework.md](2026-08-stat-rework.md) | The stat rework: one Might becomes nine attributes, workbook-exported roster, attack profiles (COMBAT_SPEC slice C2) |
| [2026-08-terrain-tiles.md](2026-08-terrain-tiles.md) | Seven sheets, and roads that know their corners — the seven-sheet atlas, connection tiles with flip/transpose, cliff ridge and walkable ice (P1) |
| [2026-08-generated-world.md](2026-08-generated-world.md) | The world stops being drawn and starts being generated — the nine-step pipeline, forests and their clearings, a river with doors, roads by A* (P1 final) |
| [2026-08-loot-sites.md](2026-08-loot-sites.md) | The world becomes worth walking into — fifteen lootable sites, channelled looting and the grave choice sheet, loot tables/relics/gold, remainder charges, wolf dens and the dusk gate, deeds vs notice, Dark Essence finished moving to field-only (R2a) |

New session write-ups go here as `YYYY-MM-topic.md`, never back into `CLAUDE.md`.
