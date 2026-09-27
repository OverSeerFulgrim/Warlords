# PROGRESSION — XP, levels, and unlocks

**Status:** Live since 2026-09-26. Every number here is read from `data/progression.json`; this page
explains them and prints the tables they produce. If the two ever disagree, the JSON is what the game
does — regenerate these tables. Frame: `ROGUELITE_REWORK.md` §9 and its §17 amendment.

## The rules

1. **XP is banked the instant it is earned.** A death two hours in still counted every deed before it.
2. **Levels are computed from total XP, never stored.** Change a number in the JSON and every profile
   re-levels on the next launch; nothing migrates.
3. **Unlocks widen options; they never raise numbers.** Second Wake is the one designer-sanctioned
   bend, alongside carried relics.
4. **Risk pays.** A deed is worth more the farther and more dangerous the place it happened — the same
   rule the loot tables follow.

## The formulas

**A deed:** `XP = base × band`

- **Base** comes in three sizes: **5** for tidying up (destroy the evidence), **10** for an act (loot,
  raise, rob, return, honour, desecrate, slay a villager, a guild bounty paid), and **30** for a fight won (clear a den or a guarded site).
- **Band** is the site's danger band, 1–4 (`WORLD_MAP_PLAN.md`). A deed with no site counts as band 1.

**Everything else** is flat, because none of it has a band: a wolf killed **5**, a building placed
**5**, each unit of sortie loot banked at the Throne **1**, each relic banked **20**, and **20** for
each carried-in item that comes home alive (the anti-hoarding lever, ROGUELITE_REWORK §10).

**When the run ends**, however it ends: **25 per full day survived**, plus **250** for a victory.

**Levels:** going from level *L* to *L*+1 costs `100 × L`, so level *L* needs `100 × L × (L−1) / 2` in
total. Each level costs one step more than the last. The cap is level 20.

## The tables

### XP per deed

| Deed | Base | Band 1 | Band 2 | Band 3 | Band 4 |
|---|---|---|---|---|---|
| Destroy the evidence | 5 | 5 | 10 | 15 | 20 |
| Loot a site | 10 | 10 | 20 | 30 | 40 |
| Raise a corpse | 10 | 10 | 20 | 30 | 40 |
| Rob a grave | 10 | 10 | 20 | 30 | 40 |
| Return the belongings | 10 | 10 | 20 | 30 | 40 |
| Rob a shrine | 10 | 10 | 20 | 30 | 40 |
| Honour a shrine | 10 | 10 | 20 | 30 | 40 |
| Desecrate a shrine | 10 | 10 | 20 | 30 | 40 |
| Slay a villager | 10 | 10 | 20 | 30 | 40 |
| A guild bounty paid | 10 | 10 | 20 | 30 | 40 |
| Take a prisoner (L3) | 10 | 10 | 20 | 30 | 40 |
| Search a prisoner (L3, no band) | 5 | 5 | — | — | — |
| Summon a Ghoul (L3, no band) | 30 | 30 | — | — | — |
| Clear a guarded site | 30 | 30 | 60 | 90 | 120 |
| Clear a wolf den | 30 | 30 | 60 | 90 | 120 |

### Levels

| Level | Total XP | XP from the previous level |
|---|---|---|
| 1 | 0 | — |
| 2 | 100 | 100 |
| 3 | 300 | 200 |
| 4 | 600 | 300 |
| 5 | 1000 | 400 |
| 6 | 1500 | 500 |
| 7 | 2100 | 600 |
| 8 | 2800 | 700 |
| 9 | 3600 | 800 |
| 10 | 4500 | 900 |
| 11 | 5500 | 1000 |
| 12 | 6600 | 1100 |

### What a run is worth

Worked through the formulas above, not measured. The second row is close to the scripted
playthrough of 2026-09-26.

| A run that… | XP |
|---|---|
| Raise one corpse at a Band 1 grave, die the same day | 10 |
| Raise both Band 1 graves, clear and loot a Band 2 den (two wolves), bank 7, die on day 1 | 117 |
| …then a derelict-graveyard trip (raise one, rob two), the camp, bank 15 more and a relic, die on day 3 | 282 |
| …and a Band 4 crypt cleared and looted, 20 more banked, a second relic, day 5 | 532 |

## Unlocks

| Unlock | Level | XP | What it does |
|---|---|---|---|
| Summon Ghoul | 2 | 100 | *Ruled 2026-09-26; not castable yet.* Summon a ghoul at the Dark Altar; needs a sacrifice — a living prisoner (ROGUELITE_REWORK §17.5, §17.7). The Altar's panel shows it greyed with its reason (level 2, then "needs a prisoner", which is LIVING_WORLD L3). Not in `data/progression.json` yet, so the run-end screen never promises it before it works. |
| Second Wake | 5 | 1000 | Once per run, death still costs everything he carries, but he wakes at the Throne instead of the run ending. |
| Second relic slot | 7 | 2100 | Carry a second item from the stash into a run (ROGUELITE_REWORK §10). |
| Third relic slot | 10 | 4500 | A third — and never more. |

At roughly 120 XP for an ordinary first-day run, Second Wake arrives around the **ninth run**; a player
who reaches Band 3–4 sites gets there in three or four. That is the intended "down the road". To move
it, change its `level`; to make the whole climb faster or slower, change `level_curve.step`.

## Tuning notes

- The **band multiplier is the lever that keeps players off Band 1**. If early runs farm the two fresh
  graves forever, it is working as intended only if those graves stay one-charge; if Band 1 still
  outpays the walk to Band 3, raise the multiplier's top end rather than cutting Band 1.
- **Survival XP** (25 a day) exists so a careful player who never fights still progresses. If
  hiding in the lair out-earns sorties, lower it.
- **Banked loot** pays 1 per unit on purpose: it rewards bringing things home without letting a big
  haul out-earn the deeds that produced it.
