# RAVEN SPEC — The Bird That Never Lies (R2)

**Status:** Draft for review, 2026-08-06. Details `ROGUELITE_REWORK.md` §6 and covers the R2 piece
`LOOT_SITES_SPEC.md` put out of scope. Nothing here is implemented.

> **Correction, load-bearing.** `docs/history/2026-08-world-map-r1.md` said, in its fog-of-war
> section, that *"the map doc's 8–12 is the Raven's scouting number, rework §6, and that's R2."*
> **That is wrong and this spec supersedes it.** `ROGUELITE_REWORK.md` §4 amendment 3 *replaced* the
> 8–12-cells-per-scouting-action model outright; §6 gives the Raven no reveal radius at all, and
> `WORLD_MAP_PLAN.md`'s own header already records the retraction. The Raven does not clear fog.
> **The history file's parenthetical was fixed and now points here** (2026-08-06 for the
> substance, prompt U1 on 2026-08-27 for the pointer). What stands above is the record of
> what it used to claim, not an open task.

**Scope:** what the Raven is in v1, the ping lifecycle, the honesty invariant, cadence and pool,
UI surface, and what is deliberately not built.

**Out of scope, specced separately:** what a pinged site actually yields (`LOOT_SITES_SPEC.md`),
the sortie that goes and gets it (`SORTIE_SPEC.md`), the escort (`ESCORT_SPEC.md`).

**Companion documents:** `ROGUELITE_REWORK.md` (§6, §14, §15), `LOOT_SITES_SPEC.md` (§2 site
catalog, §3 telegraphing), `WORLD_MAP_PLAN.md` (§8 fog and scouting — *as amended*), `CLAUDE.md`.

---

## 1. Design goals

1. **V1 is a passive ping system, and nothing else.** No token, no bird on the map, no directives,
   no scouting UI. Periodically a portrait icon appears with a marker: *the Raven found something.*
   Clicking centres the camera on it.
2. **Pings are always honest.** What the Raven reports is real, reachable, and worthwhile. It never
   baits, never exaggerates, never points at a trap. The familiar is the one thing in the world that
   is trustworthy — that contrast is what makes the world feel treacherous rather than merely
   hostile.
3. **It never finds the big stuff.** Minor finds only. A fresh grave, a small cache. If the Raven
   could point at the crypt, exploring would be a chore list rather than a risk.
4. **It does not solve fog of war.** Revealing the map remains the Necromancer's job, on foot, at
   risk — *his physical presence in the world is the whole point*
   (`ROGUELITE_REWORK.md` §4 amendment 3). A ping shows a marker, not terrain.
5. **Dangerous surprises live only in self-found discoveries.** The ~90/10 worthwhile-to-surprise
   ratio (`ROGUELITE_REWORK.md` §6) applies to what the *player* uncovers. Raven pings are 100%
   worthwhile, by rule.

---

## 2. What a ping is

A ping is **a pointer to an already-placed site**, not a spawn. The world's sites exist from run
start (`LOOT_SITES_SPEC.md` §2 places a fixed hand-authored set in R2); the Raven surfaces one the
player hasn't found yet.

```
ping = { site: WorldSite, day_found: int, seen: bool, claimed: bool }
```

That framing is what keeps honesty cheap: the Raven cannot promise something the world doesn't have,
because it only ever names things the world already has.

**Eligible sites** — the pool is narrow on purpose:

| Eligible | Not eligible | Why |
|---|---|---|
| `fresh_grave` (Band 1) | anything Band 3 or 4 | it never finds the big stuff |
| `small_cache` (Band 1) | any site with a `guardian` | pings are never dangerous |
| `abandoned_camp` **only when its occupancy roll came up empty** | any site the player has already discovered | a ping is news |
| | `cemetery`, `crypt`, `outlaw_cave`, `cursed_battlefield` | Era-III and deep-danger business |

`LOOT_SITES_SPEC.md` §2 already calls `small_cache` "Raven-ping fodder" — this is the rule behind
that line. The camp exception is the interesting one: occupancy is rolled at *activation*, so the
Raven can honestly know the camp is empty in a way the player cannot. **That asymmetry is the
Raven's entire value proposition**, and it is worth more than any reveal radius.

