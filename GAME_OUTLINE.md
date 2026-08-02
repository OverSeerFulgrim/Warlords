# Game Outline — Undead Empire (working title)

Design outline for the core game structure, v4 — adds relationships/loyalty, execution-quality grudges, bounty board thresholds, and the Dark Altar body-conversion loop.

> **Current roadmap focus: Stages 1–3 only** (collect → build → recruit & settle). Concrete baseline values live in `FOUNDATION_SPEC.md`. Bounty board, missions, training, market/trade, grudges, and spells are hard-locked until a Stage 1–3 run is smooth. The Barracks Upgrade button exists in UI but is hard-locked as a roadmap placeholder. `CLAUDE.md` covers the code; this file covers *what the player does and in what order*. Where this file and the code disagree, this file is the target — "Implementation gaps" at the bottom lists where the code hasn't caught up.

## Concept in one line

A villain-power-fantasy roguelite settlement builder: you are the Necromancer the "good" nations fear. Grow a hidden undead settlement from a lone throne into an empire strong enough to survive whatever your own infamy summons.

## Design pillars

1. **You are the threat — and you choose who hates you.** The world reacts to *what* you do. And you *must* do villainy: your special resource only comes from crossing someone.
2. **Indirect control.** Followers are individuals with traits and loyalty — you post bounties, set priorities, and assemble parties; you don't order units around.
3. **Earn it in stages.** Labor before buildings, buildings before followers, followers before adventure.
4. **The town grows organically.** Recruits arrive at the Barracks, then move out and build their own homes. Who joined you — and who gets along — shapes the settlement.
5. **Villains are factions too.** Every faction runs on the same interface, so a rival villain can be AI *or another player* later.
6. **Bright villainy, not grimdark.**

---

## Resources

| Resource | Source | Used for | Notes |
|---|---|---|---|
| **Wood / Stone** | Workers (priority list), gathering bounties | Construction | Mundane materials |
| **Bones** | Map nodes (animal carcasses in forests; uncommon graves by roads, ruins, village outskirts), later harvest bounties | Workers, undead costs | Finite on the map — bounties become the scalable source |
| **Food** | Foraging buildings, workers, trade | Feeding recruits | **Undead don't eat.** The Necromancer's food need is minimal — only living recruits (orcs, goblins, gnomes…) eat. Other villain classes need much larger food economies. **No food → morale drops → recruits steal, break your rules, or leave.** |
| **Dark Essence** (special) | **Harvest bounties only** — fresh bodies | Advanced undead, spells, forging | See "Special resources" below. Never gathered by workers, never produced passively. |

## Special resources (the anti-turtle engine)

Every villain class has a **special resource** that gates its advanced tier — and it can *only* be obtained by sending recruits out into the world, which starts grudges. **You cannot reach the endgame without making enemies.**

- **Necromancer — Dark Essence,** harvested from fresh bodies. The bodies must come from somewhere; it's only a matter of *who you're willing to cross*:
  - Church graveyard at night → Church grudge if seen.
  - A fresh battlefield → a Nobleman grudges you for stealing his fallen men.
  - **Bodies are physically brought back** to the settlement and converted to Essence at the **Dark Altar** — which is also where spell upgrades happen once spells exist. (No passive Essence production; the Altar is refiner + spell hub.)
  - No Dark Essence = no advanced undead, no spells. Turtling starves your class identity.
