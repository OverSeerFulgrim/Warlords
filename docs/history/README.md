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
| [2026-08-27-r1-playtest-notes.md](2026-08-27-r1-playtest-notes.md) | The R1 feel playtest: exit criteria ticked, notes and decisions, and the U1 prompt it produced |
| [2026-08-27-u2-input-and-visibility.md](2026-08-27-u2-input-and-visibility.md) | Four input and visibility fixes from the R1 playtest: minimap clicks, right-click-to-move, friendly units lighting fog, friendly dots (the file calls it prompt U2; `R2_PROMPTS.md` names it **U1**) |
| [2026-08-combat-feedback.md](2026-08-combat-feedback.md) | Red numbers, in real time — pooled floating damage numbers over every combatant (COMBAT_FEEDBACK_SPEC) |
| [2026-08-stat-rework.md](2026-08-stat-rework.md) | The stat rework: one Might becomes nine attributes, workbook-exported roster, attack profiles (COMBAT_SPEC slice C2) |
| [2026-08-terrain-tiles.md](2026-08-terrain-tiles.md) | Seven sheets, and roads that know their corners — the seven-sheet atlas, connection tiles with flip/transpose, cliff ridge and walkable ice (P1) |
| [2026-08-generated-world.md](2026-08-generated-world.md) | The world stops being drawn and starts being generated — the nine-step pipeline, forests and their clearings, a river with doors, roads by A* (P1 final) |
| [2026-08-29-r2-spec-review-agenda.md](2026-08-29-r2-spec-review-agenda.md) | The designer's agenda for the seven-spec R2 review (moved from `docs/` 2026-09-26; the items still open are carried in `docs/REVIEW_2026-09-26.md` §7) |
| [2026-08-loot-sites.md](2026-08-loot-sites.md) | The world becomes worth walking into — fifteen lootable sites, channelled looting and the grave choice sheet, loot tables/relics/gold, remainder charges, wolf dens and the dusk gate, deeds vs notice, Dark Essence finished moving to field-only (R2a) · **plus the 2026-08-30 playtest fixes**: the silently-refused Collect, and raising a corpse you can actually see |
| [2026-08-villain-combat.md](2026-08-villain-combat.md) | His own two hands — engage close / cast far with no attack button, the lair aura deleted as a flag and reborn as geography, out-of-combat regen, death that costs the haul, the den breadcrumb (R2b) |
| [2026-08-sortie-deposit.md](2026-08-sortie-deposit.md) | Getting it home — party capacity and the filling order, the automatic deposit at the Throne (never the band edge), relics waking on deposit, dropping and the cache that replaced destruction, death clearing the unbanked haul (R2c) |
| [2026-08-escort.md](2026-08-escort.md) | The dead who walk with him — an escort that is one enum member and one field on the rally point, the wolves-to-hostiles() refactor, Defensive/Aggressive stances as policy rather than orders, and cover-the-retreat (R2d) |
| [2026-09-26-run-lifecycle-and-raise-dead.md](2026-09-26-run-lifecycle-and-raise-dead.md) | The run ends — RunLifecycle, MetaProfile XP/levels, the run-end screen, Second Wake as an unlock; Raise Dead as his first spell (graves free, bones anywhere); no starting skeleton; timed recruitment off; the R2 close-out fixes from the 2026-09-26 review |
| [2026-09-26-raven.md](2026-09-26-raven.md) | The bird that never lies (R2e) — dawn pings under the five-condition honesty invariant, delivered silence, the HUD chip and above-fog marks; discovery as its own flag; camp occupancy and ruling 1 on the camp; the wolf-den gold nudge |
| [2026-09-26-demo-shell.md](2026-09-26-demo-shell.md) | The demo shell — named key actions by physical key (AZERTY-safe), pause menu, Surrender confirm, once-per-session title, dev bridges and the speed button out of release builds, Windows/Linux export presets built and run |
| [2026-09-26-living-world-l0-l1.md](2026-09-26-living-world-l0-l1.md) | The living village (LIVING_WORLD L0 + L1) — `Settlement` with `GameState` as its façade, integrity on the trip loop, Harrowdale's named people, jobs, meals, guards who train and answer an alarm, restaffing after a death, bodies to raise; the Hidden / Hunting stance |
| [2026-09-26-endings-and-lair.md](2026-09-26-endings-and-lair.md) | What each ending keeps — victory keeps all gear and relics, fleeing from the lair keeps 3, death keeps nothing; the stash, carry-in slots (1 → 3) lost on death, the Lair screen and its shelves |
| [2026-09-26-items-and-gear.md](2026-09-26-items-and-gear.md) | After the first playtest: gear worn anywhere (and working at once), resources that take no space, six item slots for items only, items land on the ground to pick from, the Items window (I); **every building now a blueprint found in the world** |
| [2026-09-26-living-world-l2.md](2026-09-26-living-world-l2.md) | The Guild and the roadside opening (LIVING_WORLD L2) — wake on the road, the first-run popup, a board generated from world state, pay into his hands, standing that drops only when a witness's runner arrives, the keeper at the door, the Altar blueprint learned by clearing a den |
| [2026-09-26-hud-redo.md](2026-09-26-hud-redo.md) | The HUD redo — no bottom bar; every piece appears the first time its mechanic does; the portrait card, worn-gear strip, a roster of his dead with health, the action bar (R/E/C/I/B), History (L) under the clock, the full map (M) naming only what he has seen |
| [2026-09-27-living-world-l3.md](2026-09-27-living-world-l3.md) | Downed and prisoners (LIVING_WORLD L3) — humanoids go down at 0 hp and bleed out; bind (G) / finish (X), batch too; guards carry their own home; prisoners on a rope, the Cell, meals and starving, Search (teaches the Cell); Summon Ghoul at the Altar (the workbook's Ghoul row); burial parties and a new raisable grave per burial |
| [2026-09-27-ui-kit.md](2026-09-27-ui-kit.md) | The commissioned UI kit on the menus — masters committed to `_originals/UI/`, cut by `tools/make_ui_kit.py`; `UiKit.gd` dresses the title (main-menu frame), pause, flee picker, Lair, Items and run-end (popup frame, crest, plates, tick boxes, divider, kit XP bar); `tools/capture_menus.gd` screenshots them all |

New session write-ups go here as `YYYY-MM-topic.md`, never back into `CLAUDE.md`.
