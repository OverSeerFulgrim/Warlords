# docs/ — what is live, and what wins

One page so no file gets confused with another. Last verified 2026-08-09. The precedence rule,
stated once: **`design/ROGUELITE_REWORK.md` wins on design intent; the newest `history/` file
wins on what the code actually does; `CLAUDE.md` (repo root) wins on code conventions.**

## Start here

| File | What it is |
|---|---|
| `CURRENT_STATE.md` | The dated snapshot reconciling everything. Refresh or delete it when it goes stale — it says so itself. |
| `GAME_IMPROVEMENT_REVIEW.md` | Product-level review lens, **non-authoritative** by its own header. Its R2 review criteria (§14) are the playtest questionnaire. |
| `prompts/R2_PROMPTS.md` | **The only live prompt set.** The build order: playtest R1 → P0 → F1 → C2 → P1 → P2 → R2a–R2e. Every older prompt set is in `archive/`. |

## design/ — the specs

**The plan of record:** `ROGUELITE_REWORK.md` (run frame, eras, R1–R6 roadmap), with
`WORLD_MAP_PLAN.md` as the adopted map spec.

**The R2 slice specs** (drafts awaiting designer review, all current):
`TERRAIN_SPEC.md` (seven sheets, autotiling, forests §6b, generation) ·
`LOOT_SITES_SPEC.md` (sites, choices, loot, relics, wolf dens §3b) ·
`SORTIE_SPEC.md` (carry, deposit, death) · `ESCORT_SPEC.md` (Command Undead: Escort) ·
`RAVEN_SPEC.md` (honest passive pings) · `NECROMANCER_SPEC.md` (his statline and Arcane combat) ·
`COMBAT_FEEDBACK_SPEC.md` (red damage numbers).

**Re-live after the C2 adoption:** `COMBAT_SPEC.md` — the nine-attribute stat system, profiles,
damage model; its amendment block is the adoption record. `stat_rework_roster.xlsx` beside it is
**the authoritative statline source** (races, villain, wolf) until prompt C2 exports it to
`data/races.json`.

**Live with scars:** `FOUNDATION_SPEC.md` (settlement numbers; carry = Endurance since the C2
adoption) · `TRAITS.md` + `TRAITS_IMPLEMENTATION_PLAN.md` (already written against the new stat
model; the plan has not been run yet) · `RACES.md` (**stat table dead** — workbook wins; its
alignment/rarity/housing content is live) · `GAME_OUTLINE.md` (**Stages 4–5 dead** — rework wins;
pillars and the Stage 1–3 loop description are live).

## art/

`SPRITE_SPEC.md` is the one sizing authority (terrain sheets are its documented exception).
`ART_BRIEF.md` and `Necromancer_Reference.md` are commissioning references;
`MODULAR_CHARACTER_ANIMATION_REVIEW.md` §8 (paper-doll animation) is deferred, the rest of it
executed.

## history/

The dated development narrative — what actually happened, indexed in `history/README.md`. Never
edited except to correct a factual error, and then inline with a dated note. The three
`*-r1.md` files are the record of R1's shipped code.

## archive/

Completed prompt sets and superseded originals. **Nothing in it is live**; its README says why
each file is there.