- **Criminal Syndicate — Respect.** Criminal activity *costs* Respect (the organization won't take bounties for a boss without standing); robbing a noble or moving a big black-market load *earns* it.
- Each villain class gets its own resource + risk/reward sources, designed on this pattern.
- **Trade rule:** special resources can only be traded between villains who *share* that resource (a Dark God Cult also runs on Dark Essence → natural trade partner for the Necromancer; the Syndicate can't buy Essence).

---

## Recruitable races

### Categories

Races are categorized by what they offer so recruitment events can be balanced — a first-time run is **guaranteed offers spanning the categories** (at minimum one warrior, one economy, one research race) so new players see the full scope.

| Category | Races (initial list) | Their unique buildings offer |
|---|---|---|
| **Warrior** | Orc, Ogre | Combat — but *different* buildings per race (e.g. Orc war-camp vs Ogre siege-works) |
| **Economy** | Gray Dwarf, Minotaur | Production/market buildings |
| **Research** | Gnome | Tech/spell support (Laboratory) |
| **Foraging** | Goblin, Gnoll | Superior food/gathering buildings (e.g. Goblin Wolf Hunter Lodge) |

### Race rules

- **Everyone can fight and take bounties** — race sets *baseline stats*, not permissions. An orc will almost always be stronger than a gnome; a dwarf's mining stat dwarfs a skeleton worker's.
- **Gathering bounties:** bounties can target resource gathering, not just villainy — entice the dwarf to help with stone and he'll out-mine your whole worker pool for a while.
- **Rivalries:** some races don't get along. Ogres and Orcs get aggressive and territorial with each other — you *can* recruit both, but expect "they started a fight in the middle of town" events. Rivalry pairs are data, defined per race.

### Relationships & loyalty

- **Every recruit keeps a relationship bar with each character they've interacted with** (shared bounties, missions, town events, fights). Some pairs just work better together — party synergy should reflect it.
- Race rivalry sets the *starting* relationship, not its ceiling — an orc and an ogre who survive missions together can grind past it.
- **Loyalty to you is the override:** when you assign a party containing characters who dislike each other, their Loyalty decides whether they set differences aside for what you want done. High Loyalty = grit teeth and work; low Loyalty = friction, mission penalties, or refusal — and town fights.

---

## General outline (the arc of a run)

| Act | Player experience | Systems in play |
|---|---|---|
| **1. Arrival** | Throne built, one skeleton worker, a starting pool. Set the resource priority list. | Workers, priority-driven gathering |
| **2. Foundation** | Build the **Barracks** early — recruit intake. Economy + food buildings follow. | Building placement, prerequisites |
| **3. Recruitment & settling** | Events bring category-balanced recruits to the Barracks. Feed them, fund their houses, watch rivalries. | Events, intake, food/morale, organic housing, race unlocks |
| **4. Villainy & economy** | Harvest bounties for Dark Essence (choosing whom to cross), missions, training, market, trade. | Bounties, missions, training centers, market/trade, grudges begin |
| **5. Reckoning** | The factions you wronged mount the endgame raid. Survive with the Throne standing + hit the Power threshold. | Faction grudges, endgame raid, win/loss |

---

## Core loop: staged flow (what you do)

### Stage 0 — Arrival (automatic)
Throne of Bones (main building, hp — the raid's target), **1 skeleton worker**, starting resource pool.

### Stage 1 — Collect resources (priority list)
- **Global priority list, not per-worker orders.** Bottom-bar menu ranks resources; each has a player-settable **threshold** — once stock ≥ threshold, workers fall through to the next priority, returning whenever spending dips it back under.
- Recruit more workers (Bones cost). Undead workers need no food.
- *(Per-worker manual override is a possible later add.)*

**Gate → Stage 2:** afford your first building (economy-enforced: starting pool covers the Barracks *or* one cheap economy building, not both).

### Stage 2 — Build
1. **Barracks** — recruit intake. **Only one, ever — but upgradeable** to raise its population cap (base 5 → upgrade tiers).
2. **Economy & food** — Bone Pile; early food source (forage hut or similar) before living recruits arrive.
3. **Tech** — Workshop → Blacksmith, Training Centers.

Every building adds **Power** (the win stat).

**Gate → Stage 3:** Barracks built → recruitment-event timer turns on.

### Stage 3 — Recruit & settle
- Events deliver recruits into the Barracks, **category-balanced** (first run guaranteed warrior + economy + research offers). Each recruit: name, race, traits, Might/Guile/Influence/Loyalty seeded from race baselines.
- **Feed them.** Living recruits consume Food on a tick. Shortage → morale drops → theft, rule-breaking, desertion events.
- Per Barracks resident, you can:
  - **Let them stay** (occupies a slot),
  - **Send them away** — but departures have memory: depending on how you handled it, they may **return later with a gift** to prove their worth, or **hate you** and ambush your villagers out on bounties.
  - **Fund a house** — pay the cost; they build a home *themselves, somewhere nearby of their choosing*. Frees the slot; the town grows organically.
- **Races unlock unique buildings** in your build menu once settled (per the category table). Rivalry pairs living together generate friction events.

**Gate → Stage 4:** roster ≥ 1.

### Stage 4 — Command, train, trade
- **Bounty board (indirect):** followers choose bounties by traits/stats. Types now include:
  - **Harvest bounties** (the Dark Essence source) — each variant crosses a different faction (graveyard → Church, battlefield → Noble). Bodies are carried home to the Dark Altar for conversion.
  - **Gathering bounties** — resource help from stat-appropriate recruits.
  - Classic villainy bounties (raids, thefts) — grudge-tagged per target.
- **Grudge comes from getting caught, not from the act.** A perfectly executed bounty can accumulate *zero* grudge. Noisy grave-digging, evidence left behind, a witness — an **execution-quality roll** (recruit skill vs bounty difficulty) decides whether the tagged faction actually notices. Better recruits don't just succeed more; they keep you invisible longer.
- **Bounty board settings:** per bounty, set **minimum skill thresholds** (e.g. Guile ≥ 4). Higher thresholds mean cleaner jobs but drastically shrink the pool of recruits willing/able to take it — a posted bounty nobody qualifies for just sits there.
- **Missions (direct):** hand-picked parties, stat checks.
- **Training centers (passive):** stocked with items; recruits train in downtime. Item type → stat (weapon racks → Might, lockpicks → Guile, regalia → Influence).
- **Market & trade:** you own the market; recruits buy wares (local economy loop). Trade missions sell surplus to outside towns — income plus exposure/relations effects. Special-resource trade only with same-resource villains.

### Stage 5 — Escalate and survive
- Each run procedurally spawns "good" factions (Church, Noble House, Merchant League, Paladin Order…) and possibly **rival villains** (Criminal Syndicate, Dark God Cult…).
- **Per-faction grudge**, fed by tagged actions *that get noticed* (execution-quality roll — see Stage 4). Grudge tiers: Quiet → Noticed → Wrath. Peak-grudge faction mounts the **endgame raid** (Crusade if it's the Church; noble host, mercenary army, etc. otherwise). Multiple angry factions scale the raid.
- Because Dark Essence requires harvest bounties, **grudges are effectively unavoidable over a run** — clean execution delays exposure, but volume catches up. The choice is *whose* grudge, and *how fast*.
- **Win = both:** survive the raid with the Throne standing **and** reach the Power threshold.

### The loop in one line

> Set priorities → gather → Barracks → recruits arrive (fed, housed, sometimes feuding) → harvest bounties for your special resource → grow Power → manage *whose* grudge you're feeding → survive their raid → win.

---

## Multiplayer-minded architecture (design now, build later)

- **Everything is a Faction** — good nations, your settlement, rival villains — one interface: goals, resources (including special resource), relations, grudge. Villain-to-villain: trade (same-resource rule), mercenary services, joint plots, or raids.
- Rival villains spawn per run as AI long before netcode exists.
- **Code implications, adopt now:** per-faction state (not one-player singletons), deterministic data-driven ticks, serializable state, player actions as **commands** ("post bounty X", "fund house Y") rather than direct mutation.

---

## Implementation gaps (current code vs this outline)

1. **Worker priority list** — replace per-worker cycle buttons with global ranked priorities + thresholds; `WorkerSystem._gather_tick()` assigns from the list.
2. **Barracks redefinition** — single, upgradeable intake housing (cap 5 base). Training moves to Training Centers. Recruitment gates on Barracks capacity, not species housing.
3. **Food + morale** — new resource; per-recruit consumption tick (undead exempt); morale stat with theft/rule-break/desertion events on shortage. Foraging buildings as source.
4. **Fund-a-house flow** — per-recruit action, cost, self-placed house, frees slot.
5. **Race data rework** — `followers.json` → race table with category, stat baselines, unique-building unlocks, rivalry pairs. Event balancer guarantees category spread on first run.
6. **Departure memory** — sent-away recruits stored with disposition; return-with-gift or ambush events.
7. **Dark Essence source rework** — remove passive Dark Altar production and starting-stash reliance; harvest bounties yield **bodies** (a carried good), converted to Essence at the Dark Altar. Altar doubles as spell-upgrade building later.
8. **Gathering bounties** — bounty type targeting a resource, payout scaled by recruit's relevant stat.
9. **Faction/grudge system** — per-faction grudge meters; grudge applied only when the **execution-quality roll** fails (recruit skill vs bounty difficulty). Endgame raid from peak faction; Crusade = Church flavor.
10. **Bounty board thresholds** — per-bounty minimum stat requirements; eligibility filter in follower evaluation (`Follower.evaluate_bounty`).
11. **Relationship system** — pairwise relationship values updated by shared activity; race rivalry sets initial value; party assembly checks relationships, with Loyalty as the override that suppresses friction.
12. **Training centers, market, trade missions** — new systems per Stage 4.
13. **Remove the 3 seeded starting followers**; start with 1 skeleton worker.
14. **Faction refactor of GameState** — incremental, but all new systems written per-faction from day one.

Suggested order: **1 → 2/4 (intake loop) → 13 → 3 (food/morale) → 5 → 8 → 7+9+10 (essence/grudge/board — one loop) → 11 → 6 → 12 → 14 ongoing.**

## Out of scope (still)

Climate, multi-settlement, actual netcode, save/load (serializability is a design constraint now), real (.tscn) UI.

## Open questions

- **Morale scope** — per-recruit morale stat, or one settlement-wide meter? Per-recruit is richer (the hungry ogre riots first) but more UI.
- **Barracks upgrade tiers** — how many, what costs, what cap per tier (e.g. 5 → 8 → 12)?
- **Food consumption rate** — per recruit per tick? Do bigger races (Ogre) eat more?
- **Priority thresholds UI** — typed numbers or Low/Med/High presets?
- **Which stat drives execution quality?** Guile as the default stealth stat, or per-bounty (a battlefield harvest might roll Might — muscle the bodies out fast)?
- **Relationship visibility** — full pairwise grid in UI, or only surfaced when relevant (party picker warnings, event popups)?
- **Bodies as cargo** — do bodies have weight/capacity (an ogre hauls more corpses than a goblin), or abstract count per bounty?
