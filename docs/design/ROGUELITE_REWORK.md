# ROGUELITE REWORK — From Hidden Lair to Rising Legend

**Status:** Design target, agreed in discussion 2026-08-03. Amended 2026-08-06 — see §16 for the post-R1 decisions and corrections. Supersedes the "recruits arrive on a timer" model and the open-ended campaign structure implied by GAME_OUTLINE Stages 4–5. Does **not** invalidate the Stage 1–3 foundation (settlement grid, priority-list economy, Barracks intake, morale/meals, combat primitive) — that foundation becomes the in-run base layer and is a prerequisite for everything here.

**Companion documents:**
- `WORLD_MAP_PLAN.md` — the world map spec ("the map doc" throughout). Adopted with three amendments (§4). The original `Warlords_World_Map_Scale_and_Exploration_Plan.docx` is the archived source; the `.md` is the live, tooling-readable version and wins on any divergence.
- `GAME_OUTLINE.md` / `FOUNDATION_SPEC.md` / `RACES.md` — still authoritative for the settlement layer mechanics.
- `CLAUDE.md` — code conventions; §12 of this doc maps the rework onto the existing systems.

---

## 0. Why this rework

Two problems with the current design, one of fiction and one of genre:

1. **Recruits finding a hidden lair makes no sense.** The Necromancer is hidden *because he is weak* and wants to stay that way as long as possible. Strangers wandering in to volunteer undermines the fantasy. The fix: **power attracts power** — reputation is earned through deeds in the world, and only once the world whispers his name do followers seek him out. (The seed of this already exists in code: `recruitment.json`'s rarity-by-power table.)
2. **Without a reason to leave the base, this is a colony sim.** The difference between a colony sim and the game we want is where the player's attention and risk live: concentrated on a person who *leaves*, with the base demoted to an engine that runs while he's gone. The priority-list economy was built to self-manage; this rework is what that was for.

The progression in one line: **Hide → Explore → Influence → Rule.**

---

## 1. The run frame

**One region = one run.** The game is structured like Slay the Spire: discrete runs on a shuffled map, permadeath, meta-progression between runs that adds *variety, not power* (§9).

### A run ends one of three ways

| Ending | Trigger | What you keep |
|---|---|---|
| **Death** | The Necromancer dies (or the Throne falls) | XP earned during the run, chronicle entry. Everything else lost — including any stash relics brought in. |
| **Flee the region** | Player chooses to abandon the run alive | XP + everything the Necromancer carries banks to the stash. No victory. |
| **Take the Manor** | Survive the crusade and seize the human lord's manor | XP + all loot banks, victory bonus, chronicle triumph entry. |

The flee option is deliberate: it is the run-scale version of "one more grave, or turn back?" Deaths never feel arbitrary because there was always a door out the player chose not to take.

**Target run length: 1.5–2 hours for a full victory**, with most deaths arriving earlier. All escalation pacing, XP rates, and crusade timing tune against this number.

### The banking rule (one rule, three scales)

Nothing is yours until it is home. This already governs the worker trip loop (resources enter `GameState` only on deposit). It now applies at every scale:

- **Trip:** a worker's carried load banks when deposited at the settlement.
- **Sortie:** the Necromancer's expedition loot banks when he returns to the lair — usable in-run from then on.
- **Run:** everything banks to the permanent stash only when the run ends *alive* (flee or victory). Die and the run's loot is gone, along with anything brought in from the stash.

---

## 2. Reset / persist ledger

Explicit, because in a run frame ambiguity here breaks everything.

**Resets every run:** the settlement (Throne + starting skeletons only), all recruits, all resources, the world map layout (reshuffled), reputation (all five axes to zero), relics carried into the run (at risk), day counter, threat/escalation state.

**Persists across runs:** villain XP and level, unlocks (spells, unit types, items, encounter-pool entries, relic slots), the stash, Lair decorations and trophies, the chronicle.

**Hard rule: no meta-progression may grant in-run reputation, stats, or resources.** Being unknown again each run *is* the Era I fantasy. A level-20 Necromancer's skeleton hits exactly as hard as a level-1's; the veteran has more options, never bigger numbers. (Carried relics are the one sanctioned bend in this rule — see §10 for why they're self-balancing.)

---

## 3. The arc of a run: three eras

The proposal's Eras map onto a single run's escalation, not a campaign. They align with the map doc's §10 escalation bands.

**Era I — Survival (early run).** Unknown. Throne, Raven, a handful of skeletons, thin resources, zero reputation. The base mostly self-manages; the player's primary activity is sorties into the wilderness. Humans blame animals and outlaws for anything odd. No recruits — nobody knows you exist.

**Era II — Influence (mid run).** Deeds accumulate into reputation; rumors spread (emptied graves, vanished caravans, travelers' stories). Recruit offers begin — people *seeking you out*, gated by reputation axes (§7), not time. The estate notices patterns; the church investigates; patrols thicken.

**Era III — Dominion (late run).** The settlement is real, bounty parties operate — **as visible units travelling the world map, in view** (§16 amendment 2; the old off-map abstraction was deleted with the world map's arrival) — and exploration becomes optional rather than mandatory. Roads are contested, the lordship fortifies, and the crusade musters. Ends at the manor gates — theirs or yours.

---

## 4. The world map

**The map doc (`WORLD_MAP_PLAN.md`) is adopted as written**, including: 144×144 cells (bounds 128–160), travel-time targets as the primary metric (3–5 min uninterrupted crossing), the four danger bands, region allocation, content density (~10–15 active meaningful locations per run), fog of war, telegraphed danger, roads-vs-wilderness tradeoff, escalation-in-place, and shuffle-based replayability.

Sanity check against code: walk speed is 1.0 = 1 cell/second (`CELL_SIZE` 64px), so 144 cells ≈ 2.4 min straight-line — inside the target band once terrain and detours exist. (Correction, 2026-08-06: this originally claimed 1.0 was "already" the code's value; the Necromancer was 1.4 when this was written, and R1 tuned him down to 1.0 — see `docs/history/2026-08-world-population-r1.md`. The documented cost: he's only ~11% faster than a skeleton cross-country; roads, not base speed, are what make him fast.) A cross-map trip costs a meaningful slice of the 30-minute day, so expeditions interact with dusk, meals, and the wolf spawn *for free*.

### Three amendments

1. **The Demonologist's region ships sealed.** The 20×20 territory stays in the map template so the layout never needs rework, but v1 places a dormant/sealed ritual ground there — no AI rival. The Demonologist returns as the second *playable class* (§11), not as an AI first.
2. **The village is static in v1.** No homes/market/inn routines. Static buildings, one or two scripted patrol loops (reusing `Roaming.gd`), nothing with a daily schedule. Escalation is initially just patrol count and radius growing with notoriety.
3. **Scouting is passive, not directed.** The doc's "8–12 cells per scouting action" model is replaced by the passive Raven (§6). Fog of war clears primarily through the Necromancer's own travel — which is the right dependency, because his physical presence in the world is the whole point.

---

## 5. Exploration: the sortie loop

**The Necromancer is directly controlled in the world.** This is a deliberate, bounded amendment to the indirect-control pillar: *he* is the player; the pillar governs everyone else. Followers and escorts are never individually commanded, ever.

A sortie is a push-your-luck loop:

```
leave the lair with an escort → travel (fog clears as you go) → investigate /
gather / fight / choose → carry capacity fills → the return leg → deposit at the lair
```

- **The escort behaves automatically** — defend the Necromancer, carry loot, engage nearby enemies, cover the retreat. Built on the Command Undead order model (a standing order on the dead as a class), not per-unit control.
- **Everything carried is unbanked until home.** A heavy load, an injury, or nightfall turns a safe return into a crisis — that's the design working, not a bug.
- **Danger comes from choices, not attrition** (map doc §9). The player should rarely die during uneventful movement; failure follows an encounter, pursuit, or deliberate gamble. Distant bands offer clearly better loot to justify the risk.
- **The Necromancer becomes killable.** His death ends the run (§1). The "untouchable" combat rule from the settlement combat pass is repealed in the world; whether he keeps a protective aura *inside his own lair* is an open tunable (§15).

**Code migration note:** `NecromancerToken` currently owns its position with no data object — with the explicitly documented trigger that the moment any other system needs his position, it splits like `Laborer`/`WorkerToken`. That moment is now. He needs a data object (position, hp, carry, escort roster) with the token as a pure view, before any world-map work begins.

---

## 6. The Raven

**V1 is a passive ping system.** The Raven is an unseen bird — no token, no directives, no scouting UI. Periodically, a portrait icon appears with a ping on the map: *the Raven found something*. Clicking centers the camera on the ping.

- **Pings are always honest.** What the Raven reports is real and worthwhile — minor finds only (a fresh grave, an abandoned camp, a wounded traveler, a small cache). It never finds the big stuff and it never baits you into a trap.
- **Dangerous surprises live only in self-found discoveries.** The "~90% worthwhile / 10% surprise" ratio applies to what the *player* uncovers, never to Raven pings. The familiar stays trustworthy; the world stays treacherous.
- **The Raven does not solve fog of war.** It surfaces a handful of opportunities; revealing the map remains the Necromancer's job, on foot, at risk.

**Deferred (post-v1):** directed scouting ("scout that area"), and the Raven accompanying bounty parties as an observer. Both are good; neither is needed to prove the loop. When directives arrive, the choice "is the Raven scouting ahead of *you*, or watching *home*?" is the design hook to build them around. (Note: with bounty parties now visible on-map — §16 amendment 2 — the observer role shrinks from "reports on an unseen expedition" to alerts/camera-centering on a party the player could already watch; it may not survive as a feature.)

---

## 7. Reputation and the recruitment rework

**The timed recruit event is dead.** Recruitment is unlocked by reputation, earned by witnessed deeds during the run. Reputation is in-run only (§2) and also feeds escalation — the same notoriety that attracts followers attracts the church.

Five axes, each moved by deeds and each attracting a different kind of follower:

| Axis | Moved by | Attracts |
|---|---|---|
| **Wealth** | Hoarding treasure, robbing the rich, visible prosperity | Merchants, craftsmen, opportunists |
| **Power** | Battles won, armies seen, monsters slain | Warriors, ambitious fighters, champions |
| **Cruelty** | Atrocities, terror, ruthless choices | Cultists, sadists, the ruthless |
| **Mercy** | Sparing, healing, returning heirlooms | Outcasts, refugees, grateful survivors |
| **Forbidden Knowledge** | Rituals, tomes, magical events, grave secrets | Mages, scholars, occultists |

- No good-vs-evil meter — the axes are reputations, not morality. Cruelty and Mercy can coexist (feared *and* fair is a real medieval reputation).
- Recruit offers trigger on axis thresholds and pull from race/category pools weighted by which axes are high. The existing `RecruitGenerator` machinery (rarity weights, stat rolls, exceptional recruits, Barracks capacity gate) survives intact — only the *trigger* and the *weighting input* change.
- Encounters are the reputation engine. The wounded-orc template is canonical: help him (Mercy, maybe a future recruit), finish him (resources + a corpse, Cruelty), leave him (unknown outcome — he may survive, another faction may find him). One encounter, multiple stories, no obviously correct answer.
- Grave robbing gets the same treatment: raise the corpse / steal the valuables / return the belongings / destroy the evidence — each moving different axes.

---

## 8. Loot and relics

- **Mundane loot:** gold, resources, Dark Essence. **Dark Essence becomes field-loot only** — never worker-gathered, exclusively found out in the world. (Correction, 2026-08-06: this originally claimed field-only was "already a code convention" — it isn't. Workers have never gathered it, but bounties, missions, and events all grant it today; those sources are re-pointed or retired in R2, per `LOOT_SITES_SPEC.md` §5.) It is a *reason to leave*.
- **Relics:** rare finds — rings, noble seals, heirlooms, journals, tomes, weapons — with rarity tiers. Some grant in-run effects; all are stashable at run end (alive). Relics are the extraction layer's currency (§10).
- **Exclusivity principle:** the pull of exploration must be *exclusive*, not merely efficient. If workers can gather it at home, the player stays home. Reputation, Dark Essence, relics, recruits, and XP-bearing deeds are all field-only.

---

## 9. Meta-progression: XP, levels, unlocks, chronicle

**XP is banked the instant it is earned** — from discoveries, encounters resolved, buildings raised, battles won, reputation milestones, run endings. Never awarded only at run end: a death two hours in must still feel like a chapter, not a refund.

**Levels unlock variety, not power:**

- New **spells** (Command Undead is spell one; the pool grows)
- New **undead unit types** (the ghouls and wraiths already on the roster — `is_undead()` reads alignment from `races.json`, so they're commandable the day they exist)
- New **starting-item choices** and **relic slots** (§10)
- New **encounter-pool entries** (more possible stories per shuffle)

The hard rule from §2 repeated because it is the whole design: **unlocks widen the option pool; they never raise numbers.** This is Slay the Spire's model, it protects early-run tension forever, and it means multiplayer veterans have more options, not stat advantages.

**The chronicle.** Every run gets an epitaph, win or lose: *"Run 4 — slain by the church's hunters on day 6, having emptied eleven graves."* Cheap to build off the existing log patterns, and it reframes deaths as the legend accumulating. Displayed in the Lair.

---

## 10. The Lair (meta hub)

The main-menu home between runs — the Hades-house model. The chronicle made into a room.

- **The stash.** Relics extracted from runs live here permanently.
- **Decoration and trophies.** Mount the wolf's head; hang the lord's banner from the run you won. Placement reuses the existing settlement placement-mode code. Trophies are earned by specific feats, not bought.
- **Relic risk.** Starting a run, the player may carry stash relics in: **1 slot initially, unlockable to a maximum of 3.** Carried relics grant their in-run effects — and are **lost forever on death**. This is the extraction-genre tension grafted on: risk it or shelf it.
  - This is the one sanctioned bend of the variety-not-power rule. It is self-balancing through fear: the advantage is priced by what's on the line, and it only stays priced if slots stay scarce. Never exceed 3.
  - **Anti-hoarding lever:** a relic that survives a run it was risked in earns bonus XP and accrues legend (*"the blade seen at the sack of the manor"*). The museum shelf is a valid playstyle, but it should be the *boring* choice, not the correct one.
- **Later:** class selection (once the Demonologist exists), the unlock browser, run statistics.

---

## 11. Villain classes and multiplayer

**Villain classes are this game's Slay the Spire characters.** Each class has its own spell pool, unit roster, item pools, and XP track. The Necromancer is character one. **The Demonologist is character two** — a future *playable class*, not an AI rival. (An AI rival occupying the second lair is a possible later feature, but it is downstream of the class existing, not upstream.)

**Design constraint, effective immediately: no system may assume there is exactly one villain on the map.** Villain-specific state (position, hp, reputation, escort, class identity) lives on a per-villain object, never in global singletons. This single discipline keeps both the second class and multiplayer possible without designing either now.

**Multiplayer is noted and gated.** The shape is already visible — two players, two classes, one shuffled map, hidden starts, discovery of the other player as a memorable mid-run moment, then diplomacy/trade/betrayal/war — and it drops into the map doc's two-villain layout unchanged. No design or netcode work now; the per-villain-object constraint above is the entire present-day cost.

---

## 12. Impact on existing systems

| System | Change |
|---|---|
| `GameState` win condition | "Survive crusade AND Power threshold" → **Take the Manor** (§1). Power threshold survives as an escalation input, not a win gate. |
| `ThreatSystem` crusade | Becomes the run's climax event, tuned to the 1.5–2h arc. Throne loss remains a run-ending defeat. |
| `EventSystem` timed recruit offers | Replaced by reputation-threshold triggers (§7). `RecruitGenerator`, Barracks gate, offer-refresh machinery all survive. |
| `NecromancerToken` | Splits into data object + view (the documented migration trigger has fired — §5). Becomes directly controllable and killable. |
| `UndeadCommand` / `RallyPoint` | Basis for the sortie escort's automatic behavior. |
| Priority-list economy, morale/meals, housing | **Unchanged.** This is the self-managing base layer the rework depends on. |
| `Roaming.gd`, wolf/deer | Reused for world-map wildlife and patrol loops. |
| Reputation (currently a single value) | Replaced by the five-axis model (§7). |
| Save/load | **No longer optional.** Meta-persistence (XP, unlocks, stash, chronicle) is required by R5; mid-run save is a separate, later concern. |
| Map generation | New: 144×144 template + shuffle rules per the map doc. `ResourceField`'s fixed seeding becomes the lair-band seeder within it. |

---

## 13. Staged build plan

Same philosophy as the foundation reset: each stage is playable and proves something before the next begins. **R1 is blocked on nothing; R2+ each depend on the previous.**

**R1 — The world exists.** 144×144 map template (fixed layout, no shuffle yet), fog of war, the Necromancer as a controllable unit (data/view split first), camera follow, travel between lair and wilderness, sealed rival region, static village shell. *Exit: walk from the lair to the village and back inside the travel-time targets, fog clearing as you go, day/night pressuring the trip.*

**R2 — The world is worth exploring.** Danger bands, encounter sites, grave-robbing choices, mundane loot + first relics, carry capacity, the escort (auto-behavior via Command Undead orders), Raven passive pings, sortie deposit-at-lair. *Exit: a full sortie loop — out, choices made, loot home — is tense and repeatable; dying on a sortie is always traceable to a decision.*

**R3 — The world responds.** Five reputation axes moved by deeds, reputation-gated recruit offers replacing the timer, notoriety feeding patrol escalation. *Exit: a run reaches Era II — first recruit arrives because of something the player did, and the world is visibly more watchful.*

**R4 — The run is real.** Run start/end lifecycle, death = run over, flee-the-region option, crusade climax retuned, take-the-manor victory, map shuffle between runs. *Exit: a complete run is winnable in ~2h and losable honestly; a second run is recognizably different.*

**R5 — The legend persists.** Meta save file, XP-from-deeds, level unlocks (spells/units/items/encounters/relic slots), the Lair hub with stash, relic carry-in/loss, decoration, chronicle. *Exit: dying mid-run demonstrably wasn't a waste — XP banked, epitaph written, and the next run offers something new.*

**R6 — Later (each its own effort):** directed Raven + bounty observation, living village routines, AI rival in the sealed region, the Demonologist as a playable class, multiplayer.

---

## 14. Explicitly deferred

Demonologist (as class *and* as AI), multiplayer (constraint in §11 only), directed Raven scouting, Raven bounty observation, village daily routines, diplomacy systems, mid-run save, climate (still deferred from before), additional villain classes beyond the second.

---

## 15. Open questions / tunables

- Necromancer combat stats, and whether a protective aura applies inside his own lair.
- Raven ping cadence and pool (per day? per era? capped per run?).
- Reputation threshold numbers per axis, and decay (if any) within a run.
- XP curve and unlock ordering — which spell/unit is level 2's carrot?
- Flee-the-region mechanics: instant from anywhere, or must he physically reach a map edge? (Recommendation: physically reach the lair, then flee — keeps the return leg tense even when giving up.)
- Whether escort skeletons brought on sorties fully leave the labor pool (current Command Undead rule says yes — probably correct, "the dead can dig or they can fight").
- Relic effect design space — in-run passive effects vs. activated items.
- What the victory bonus for taking the manor actually is (XP multiplier? guaranteed relic? unlock acceleration?).

---

## 16. Amendments since R1 (2026-08-06)

R1 shipped to spec. During the post-R1 doc reconciliation, two decisions were made and three stale claims were corrected inline (marked "Correction, 2026-08-06" where they sit).

1. **Reputation ownership — confirmed per-villain.** The five axes (§7) live on the villain object, never in an autoload; today's single `GameState.reputation` int is legacy and is replaced, not extended, in R3. **Threat stays global** — it is world/escalation state, legitimately `GameState`'s. R2's bridge: site *notice* feeds `GameState.add_threat()` (escalation half) while axis consequences are recorded on the villain's deeds ledger (reputation half, `LOOT_SITES_SPEC.md` §6). R3 reads notoriety from the ledger, never from `GameState`. `CLAUDE.md`'s source-of-truth line was corrected to match.
2. **Bounty parties are on-map units.** The off-map/abstracted follower-travel path was deleted in R1 (commit `3023372`: "travel happens on the world map now, in view"). Era III bounty parties therefore travel the 144×144 map as visible units — larger build scope than the old abstraction, accepted for the sake of one travel model everywhere. §3 and §6 were amended; the Raven-as-bounty-observer deferral in §6 may not survive as a feature now that parties are watchable directly.
3. **Corrections for the record:** Dark Essence field-only was a design *goal*, not an existing convention (§8; cleanup scheduled in `LOOT_SITES_SPEC.md` §5). Walk speed 1.0 was an R1 *tuning outcome*, not a pre-existing value (§4). The map spec is `WORLD_MAP_PLAN.md`; the `.docx` is the archived original (header, §4).