---

## 3. Lifecycle

```
dawn → cadence check → pick an eligible undiscovered site → ping appears
     → portrait icon + marker on world and minimap + one History log line
     → player clicks the icon: camera centres, ping marked seen
     → player walks there and loots it: ping claimed, marker clears
     → (never expires)
```

**Pings do not expire.** A ping is information, and information doesn't rot — expiry would only
teach the player to drop everything and run at every icon, which is exactly the frantic pacing the
push-your-luck loop doesn't want. The marker sits there being a standing invitation.

**Cap: 3 unclaimed pings.** At the cap the Raven stops finding things until one is collected. This
is the pressure valve — a player who ignores the bird stops getting told, and the icon quietly says
so (*"She has nothing new to tell you."*). It also means the marker layer never becomes clutter.

**Cadence: one ping per game day, rolled at dawn**, `RAVEN_PING_CHANCE_PERCENT` at **70%** so days
without news exist. `ROGUELITE_REWORK.md` §15 lists cadence as open (*per day? per era? capped per
run?*); this spec answers **per day, capped at 3 outstanding, uncapped per run**, and flags the
numbers as tunables. Rationale: the day is already the clock everything else pressures against, and
tying the Raven to it means the bird participates in dusk pacing for free — the same way travel does.

**Reveal on ping: none.** The marker is drawn over fog. The player learns *where* without learning
*what is on the way*, which is the correct division: the ping is a destination, the journey is
still unknown country.

---

## 4. The honesty invariant

Stated as a rule a harness can assert, because it is the one thing that must never drift:

> **A pinged site must, at the moment of pinging, be: reachable on walkable terrain, in Band 1 or 2,
> free of guardians and occupants, undiscovered by the player, and hold at least one unclaimed
> charge.**

If no site satisfies all five, **the Raven says nothing that day.** It does not relax a condition to
produce content. A silent day is a correct day.

The one thing a ping does not promise is *safety of the route*. The Raven vouches for the
destination, never the road — the wolf, the dusk, and the ridge are all still yours. That distinction
is worth putting in the flavour text.

---

## 5. UI surface

**The icon.** A portrait chip in the HUD (the Necromancer portrait pattern already exists in
`HudTopBar`), appearing with a soft pulse when a ping lands. Shows the count when more than one is
outstanding. Clicking cycles: first click centres on the newest unseen ping, subsequent clicks walk
through the rest.

**The marker.** Drawn on the world at the site's position and on the minimap, **above fog**. A
distinct shape from the lair ring and the villain dot — the minimap deliberately carries no live
contents (`2026-08-world-population-r1.md`), and the Raven is the sanctioned exception because it is
*intelligence you were given*, not the world leaking through the fog. Note that exception in the
minimap's header comment when adding it, so the next reader doesn't "fix" it.

**The panel.** The ping is inspectable through the existing `get_inspect_data()` contract:
title (*"The Raven's Word"*), the site's name, its band, distance and rough travel time from the
lair (`TravelLog` already computes in game-seconds), and a flavour line. No new panel.

**The log.** One History line per ping. Pings are pacing information, not alerts — same call
`TravelLog` made about milestones.

---

## 6. What is deliberately not built

Straight from `ROGUELITE_REWORK.md` §6 and §14, restated so nobody rebuilds them by accident:

- **Directed scouting** ("scout that area"). Post-v1. When it arrives, the design hook to build it
  around is the choice *"is the Raven scouting ahead of you, or watching home?"*
- **The Raven as an observer on bounty parties.** Deferred — **and note it now conflicts with the
  code**: commit `3023372` (2026-08-05) deleted the off-map follower path on the grounds that
  "travel happens on the world map now, in view, so that mode no longer exists." §6's
  watching-a-distant-bounty role assumes off-map parties. Resolve that before scheduling it; it is
  not an R2 problem, but it is a rework-doc problem.
- **A Raven token.** No bird on screen. If one ever ships it is decoration, and it must not become a
  thing the player positions.
