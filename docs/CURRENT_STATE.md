# CURRENT STATE — What Is True Right Now

**Snapshot date: 2026-08-09.** Supersedes and replaces the 2026-08-06 snapshot. Same rules as
before: this file reconciles every design document into one current picture, records which doc
wins on each disputed point, and is a snapshot, not a living authority — when it disagrees with a
doc amended after this date, the newer amendment wins and this file should be refreshed or
deleted.

**Dating note:** the amendment blocks this pass wrote into the specs are marked "2026-08-06"
(the working date the pass was run against). Treat every "2026-08-06 amendment" in
`TERRAIN_SPEC.md`, `LOOT_SITES_SPEC.md`, `COMBAT_SPEC.md`, `NECROMANCER_SPEC.md` and the
Endurance rewording as belonging to *this* snapshot's changes, not to the morning-of-08-06
reconciliation the previous snapshot recorded.

---

## 1. The document timeline (oldest → newest)

| Date | Document | Standing today |
|---|---|---|
| pre-08-03 | `GAME_OUTLINE.md`, `FOUNDATION_SPEC.md`, `RACES.md`, `TRAITS*.md` | Settlement base layer only. GAME_OUTLINE Stages 4–5 superseded by the rework. FOUNDATION §6 reworded: **carry = Endurance**. `RACES.md`'s stat table is dead — prompt C2's export re-authors it. |
| pre-08-03 | **`COMBAT_SPEC.md`** | **Re-live.** Was shelved with the settlement docs; its 08-06-marked amendment block adopts slice **C2 (the stat rework)** into the build order. C1/C1.5 shipped; C3 waits for R3; C4→R5, C5→R4; **C6 retracted** (off-map premise deleted with commit `3023372`). §7 amended: creatures carry all nine attributes. |
| pre-08-03 | `stat_rework_roster.xlsx` | **Complete and authoritative** for all statlines: 17 races × 9 attributes, skill templates, overrides, and now the **Necromancer and Wolf rows** (villain: hp 20, walk 1.0, Arcane; wolf: hp 18, chase 1.3, Melee — every shipped number preserved). C2 exports it to `races.json`. |
| 08-03 | `WORLD_MAP_PLAN.md`, **`ROGUELITE_REWORK.md`**, `ROGUELITE_PROMPTS.md` | Unchanged: the rework is the plan of record; R1 is done to spec. |
| 08-05 | R1 history: `2026-08-world-map-r1.md`, `2026-08-world-population-r1.md`, `2026-08-villain-split.md` | The record of shipped code. The population file's travel table is the R1-playtest yardstick. |
| 08-06 | `LOOT_SITES_SPEC.md`, `TERRAIN_SPEC.md`, `SORTIE_SPEC.md`, `ESCORT_SPEC.md`, `RAVEN_SPEC.md` | The five R2 slice specs, drafts for review. All five now exist (the old snapshot predated four of them) and all have been reworded to the nine-attribute language where they touch stats. |
| this pass | Amendments: forests (`TERRAIN_SPEC.md` §6b), wolf dens (`LOOT_SITES_SPEC.md` §3b), C2 adoption (`COMBAT_SPEC.md` header) | Blocking dense forest with corridors and one-mouth clearings; the first clearable site with the dusk-wolf gate; the stat rework scheduled. |
| this pass | New: `NECROMANCER_SPEC.md`, `COMBAT_FEEDBACK_SPEC.md` | The villain's combat kit (**Arcane** — engage close at 26px, cast far at 5 cells, no attack button) and floating red damage numbers. Drafts for review. |
| this pass | **`R2_PROMPTS.md`** | The executable order (§2 below). Written despite `ROGUELITE_PROMPTS.md`'s wait-for-playtest rule — the *gate at its top preserves that rule*: nothing runs before the playtest. |
| 08-05 (filed 08-09) | `GAME_IMPROVEMENT_REVIEW.md` | Product-level review lens, non-authoritative by its own header. Its §12 "thin slice first" ordering is a live recommendation the prompt set has **not** adopted (R2a builds the full catalog); its §14 criteria are the R2 playtest questionnaire. |
| 08-09 | Documentation hygiene: `docs/README.md`, `docs/archive/`, banners | The live/dead index; six completed prompt sets + the cleanup plan + the `.docx` original moved to `archive/`; `RACES.md` and `GAME_OUTLINE.md` carry partial-superseded banners. |

**Precedence rule, unchanged:** `ROGUELITE_REWORK.md` wins on design intent; the newest history
file wins on what the code actually does; `CLAUDE.md` wins on conventions — its stats line now
points at COMBAT_SPEC §2 and says plainly that the *code* speaks Might until C2 runs.

---

## 2. Where the project stands

- **Built and verified:** Stage 1–3 settlement loop and R1 (144×144 fixed world, terrain/fog,
  directly-controlled killable Necromancer, static village, sealed rival ground, travel in band).
  Unchanged since the last snapshot — **no code has been written since; this pass was all design.**
