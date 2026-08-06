# Claude Code Prompts — Stage 4 (Command, Train, Trade) + Stage 5 scaffolding

Run **one at a time, in order**, from `C:\Users\sjodz\Warlords`. Same rules as the foundation prompts: each stage leaves the game runnable, ends with a smoke test, updates CLAUDE.md, and **commits with a descriptive message**. Playtest between prompts; feed failures back as targeted bug prompts with exact log output.

Design sources: `GAME_OUTLINE.md` Stages 4–5, `FOUNDATION_SPEC.md` for conventions, `RACES.md` for stats. The grudge/essence/bounty systems are one interlocking loop, so the order below matters: factions exist before bounties can tag them, bounties exist before bodies, bodies before the Altar has work.

Standing warning for every prompt: if the game ever launches as a blank window, check `scenes/Main.tscn` for its `script = ExtResource(...)` line before debugging GDScript (see CLAUDE.md).

---

## Prompt 6 — Factions & grudge scaffolding

```
Read CLAUDE.md and GAME_OUTLINE.md (Stage 5 and the multiplayer-architecture
section) before starting.

Build the faction/grudge layer that Stage-4 bounties will feed. Scope
tightly: data + state + HUD readout. No raids yet.

1. data/factions.json: this run's "good" factions. Seed two for now —
   the Church and a Noble House — each with id, display_name, a flavor
   line, and grudge_tier thresholds (Quiet 0-29, Noticed 30-69, Wrath 70+).
   Structure it so factions could be procedurally picked per run later
   (a "pool" concept in the JSON is fine even if the code loads all
   entries for now).

2. FactionSystem (new, follows the ThreatSystem ownership pattern):
   per-faction grudge meters. API: add_grudge(faction_id, amount, reason),
   grudge_tier(faction_id), peak_faction(). Emits EventBus signals on
   tier changes. Log every grudge change with its reason — the player
   should always be able to reconstruct "why do they hate me" from the
   History tab.

3. Rework GameState.threat to be DERIVED: global threat = the peak
   faction's grudge (keeps the existing HUD/tier machinery and
   ThreatSystem's crusade trigger working unchanged for now). Document
   that the Crusade becomes "the Church's endgame raid" in a later prompt.

4. HUD: replace the flat "Threat" readout with per-faction rows somewhere
   visible (faction name + tier word, e.g. "Church: Quiet"). Keep it
   compact.

5. Design constraint from the outline's multiplayer section: keep faction
   state on the faction objects, not scattered as globals. Player actions
   that touch factions should go through FactionSystem methods.

Smoke test: headless run, add_grudge via a temp harness, verify tier
signals fire, derived threat matches peak faction, HUD rows update.
Remove harness. Update CLAUDE.md. Commit.
```

## Prompt 7 — Bounty board rework & unlock

```
Read CLAUDE.md, GAME_OUTLINE.md Stage 4 (bounty section — execution
quality and thresholds), and RACES.md before starting.

Rework the old BountyBoard into the designed system and re-surface it in
the UI (the Bounty tab's locked placeholder goes away).

1. New Bounty model (extend scripts/bounty/Bounty.gd): type
   ("gathering" | "villainy"), target resource or effect, difficulty
   (1-10), duration, reward, faction_tag (nullable — which faction cares
   if this goes loud), and min_stats (dictionary like {"guile": 4},
   nullable). Harvest bounties come in the NEXT prompt — build the model
   so they slot in as a third type.

2. Eligibility + evaluation: Follower.evaluate_bounty now checks
   min_stats first (hard filter), then the existing trait/appetite logic.
   A posted bounty nobody qualifies for stays on the board — show it
   greyed with "no takers: needs Guile 4+" so the player understands.

3. Execution-quality roll on completion: success and stealth are SEPARATE
   rolls. Success = does the job get done (existing risk logic is fine).
   Stealth = clamp((relevant_stat - difficulty) * 0.15 + 0.75, 0.05, 0.95)
   — tune freely but keep it data-visible. On stealth failure AND a
   faction_tag present: FactionSystem.add_grudge(tag, amount, reason).
   Clean execution = zero grudge, per the design. Log both roll outcomes.

4. Gathering bounties: post a bounty for a resource (wood/stone/food/
   bones); an accepting follower runs REAL trips (the Laborer loop) for
   the bounty's duration with their own skills, then collects the reward.
   This is "entice the dwarf to out-mine your skeletons" — verify a
   Mining 8+ follower visibly outpaces a skeleton on the same deposit.

5. UI: Bounty tab gets: post buttons for 2-3 starter bounties (one
   gathering, one villainy with a faction tag), the open-bounty list with
   min-stat editors (SpinBox per stat is fine), and active-bounty status.

Smoke test: headless — post gathering bounty, follower accepts and
delivers; post villainy bounty with impossible min_stats, verify "no
takers"; force a stealth failure, verify grudge lands with reason logged.
Update CLAUDE.md. Commit.
```

