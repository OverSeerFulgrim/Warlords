# docs/ — what is live, and what wins

One page so no file gets confused with another. Last verified 2026-09-26. The precedence rule,
stated once: **`design/ROGUELITE_REWORK.md` wins on design intent; the newest `history/` file
wins on what the code actually does; `CLAUDE.md` (repo root) wins on code conventions.**

## Start here

| File | What it is |
|---|---|
| `CURRENT_STATE.md` | The dated snapshot of where things stand — built, next, needs a human, still open. Refreshed 2026-09-26. Refresh or delete it when it goes stale — it says so itself. |
| `REVIEW_2026-09-26.md` | Fresh-eyes review of the repo against the docs, 2026-09-26: what is broken, doc drift, LIVING_WORLD L0 readiness, rulings owed. Non-authoritative, a snapshot; its addendum lists what got fixed the same day. |
| `GAME_IMPROVEMENT_REVIEW.md` | Product-level review lens (2026-08-05), **non-authoritative** by its own header. Its R2 review criteria (§14) are the R2 exit playtest questionnaire. |
| `prompts/R2_PROMPTS.md` | **The only live prompt set.** The build order: playtest R1 → P0 → U1 → F1 → C2 → P1 → P2 → R2a–R2e. **All of it has landed** (2026-09-26); next is the R2 exit playtest. Every older prompt set is in `archive/`. |
| `SYSTEMS_MAP.html` | The interactive systems map. |

## design/ — the specs

**The plan of record:** `ROGUELITE_REWORK.md` (run frame, eras, R1–R6 roadmap), with
`WORLD_MAP_PLAN.md` as the adopted map spec.

**The R2 slice specs** (reviewed by the designer 2026-08-29; **all built**, R2a–R2e landed by
2026-09-26; each spec's amendment blocks bind over its body):
`TERRAIN_SPEC.md` (seven sheets, autotiling, forests §6b, generation) ·
`LOOT_SITES_SPEC.md` (sites, choices, loot, relics, wolf dens §3b) ·
`SORTIE_SPEC.md` (carry, deposit, death) · `ESCORT_SPEC.md` (Command Undead: Escort) ·
`RAVEN_SPEC.md` (honest passive pings) · `NECROMANCER_SPEC.md` (his statline and Arcane combat) ·
`COMBAT_FEEDBACK_SPEC.md` (red damage numbers). `TERRAIN_MASKS.md` is TERRAIN_SPEC's companion
(connection masks read off the sheets, 2026-08-27).

**Live since 2026-09-26:** `PROGRESSION.md` (XP formulas, the level curve, unlocks, with printed
tables; the numbers live in `data/progression.json`).

**Live and being built:** `LIVING_WORLD_SPEC.md` (2026-09-26 — the guild opening, settlement
symmetry, faction ecosystems; all rulings (1–16) issued in §15, none open; its §13 lists the
amendments it requires elsewhere). **Stages L0–L2 are built** (its §14; history files
`2026-09-26-living-world-l0-l1.md` and `…-l2.md`); L3 is next.

**Live since C2 (2026-08-26):** `COMBAT_SPEC.md` — the nine-attribute stat system, profiles,
damage model; its amendment block is the adoption record. `stat_rework_roster.xlsx` beside it is
**the authoritative statline source** (races, villain, wolf); `tools/export_roster.gd` exports it
to `data/races.json`. Rout and pack morale (slice C3) are not built.

**Live with scars:** `FOUNDATION_SPEC.md` (settlement numbers; carry = Endurance since the C2
adoption; where it still speaks Might, COMBAT_SPEC §2 and `races.json` win) · `TRAITS.md` + `TRAITS_IMPLEMENTATION_PLAN.md` (already written against the new stat
model; the plan has not been run yet) · `RACES.md` (stat table re-issued 2026-09-26 from
`data/races.json` — an export, the workbook wins; alignment/rarity/housing content is live) · `GAME_OUTLINE.md` (**Stages 4–5 dead** — rework wins;
pillars and the Stage 1–3 loop description are live).

## art/

`SPRITE_SPEC.md` is the one sizing authority (terrain sheets are its documented exception).
`ART_BRIEF.md` and `Necromancer_Reference.md` are commissioning references;
`MODULAR_CHARACTER_ANIMATION_REVIEW.md` §8 (paper-doll animation) is deferred, the rest of it
executed.

## history/

The dated development narrative — what actually happened, indexed in `history/README.md`. Never
edited except to correct a factual error, and then inline with a dated note.
`2026-08-villain-split.md` and the two `*-r1.md` files are the record of R1's shipped code; the
three `2026-09-26-*` files record the run lifecycle and Raise Dead, the Raven (R2e), and the demo
shell.

## archive/

Completed prompt sets and superseded originals. **Nothing in it is live**; its README says why
each file is there.
