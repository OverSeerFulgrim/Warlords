# R1 playtest notes — 2026-08-27

Fulgrim played R1 in one unbroken session; all six foundation exit criteria ticked
(`2026-08-foundation-exit-criteria.md`). Feel-question answer: **No.** "There was no purpose in leaving currently as the game is." Expected —
the R2 set (sites, grave loot, escort, raven) is what gives leaving a purpose; re-ask at R2's exit. Session end state: Day 1 Night, Wood 62 / Stone 135 / Bones 579 /
Food 2, Threat 1 (tier 0), Throne 40/40; both offered recruits turned away; 33 undead bound to Defend.

## Requests raised, triaged against the R2 plan

| # | Request | Status | Where it lands |
|---|---------|--------|----------------|
| 1 | Click the minimap → camera jumps there | **New** | Small UI prompt; `Minimap.gd` + `GameCamera.gd`. Candidate for a `U1` prompt before P1. |
| 2 | Right-click on world (or minimap) → Necromancer paths there | **New** | Input model change: he is currently held-key driven (`Necromancer.gd` reads a movement vector). Needs a click-to-move target that coexists with the three existing click-to-target modes in `Main.gd` and with right-click-drag camera pan (`GameCamera.gd:67`). Same `U1` prompt. |
| 3 | Skeleton workers reveal fog as they move | **New — design conflict** | `FogOfWar.gd` reveals only around the villain by design (RAVEN_SPEC §1 correction: "revealing the map remains the Necromancer's job, on foot"). Workers gather inside already-revealed ground, so in practice this mostly matters for R2c hauling / R2d escorts. Decide: (a) keep villain-only, (b) any bound/undead unit reveals at a smaller radius (e.g. 3 cells). Designer call before it goes in a prompt. |
| 4 | Worker dots on the minimap | **New — design conflict** | `Minimap.gd` header: "No live contents … the only markers are the lair and the Necromancer." Your own units aren't intelligence leaking through fog, so this is arguably consistent with the rule's intent. Proposed: show *your* units (workers/undead) as dim dots, keep hostiles/animals hidden. Designer call. |
| 5 | More tiles exist, implement them | **Already planned** | Prompt **P1** — wires the six new sheets in `assets/official/terrain/` and the connection-tile layer. |
| 6 | Path/road tiles so following a road finds things | **Already planned** | Prompt **P2** ("Roads that lead somewhere") + TERRAIN_SPEC §1: "the map should tell you where to go without a quest marker." |
| 7 | Spell so skeletons follow the Necromancer | **Already planned, different shape** | Prompt **R2d** / ESCORT_SPEC: `RallyPoint` gains `Order.ESCORT` + `follow`, driven through Command Undead — not a spell. If you want it *presented* as a spell in the UI, note it for R2d's surface; the mechanism stays. |
| 8 | Necromancer can loot graves | **Already planned** | Prompt **R2a** — four-way grave choice sheet, channelled looting (LOOT_SITES_SPEC §2–§5). |

## Designer decisions (2026-08-27)
- #3 fog: **all friendly units (workers, recruits, bound undead) reveal**, at a smaller radius than the
  Necromancer's 7 cells (propose 3–4). Reveal is *lit while present*: when the unit leaves, the cell
  drops back to the dim explored state, same as it already does for the villain. Nothing becomes
  permanently visible.
- #4 minimap: **yes** — friendly-unit dots. Hostiles/animals stay hidden.
- Whether #1/#2 get their own small prompt (`U1`) run right after P0, before P1 — they're map-untouched and improve every later playtest.