## Prompt 8 — Harvest bounties, bodies, and the Dark Altar

```
Read CLAUDE.md, GAME_OUTLINE.md (special resources section), and
FOUNDATION_SPEC.md before starting. This is the run's core villainy loop:
bodies -> Dark Altar -> Dark Essence, and you can't get bodies without
risking grudges.

1. "Bodies" as a carried good: not a GameState resource — a physical
   payload like the deer. A harvest bounty sends a follower off-map
   (send_away/return_home pattern), and they come back carrying N bodies.

2. Harvest bounty variants (data-driven, in a new data/bounties.json
   that also absorbs the Prompt-7 starter bounties):
   - "Rob the church graveyard": 3 bodies, difficulty 5, faction_tag
     church, moderate duration.
   - "Scavenge the battlefield": 5 bodies, difficulty 3, faction_tag
     noble_house (they're his fallen men), longer duration.
   Balance intent: battlefield is more bodies and an easier stealth roll
   but angers the faction whose endgame raid is worse. Tune numbers
   freely; keep them in the JSON.

3. Dark Altar rework: unlock it in the build menu ("locked": false),
   REMOVE its passive dark_essence tick entirely, and give it a
   conversion queue: bodies delivered to the settlement are carried to
   the Altar and converted 1 body -> 2 Dark Essence over ~10s each
   (visible progress). No Altar built = bodies wait, with a log hint.

4. Essence sink placeholder: a "Rituals — coming soon" locked button on
   the Altar panel (same visible-promise treatment as the Barracks
   Upgrade button). Spells and advanced undead are later milestones.

5. Wire the loop end to end and verify the design's causality: the ONLY
   way to gain Dark Essence is harvest bounties -> bodies -> Altar.
   dark_essence starts and stays 0 until the first conversion completes.

Smoke test: headless — build Altar, post graveyard harvest, follower
returns with bodies, conversion produces essence; force a stealth fail
and verify Church grudge with reason "seen robbing the graveyard".
Update CLAUDE.md. Commit.
```

## Prompt 9 — Training centers (and the Blacksmith comes back)

```
Read CLAUDE.md and GAME_OUTLINE.md Stage 4 (training centers) before
starting.

1. Training Center building (buildings.json, buildable after Workshop):
   holds up to 3 training items. Items are data (data/training_items.json):
   weapon_rack -> Might, lockpick_set -> Guile, banner -> Influence.
   Each costs resources to craft (Blacksmith action for the weapon rack,
   plain resource cost for the others).

2. Passive training: IDLE living recruits (not skeletons, not workers,
   not busy followers) walk to the Training Center and train against a
   stocked item during downtime: +1 to the item's stat per full day/night
   cycle of accumulated training, cap +2 per stat from training total
   (soft cap so bounty-rolled stats stay meaningful). Show "[Training:
   Might]" in their status and a small progress readout in the roster.

3. Re-surface Forge Equipment (Blacksmith button) as the active
   counterpart: instant, targeted, costs Dark Essence — now it has a real
   economy behind it via the Altar loop.

4. Make training respect the priority system: a recruit only trains when
   the priority list has no under-threshold resource for them to serve —
   work first, gym second.

Smoke test: headless at 60x — stock a weapon rack, verify an idle orc
trains +1 Might over a cycle, caps at +2, and abandons training when the
wood threshold dips. Update CLAUDE.md. Commit.
```