- **Any fog interaction whatsoever.** See the correction at the top of this file.
- **Dishonest or trapped pings.** Not a tuning knob. If the design later wants a treacherous
  familiar, that is a different familiar for a different villain class.

---

## 7. Data schemas

**`data/world_sites.json`** — one optional flag on the `lootable` block from
`LOOT_SITES_SPEC.md` §8:

```json
"lootable": {
  "type": "small_cache",
  "raven_eligible": true
}
```

Defaults to `false`. Eligibility is data rather than a hard-coded type list so that the Raven's pool
is authored alongside the sites themselves, and so R4's shuffle can vary it without touching code.
The §4 invariant is still enforced in code at ping time — the flag says *may*, the invariant says
*must*.

**No `raven.json`.** Cadence and cap are rules, not content, and live as constants.

---

## 8. Code touchpoints

| Where | Change |
|---|---|
| New: `scripts/world/Raven.gd` | The whole system: dawn cadence roll, eligibility filter enforcing §4's five conditions, the outstanding-ping list, cap. Takes `villain`, `world`, `world_sites` and `fog` as fields — **per-villain, never looked up** (`ROGUELITE_REWORK.md` §11); a second villain has a second familiar. Subscribes to `EventBus.dawn_started`. |
| `WorldSites.gd` | `undiscovered_eligible(fog) -> Array` — the candidate query. Nothing reaches into `sites` directly, as now. |
| `FogOfWar.gd` | **Read-only** from here: `state_at()` / `is_visible_at()` answer "has the player found this". Nothing in this spec calls `reveal_permanently()` or touches `REVEAL_RADIUS_CELLS`. |
| `WorldSite.gd` | `raven_eligible: bool` from the JSON block; `discovered: bool` set when first inspected in reach. |
| `EventBus.gd` | `raven_pinged(villain, site)`, `raven_ping_seen(villain, site)`, `raven_ping_claimed(villain, site)`, `raven_silent(villain, day: int)`. Watch arity (CLAUDE.md gotcha). |
| `HudTopBar.gd` | The portrait chip and its count; click cycles to `GameCamera.center_on()`. Reuse the follow-camera drop rule — centring on a ping is a manual camera move and should drop villain-follow exactly as an arrow-key pan does (`2026-08-villain-split.md`). |
| `Minimap.gd` | Ping markers above fog, with a header comment recording why this is the one live-contents exception. |
| `InspectionPanel` | Ping payload via the existing contract. No new panel. |
| `Main.gd` | Wiring only. |

---

## 9. Verification and tunables

**Harness** `tools/verify_raven.tscn`, headless as a scene (not `-s`):

- **the honesty invariant, as five separate assertions** — over 1,000 simulated dawns, no ping is
  ever emitted for a site that is Band 3+, guarded, occupied, already discovered, or out of charges
- an occupied `abandoned_camp` is never pinged; an empty one is eligible
- the cap holds: with 3 outstanding, no fourth ping lands until one is claimed
- with no eligible site, the day passes silently and `raven_silent` fires — **no ping is invented**
- cadence lands near 70% of days over 1,000 dawns
- **fog state is byte-identical before and after 1,000 pings** — the Raven cannot reveal anything
- a claimed ping clears its marker; markers draw above fog on both world and minimap
- centring on a ping drops villain-follow

**Needs a human:** whether an icon appearing mid-sortie reads as an invitation or an interruption,
and whether 70%/day is generous or noisy.

**Tunables:**

- `RAVEN_PING_CHANCE_PERCENT` (70) and the dawn cadence — `ROGUELITE_REWORK.md` §15's open question,
  answered here provisionally
- `MAX_OUTSTANDING_PINGS` (3)
- whether the pool should widen with in-run reputation once R3 exists (*a more notorious villain has
  a better-fed bird*) — attractive, and explicitly **not** in R2
- whether a ping should carry a rough distance or an exact one (currently exact; exact is friendlier
  and the walk is the cost either way)

**Exit criterion for this slice** (feeds R2's overall exit): three consecutive game days produce at
most three honest pings, each one a real minor site the player had not found, none of which reveals
a single cell of fog — and ignoring the bird entirely costs the player nothing but opportunity.
