### Foundation exit criteria (manual playtest checklist)

Copied from FOUNDATION_SPEC §11 — Stages 1–3 count as proven when all of these hold **in one unbroken session**. Headless smoke tests have covered the mechanics in isolation; these are the integration checks that need a human at the keyboard.

- [x] **1. Priority list drives 3 workers** across Wood/Stone/Bones with thresholds, and trees visibly deplete.
- [x] **2. Barracks gets built from gathered** (not starting) resources.
- [x] **3. At least 3 recruits arrive via events** spanning ≥2 categories, get fed every meal tick, and none desert from a bug rather than a real shortage.
- [x] **4. One recruit gets a funded house**; Barracks slot frees; town visibly grows.
- [x] **5. One food shortage is survivable and legible** — morale drops, player recovers by reassigning priorities.
- [x] **6. No soft-locks** — node exhaustion, full Barracks, and zero-food states all have clear UI messaging and a way out.

Known gaps against this list, as of now:

- **#5's "recovers by reassigning priorities"** is untested end-to-end. Food is gatherable (berry grove + deer) and the priority list has a Food row, but no session has yet gone shortage → reprioritise → recovery in one unbroken run.
- **#6's zero-food state** has messaging (hungry-meal log line, alert pin, morale colour) but no explicit "you have no food source left" warning if the grove is picked clean and the deer are gone.
- **#3's "spanning ≥2 categories"** is guaranteed by construction for the first three offers, but the *arrive via events, get fed every tick* half is only verified in isolation.


---

**Ticked 2026-08-27** — Fulgrim played R1 in one session; all six held. Screenshot: Day 1 Night, Wood 62 / Stone 135 / Bones 579 / Food 2, Threat 1 (tier 0), Throne 40/40; two recruits (Mira the Human Outcast, Vexis the Dark Elf) turned away; Command Undead bound 33 to Defend.
