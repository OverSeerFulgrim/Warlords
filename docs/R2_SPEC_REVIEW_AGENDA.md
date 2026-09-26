# R2 Spec Review — Designer's Agenda

*Prepared 2026-08-29. The review is you reading the seven specs (`CURRENT_STATE.md` §4.3); this
agenda exists so the read is a checklist, not 1,900 cold lines. One sitting per spec is plenty;
the whole pass is an evening. The R2a thin/full question is already ruled (2026-08-29: R2a stays
whole), so nothing here re-opens it.*

**Suggested order:** LOOT_SITES → SORTIE → NECROMANCER → ESCORT → RAVEN, then TERRAIN and
COMBAT_FEEDBACK as light conformance reads (their code already shipped in P1/P2 and F1 — you are
accepting them as-built, not shaping them).

**How to read each one:** the *commitments* below are what the spec binds R2 to — check you still
want them. The *focus questions* are the ones worth holding in mind while reading (drawn from the
spec's own tunables and `GAME_IMPROVEMENT_REVIEW.md` §2–§9). The *pre-rulings* are tunables you
can settle now with a pencil mark so the playtest measures instead of debates. Don't re-litigate
anything in R2_PROMPTS.md's "Decisions already made" list.

---

## 1. LOOT_SITES_SPEC — the biggest surface, read it hardest

**Commits you to:** eleven site types across four bands (2 clearable wolf dens among them);
10–15 *active* sites per run drawn from a ~22-max pool; every site is a choice with a trade-off,
never a walk-on pickup; danger telegraphed in the inspection payload, surprises only in the ~10%
self-found budget; distance buys quality, enforced by tiered loot tables; gold as the sixth
resource; relics; the four-way grave choice; deeds ledger (per-villain) vs notice→threat
(global); dusk raids end when the last den is cleared.

**Focus questions (§2 of the review):**
- Is field loot valuable enough to justify leaving home — does anything a site yields duplicate
  the home economy? (Exclusivity is the spec's own first law; audit the tables against it.)
- Does the four-way grave choice sheet read as four *different* sorties, or two good picks and
  two traps?
- Cemetery-as-notice (no guardian, escalating threat): does "the third grave is reckless" feel
  like your game?
- Eleven types at R2 — happy with all eleven, or would you cut one? (Cutting a type now is one
  table row; after R2a it's a migration.)

**Pre-rulings worth pencilling:** channel durations; occupancy odds for the camp; whether
destroy-the-evidence should cost bones/time; whether a fled pack wolf counts toward "cleared"
(spec says yes); post-clearance dusk floor (spec says 0 — the quiet is the reward).

---

## 2. SORTIE_SPEC — the loop's spine, shortest spec, biggest rule

**Commits you to:** banking at the Throne only (band edge banks *nothing*); carry = Endurance,
no bespoke stat, no bags (villain 6, skeleton 4); overflow leaves an exact remainder charge at
the site, never a ground pile; drop-in-reach returns loot to the site, drop-in-open destroys it;
relics activate on deposit, not pickup; death clears every unbanked thing; no independent
escort delivery (struck 08-06 — if it ever exists, it's an R5 spell).

**Focus questions:**
- Does limited capacity create decisions rather than inconvenience? The spec's answer is "tune
  yield, never capacity" — agree before the playtest tempts you otherwise.
- Is the return journey meaningfully different when loaded? (The dusk warning + the wolf are
  carrying that; nothing else slows him.)
- Does deposit-with-no-button feel like a reward or a bookkeeping event? §2 of the review wants
  an audiovisual payoff — the spec is quieter than the review here. Rule which you want.

**Pre-rulings worth pencilling:** drop-in-open destructive vs half-lossy; partial deposit stays
free; dusk warning hour and loudness; relics stay droppable (the spec argues yes, deliberately).

---

## 3. NECROMANCER_SPEC — the villain's own hands

**Commits you to:** no attack button ever; engage at the wolf's own 26px, then cast at 5-cell
arcane reach (engage close, cast far — the split *is* the design); retaliation without input;
the lair aura becomes a position test and the flag is deleted; his magic is a sidearm — one wolf
is a costly win, a 3-wolf den solo is a loss, and Band 3 solo wins mean *his* numbers are wrong;
a two-entry spell surface that stays two entries until R5.

**Focus questions (§3 of the review):**
- Does controlling him feel different from controlling an adventurer — is walking into 26px a
  *decision* the screen lets you perceive? (Flagged NEEDS A HUMAN in the prompt; you'll answer it
  at the R2b playtest, but read §3's "why the split matters" now and object now if ever.)
- Do his actions express necromancy through consequences? §3 of the review wanted ~3 field
  actions; R2 ships fight + raise + escort. Enough for this stage, or is one more (desecrate?
  conceal?) worth pulling forward?
- Can the player tell why the Necromancer personally had to be present? (Exclusivity again —
  essence, relics, deeds are his alone.)

**Pre-rulings worth pencilling:** disengage parting-shot cost (spec: no — the chase is the
cost); out-of-combat regen (spec: none); wolf Int 2 as the tuning knob you'll reach for first.

---

## 4. ESCORT_SPEC — one enum member, not a system

**Commits you to:** escort = RallyPoint gains `Order.ESCORT` + a `follow` field, everything
downstream unchanged; all bound undead, never a subset, never living recruits; no selection UI;
every hauler is a laborer not digging at home (the relief valve that keeps carry tight);
cover-the-retreat below the flee threshold is the one new behaviour and the one thing they do
unasked; escort deaths ride the ordinary combat path and destroy the load.

**Focus questions:**
- The allocation trade ("the dead can dig or they can fight, not both") is the spec's whole
  economy — is the sting of a lost escort (body + load + labour) the *right* sting, or too much
  at R2 scale?
- §7 of the review asks that settlement features answer "how does this prepare the next sortie /
  how does leaving hurt" — the escort is the cleanest answer the game has. Read §5 (what it
  costs) and check the cost is visible enough at home.
- Should covering slow the villain? Spec says no (he is always yours to drive). This is the one
  place the no-orders pillar and protectiveness rub — worth a deliberate yes/no.

**Pre-rulings worth pencilling:** `ESCORT_RADIUS_PX` 2.5 cells (the party-reads-as-a-party
number); skeleton 0.9 speed (a hair slower than him, deliberately); whole-escort wipe forces
nothing (spec: correct).

---

## 5. RAVEN_SPEC — the honesty invariant, and the correction block

**Read the correction block at the top first** — an older doc claims the Raven clears fog; this
spec supersedes it, and the harness asserts fog is byte-identical after 1,000 pings.

**Commits you to:** passive pings only — no token, no directives, no scouting UI, no fog
interaction; minor Band 1–2 finds only, never the crypt; the five-condition honesty invariant
(reachable, Band 1–2, unguarded/unoccupied, undiscovered, has a charge) with silence as the
correct output when nothing qualifies; 70% dawn cadence, cap of 3, pings never expire; the
abandoned-camp asymmetry (the bird can honestly know it's empty when you can't) as its whole
value.

**Focus questions:**
- "Never relax a condition to produce content — a silent day is a correct day." That rule will
  be pressure-tested the first time a playtest feels quiet. Sign it now or amend it now.
- Is 70%/day generous or noisy? (NEEDS A HUMAN at R2e; pre-rule your prior.)
- Exact distance vs rough on a ping — spec says exact, the walk is the cost. Agree?

---

## 6. TERRAIN_SPEC — conformance read (P1/P2 shipped it)

The code exists; you played it at the P2 human check and the roads/treeline answers were YES.
Reading is confirming the spec matches what shipped plus the two things you added after:

- The **road promise** (your 08-27 ruling) is now in R2a item 3: every dirt-track terminus gets
  a loot action, asserted in `verify_terrain`. Confirm the wording matches your intent.
- Band 4 gets no paths — found, not followed; clearings have exactly one mouth; the draw-call
  budget is terrain-only by definition now (§12's long paragraph is the record — worth reading
  once so the next "budget exceeded" conversation is short).
- §11 (how this feeds R4's shuffle) is the only forward-looking part — skim for anything that
  would surprise you in R4.

---

## 7. COMBAT_FEEDBACK_SPEC — conformance read (F1 shipped it)

Shortest spec, already live. One question: after two weeks of playtests, do the red numbers do
what §1 promises (every point of villain damage visible)? If yes, mark it accepted and move on.
The den fights and villain casting land on this system in R2a/R2b — any float-readability
complaint gets much more expensive to fix after those.

---

## Rulings owed along the way (not spec-gated, but this is the sitting to clear them)

1. **`missions.json` court_infiltration** — currently `"relevant_stat": "mercantile"` (difficulty
   7, reward 2 rep + 5 essence). The open call: is planting influence in a noble's court a
   mercantile act or a leadership one under the nine-attribute model? One-word edit either way.
2. **RACES.md re-issue** — its stat table is re-authored by C2's export (COMBAT_SPEC §12). C2
   shipped; the re-issue is still owed. Fold into the next housekeeping commit.
3. **Root README** still describes the pre-rework game (review §11).
4. **`.gitattributes` / CRLF** — the autocrlf warnings on every commit; one line ends them.

Items 2–4 could be one small Claude Code housekeeping prompt — say the word and it's drafted.

---

## Exit

When each spec is read: either mark it accepted (strike "draft for review" in its header, or
keep a one-line list and commit the lot as "R2 spec review: accepted") or raise the objection
*before* R2a runs. Then run R2a from `docs/prompts/R2_PROMPTS.md` — it's ready, item 0 and the
road promise included.