## Prompt 10 — Market & trade missions

```
Read CLAUDE.md and GAME_OUTLINE.md Stage 4 (market & trade) before
starting.

1. Market building (buildings.json, requires Workshop): once built,
   settled recruits (house-dwellers, not Barracks residents) buy goods on
   a dawn tick: each spends nothing yet in currency terms — model it as
   the settlement converting 1 surplus Food or Wood per resident into a
   small trickle of a new "coin" GameState resource. Keep it deliberately
   simple; this is a placeholder economy to be deepened later. Coin shows
   in the HUD.

2. Trade mission: a Dispatch action (re-surface the Missions machinery
   for this one mission type): pick a follower, send them with N surplus
   resource to "the nearest town", duration scales with N, returns coin
   at a better rate than the market tick. Exposure: every trade mission
   rolls the same stealth mechanic as bounties against a random seeded
   faction at low difficulty — trade is how the outside world learns
   about you (reason: "strange goods traced back to your settlement").

3. The old missions.json content (Smuggling Run etc.) stays dormant —
   only the trade mission surfaces. Note in CLAUDE.md that classic
   missions return when relationships/parties land.

Smoke test: headless — build market, verify dawn coin trickle from
settled recruits only; run a trade mission, verify coin income and that
a failed stealth roll lands grudge with the trade reason. Update
CLAUDE.md. Commit.
```

## Prompt 11 (optional, when ready) — Relationships & departure memory

```
Read CLAUDE.md, GAME_OUTLINE.md (relationships & loyalty section), and
RACES.md (rivalry pairs) before starting.

1. Pairwise relationships: follower-to-follower value (-5..+5), seeded
   from RACES.md rivalry pairs (-3), good-vs-evil alignment (-1), else 0.
   Shared activity moves it: completing a bounty/trade mission together
   +1, a town friction event -1. Storage: dictionary on one side keyed by
   the other's id — keep it serializable.

2. Friction events: two co-located recruits at relationship <= -3 can
   fire a "started a fight in town" event (small morale hit to both,
   logged). Loyalty override: if both have Loyalty >= 7, the fight is
   suppressed with a log line about grudging professionalism.

3. Departure memory pays off: the dispositions recorded on send-away/
   desertion now drive two rare events — return-with-a-gift (positive
   disposition: rejoin offer with +1 to a stat) and ambush (negative:
   a follower out on a bounty takes a penalty, logged with the
   deserter's name).

Smoke test: headless — seed an orc and ogre, verify starting -3, force a
shared bounty to +/-, verify friction fires below -3 and is suppressed
at high loyalty; verify one gift return and one ambush from stored
dispositions. Update CLAUDE.md. Commit.
```

---

## Stage-4 exit criteria (prove it before Stage 5 raids)

1. Dark Essence is obtainable ONLY via harvest bounties → bodies → Altar, and the first essence arrives with a comprehensible risk story behind it.
2. At least one faction reaches Noticed purely from *your choices*, and the History log can reconstruct exactly why.
3. A clean-stealth run of 3+ bounties lands zero grudge (execution quality matters).
4. A Mining-8 follower on a gathering bounty visibly out-produces skeletons.
5. An idle recruit trains a stat while workers still respect priorities.
6. Trade produces coin and at least one "traced back to you" grudge event over a long session.
7. No soft-locks: no-takers bounties, Altar-less bodies, and full boards all message clearly.

After these pass, Stage 5 (endgame raids per faction, the Church's Crusade as one flavor) gets its own prompt set.