- **Next milestone: R2 — "The world is worth exploring"**, now fully specced across seven specs
  plus two adopted COMBAT_SPEC slices. Nothing in R2 is implemented.
- **The prompt order** (`R2_PROMPTS.md`, gate intact):

  ```
  playtest R1 → P0 (travel harness + doc fixes) → F1 (damage numbers) → C2 (stat rework)
              → P1 (tilesheets) → P2 (generated world + forests)
              → R2a (sites + dens) → R2b (villain combat) → R2c (deposit)
              → R2d (escort) → R2e (raven)
  ```

  F1 was briefly named C1 and was renamed to avoid colliding with COMBAT_SPEC's slice names.
- **Debts owed before anything runs:** the R1 *feel* playtest (a human at the keyboard — the gate
  everything sits behind), the six unticked foundation-checklist boxes, and the CRLF
  normalization commit (still outstanding from the last snapshot; `git status` still lies).

---

## 3. Decisions made this pass (the designer ruled on each)

1. **The stat rework is adopted, scheduled as prompt C2.** Nine attributes, one governing
   attribute per skill, profiles (Melee Str/End, Ranged Dex/Speed, Arcane Int/Int). **Carry
   moves to Endurance** — reworded through FOUNDATION §6, SORTIE, LOOT_SITES; no shipped number
   moves (skeleton End 4, wolf End 5 equal their old Might; villain End 6 keeps hp 20 / carry 6).
2. **The Necromancer is Arcane** (Int 7). Fights open only at 26px or on being hit; once engaged
   he casts at 5 cells. Kiting is real but bounded (wolf chase outruns him). Command Undead stays
   his real weapon; no attack button, ever. `NECROMANCER_SPEC.md` is the detail.
3. **Creatures use the same nine attributes as characters** — COMBAT_SPEC §7's reduced set is
   superseded; wolf Int 2 is the arcane-vs-beast tuning knob. Behaviour stays hardcoded profiles.
4. **Forests are the third wall.** Dense forest blocks; open woodland fringes at 0.85; corridors
   are carved, not paved; every interior clearing has exactly one mouth. Bigger trees: canopy
   pines at 1.9–2.6 tiles (one MultiMesh, zero nodes), lair pines 1.5 → 2.0 tiles.
5. **Wolf dens are the first clearable site**, living in forest clearings. 2–3 wolf-statted
   guardians; clearing the last den ends dusk raids for the run; best wolfhide-cloak odds; Power
   deed on clearing.
6. **Damage is shown as red floating numbers** in real time (`COMBAT_FEEDBACK_SPEC.md`), fed by
   one `damage_shown` signal from the policy layer. Views only; Combat/Engagement untouched.
7. **Relic effects generalize to attribute deltas** (`{"attribute": ..., "delta": ...}`);
   `sermon_of_ash` is now +1 Intelligence.

---

## 4. Known rough edges

1. ~~ESCORT_SPEC §9 stale aura-flag line~~ — **fixed 08-09**: the line now records that R2b makes
   the aura positional and deletes the flag.
2. ~~SORTIE_SPEC §1.5 "send an escort back"~~ — **ruled and struck 08-09**: no independent
   delivery; if it ever exists it is a spell (R5 material). The strikeout note sits in the spec.
3. **The seven R2 specs are still marked "draft for review."** The review is the designer reading
   them — same dependency as the playtest, same person.
4. **This pass's amendments are date-stamped 08-06 inside the files** (see the dating note up
   top). Cosmetic, but worth knowing before trusting a date over this table.
5. **`GAME_IMPROVEMENT_REVIEW.md` §12 recommends a thin-slice R2** (two graves + carry + deposit
   + death before the full catalog) — a real, unadopted alternative to R2a's build-it-all order.
   Decide at spec review whether R2a gets split into R2a-thin + R2a-full.
6. **Repo `README.md` (root) still describes the pre-rework game** per the review's §11 — small,
   still owed.

---

## 5. What happens next, in order

1. **Play R1** — twenty minutes, human at keyboard: does leaving the lair feel like a decision?
   Tick the six foundation-checklist boxes in the same session. Everything is gated on this.
2. Review the seven R2 specs (they wait on the designer, not on code).
3. Run P0, then F1, then C2 — safe, map-untouched, and every later prompt builds on them.
4. Run P1 → P2, re-running `measure_travel` until every row is back in band.
5. Run R2a → R2e in order, playtesting between prompts.
6. Check R2's exit ("one more grave, or turn back?" is a real question), then write R3 prompts —
   not before.

Housekeeping: the CRLF normalization commit (or a `.gitattributes` line) is **still owed** so
`git status` becomes honest again — the improvement review's §11 asks for the same thing. The
documentation side is now clean: `docs/README.md` is the live/dead index, `docs/archive/` holds
everything completed or superseded, and one commit should capture this whole pass.
