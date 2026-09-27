# LIVING WORLD SPEC — The Guild Opening, Settlement Symmetry, and Faction Ecosystems

**Status:** Design target, agreed in discussion 2026-09-26; **all rulings issued the same day (§15) —
1–12, then 13–15 (the L0 model) — ready for L0/L1 prompts.** Not yet prompted. The first pieces are already
in the game: no starting skeleton on any run, Raise Dead as his starting spell, 3 starting bones,
the Dark Altar locked, and death ending the run with XP banked
(`docs/history/2026-09-26-run-lifecycle-and-raise-dead.md`). Amends `ROGUELITE_REWORK.md` where marked (§13) and **pulls "living village
routines" forward from the R6 deferral** into a staged build that starts alongside R3. Everything
numeric here is a playtest hypothesis and should be read from data.

**Companion documents:**
- `ROGUELITE_REWORK.md` — the run frame, Eras, five reputation axes, meta-progression rules. This
  spec lives inside that frame; §13 lists the amendments it requires.
- `COMBAT_SPEC.md` — §5 morale/rout is the base this spec's downed/capture layer (§11) extends.
  Slice C3 (morale, judgement, packs) is the natural carrier.
- `LOOT_SITES_SPEC.md` §6 — the deeds ledger and the witness principle ("threat lands only when the
  witness reaches a settlement"). §8 here is that principle built out.
- `RACES.md` / `data/races.json` — the roster this spec sorts into settled / camp / wandering (§6).
- `GAME_OUTLINE.md` — the Dark Altar body-conversion loop, which §10's sacrifice rule extends.
- `WORLD_MAP_PLAN.md` — the lordship / wilderness / lair regions the guild and camps are placed in.

---

## 0. Why

Two findings from the 2026-09-13 demo review and the 2026-09-26 discussion:

1. **The early game gives no reason to leave the lair.** R2 makes the world *lootable*; it does not
   make it *legible*. A first-time player standing at the lair edge has nothing pulling him down the
   road.
2. **Nothing outside the lair moves on its own.** The village is a shell. Roads carry nobody.
   Without other actors running their own loops, the Necromancer is the only predator, and a world
   with one predator is a colony sim with a longer commute.

The fix is one structural rule (§2), one opening (§3), and one faction template (§5) applied to
every race that has a home. Everything else in this document falls out of those three.

---

## 1. The design in one paragraph

You wake on a roadside in Era I, unknown, with nothing. A sign points down the road to the
**Adventurers' Guild**, a neutral mercenary hall that takes coin from anyone and doesn't know what
you are. Past the guild are graves; you raise your first dead on the way to your first job. You do
the guild's bounties in disguise, and every job is a cover for the real payout: the corpses. Around
you, human villages, goblin camps, and bandit holds run the **same settlement system your own town
runs**, working fields, cutting wood, raiding each other, burying their dead, and sending caravans
down the road. You are one predator in that food chain. Slip up in front of a witness and your
standing with the guild drops; when the guild finally *knows*, its doors close, and you have to
build. Every building you flip teaches you its blueprint forever. Every run, you know more, even
when you die.

---

## 2. The one rule: Settlement symmetry

> **There is one Settlement system. The player's town is a settlement whose owner is the villain.**

- One `Settlement` model, one `Building` class, one job-slot/production system, one population
  model. `owner` is a parameter (per-villain discipline, same as reputation and the deeds ledger).
- **Ruled (§15, no. 13): each settlement owns its own stockpile** — resources, population/followers,
  and Power. `GameState` becomes a **façade over the player's settlement**, so the HUD and every
  existing caller keep reading `GameState` unchanged. This retires `CLAUDE.md`'s "GameState is the
  single source of truth" convention when L0 lands; until then that convention stands.
- Every building specced for an NPC faction is a building the player can eventually own. Every
  building already built for the player (Barracks, Workshop, Laboratory, Dark Altar, houses) is NPC
  content the day a faction is given a blueprint list.
- **Flipping a settlement is changing `owner`.** Capture is not a special case; it is the field
  write plus whatever the new owner does with the population left standing (§9).
- Corollary for scope: this is what makes ecosystems affordable for one developer. There is no
  second economy to build. The AI faction is a settlement with a decision loop bolted on.

---

## 3. The opening

**Ruled 2026-09-26: roadside spawn; first run starts with no Altar and no skeletons.**

> **Built so far (2026-09-26):** no starting skeleton on any run; the Dark Altar is locked (not a
> starting building); **Raise Dead is his starting spell** — a grave's corpse is raised free at the
> graveside, and without a corpse it costs 5 bones anywhere; he starts with 3 bones, so the first
> dead come from a grave. He still starts **at the Throne**, and the graves are the fresh graves
> north-west of it; the roadside spawn, the guild, the popup and the Altar-in-the-den are L2.

- **Spawn:** the Necromancer starts at the roadside at the edge of the lair region, the lair a
  marked site a few cells off the road. The Throne and the Raven are at the lair. **No starting
  skeletons.** The road is the first thing on screen.
- **First-run popup** (placeholder for a tutorial): *"Follow this road to the Adventurers' Guild."*
  Nothing more.
- **The first bounty is the tutorial.** The board's first job is *clear the wolf den*. The den is
  past the guild; **between the guild and the den are graves** — the player raises his first dead on
  the way to his first fight. Command Undead is learned by needing it.
- **The Dark Altar blueprint is inside the den.** The first run has no Altar until the den is
  cleared; from then on the blueprint is known (§12) and the Altar is built each run.
- **Later runs:** the popup does not repeat. Whether the player walks to the guild at all is a
  choice once blueprints have accumulated — the guild phase is expected to shrink across runs, not
  be removed. **Ruled: every run starts without a skeleton.** The roadside graves are the run's
  first source of dead, on run one and run fifty.
- **The road** runs lair-edge → Guild → graves → village → map edge (the trade road, §7). The guild
  sits on it deliberately: caravans pass its door.

---

## 4. The Adventurers' Guild

A **neutral faction** ("Guild"), distinct from the Lordship and the Church. It owns one building on
the road and posts the region's bounties.

### 4.1 Standing

Guild standing is a **per-faction disposition, per-run**, separate from the five reputation axes.
The axes say what the world whispers about you; standing says what the guild is currently prepared
to do with you. Three tiers, no number shown:

| Tier | Access | Moves down when |
|---|---|---|
| **Unknown** | Full board, normal pay, no escort | a witness reaches a settlement (§8) |
| **Suspected** | Board open, worse pay, an escort sent with you, the board starts listing "strange sightings" | a second confirmed report, or an adventurer's report (§8.2) |
| **Known** | Doors shut, a bounty on *you* is posted, adventurer parties leave the guild hunting | — |

- **Ruled: standing never recovers within a run.** The guild forgets nothing. It is also the
  cheapest option to build: a tier that moves one way, no timer, no counter. Protection against
  losing it is the mask (§8.6), which costs gold, not time.
- **Ruled: Known is a hard door for the guild.** Bandits are the fence (§10.3).
- **Ruled: Known is one Era II trigger, not the only one.** The doors closing *is* the transition
  from "hide" to "build", but deeds on the five axes can bring Era II on their own.

### 4.2 The board

Bounties are **generated from world state**, not hand-authored (a hand-authored first list is fine
for the first playable, but the data shape must be the generated one from day one):

| Bounty | Generated when | Typical taker |
|---|---|---|
| Clear the den | a den spawns | any adventurer; **the player's first job** |
| Punish the raiders | goblins/bandits hit a farm, road, or caravan | fighters |
| Escort the caravan | a caravan was lost (§7.3) | fighters |
| Bring back N of X | a village runs short of a material | low-level |
| **Forage** — berries, mushrooms | the market or a village needs potion stock (§5.8) | **low-level adventurers, druids** |
| **Recover the badge** | an adventurer is MIA (§4.4) | mid-level |

Bounties are the guild's view of the ecosystems in §5. If nothing in the world is wrong, the board
is thin. That is correct.

Adventurers take bounties too. The player competes for them, and an adventurer walking out to a
den is a body on the road, whoever wins.

### 4.3 What the guild is really for

The guild is **the player's introduction to the bounty board they will eventually own**. Era III
already has bounty parties operating from the player's settlement as visible units
(`ROGUELITE_REWORK.md` §16.2). This spec makes the early game the same mechanic from the customer
side. Three-act shape, one building:

1. Early: you take their scraps, in disguise.
2. Middle: they post a bounty on you.
3. Late: you post bounties on them, from your own board.

### 4.4 Being an adventurer is dangerous: MIA and the Guild ID badge

Every bounty has a **due date**. An adventurer who took a job and has not reported in by the due
date is **MIA**, and the board generates a **Recover the Guild ID badge** bounty.

- Every adventurer carries a **badge**. It is the guild's proof of death; recovering it is what the
  guild pays for.
- **Bodies move.** Scavengers eat them, goblins drag them to camp, the player raises them. The badge
  is wherever the body (or the captor) is now. The adventurer **may still be alive**, a prisoner of
  goblins or bandits (§10) — then the bounty resolves as a rescue.
- The guild **sells a finder** — an item that points toward a named badge, **anywhere on the map**
  (ruled). There is no distance at which a carried badge stops being a heading to your lair.
- Consequences that fall out, no code of their own:
  - Adventurers the player kills become MIA on schedule, and the player can take the recovery job
    for his own victim.
  - **Badges are trackable.** A player who loots badges and carries them home has given the guild a
    heading to his lair. Return them, sell them, or drop them — never stockpile them.
  - The finder is a player tool too: buy one to find an adventurer's body before the scavengers do.
- **A badge is an item: pick it up, carry it, drop it anywhere.** The finder points at the badge,
  not the body, so **wherever the badge lies is where the recovery party goes.** Drop it at the edge
  of a goblin camp and the guild sends warriors into the goblins; drop it on a bandit hold and two
  factions that were leaving each other alone start a war. This is the player's first tool for
  making the world fight itself, and it costs nothing but the walk.
- **Later unlock (XP tree): the Raven carries the badge.** The familiar flies it to a chosen
  location, so the false flag can be planted without the Necromancer walking into the place he is
  framing. Same rule for anything else small enough to fly with, when such items exist.

### 4.5 Adventurer types

Six classes. **Warriors and rangers are the most common.** Each class is defined by what it does
to the player, not by a stat block; stat templates live in data like any other skill template.

| Class | Rarity | Takes | What it means for the player |
|---|---|---|---|
| **Warrior** | Common | den, raiders, escort | The front line. Highest rout threshold of the commons; the body you most often find on the road. |
| **Ranger** | Common | den, raiders, forage, recovery | **Follows tracks.** A ranger on a recovery bounty can trail the player's route from the body. (No route-trail system exists yet; R2 only logs dawn "tracks" after a wolf raid. The trail is new work at L4.) Rangers are how the guild finds a lair without a badge. |
| **Rogue** | Uncommon | recovery, escort | Scouts ahead of a party. The class most likely to find **parked skeletons** (§8.3) and to run rather than fight — a rogue is a report waiting to happen. |
| **Druid** | Uncommon | **forage**, den | Owns the forage board (§5.8). Animals don't attack druids, so a druid can walk into a den the player wanted cleared and *calm* it — den competition of a different kind. |
| **Wizard** | Rare | recovery, escort (hired by caravans after losses) | **A detector on the road.** Sees through the Necromancer's disguise and the mask (§8.4, §8.6). Never travels alone. The rarest corpse. |
| **Cleric** | Rare | recovery, hunting parties | **The other detector on the road.** Sees through the undead's disguise and thralls (§8.5). A **Known**-tier hunting party (§4.1) always carries one. |

- **Party composition scales with the bounty.** Low-level bounties go to a solo warrior or ranger;
  recovery and escort jobs go to pairs or trios; the hunting party that leaves the guild at Known is
  a full four with a cleric in it.
- Wizards and clerics are what make **who is on the road** matter as much as **who is in the
  village**: a village with no tower is still dangerous the day an escort with a wizard walks past.
- Adventurer prisoners are the highest-value captives (badge, ransom, and — for a wizard —
  information, §10.3). Adventurer corpses are the best raise material short of a village wizard.

---

## 5. The faction ecosystem template

Every faction with a home runs this loop. **Only simulate what leaves the walls.**

| Layer | What it is |
|---|---|
| **Home** | A settlement (§2) with a slot cap |
| **Needs** | A short list: food, wood, safety, stone, (gold) |
| **Jobs** | Agents who *walk out* to satisfy a need: farmer → field, woodcutter → forest, hunter → game, miner → deposit, trader → road, patrol → perimeter, raider → someone else's farm, **forager → berries and mushrooms**, **burial party → graveyard** |
| **Outputs** | Resources for them; **victims with a purpose** for you |

Nothing that never leaves the walls is simulated. There are no prices, no internal trade, no
happiness meter. If killing a unit does not change what the settlement does next, the unit should
not exist.

### 5.1 Population is the master resource

Workers, guards, caravan escorts, and settlers all draw from one pool. Killing anyone drains it.
Losing a building does not, but re-staffing it does.

### 5.2 The production formula

```
output = base × staffed_fraction × building_integrity
```

**Ruled (§15, no. 14): the formula is the design statement and the readout, not a second
economy.** Production keeps the existing **worker trip loop** — agents walk out, gather, and walk
back — so the formula is what that loop *adds up to*:
- **Staffing** falls out of who is alive: a dead woodcutter makes no trips. Nothing computes
  `staffed_fraction`; the panel may display it.
- **Buildings get job slots.** A slot is what a worker is assigned to; the slot count caps staffing.
- **Integrity multiplies each trip's yield** as it is banked.
- **The player's Throne has unlimited slots and 100% integrity**, so the player's town plays exactly
  as it does today.

- Kill one of three woodcutters → wood at 2/3 until the village re-staffs from population.
- Kill all three → zero.
- Damage the mill → output scales with integrity. Destroy it → zero until repaired (costs their
  wood) or rebuilt (costs their wood and a slot).
- **The same formula governs the player's buildings.** That is the point of §2.

### 5.3 Re-staffing priority, and Randy the Guard

When population is short, a settlement fills jobs in a fixed order:

> **food > safety > wood > stone > market/other**

This one list is what makes a village read as *reacting*. Kill the guards, and the village pulls a
woodcutter in to hold a spear; the mill goes idle on its own; a bounty appears on the board for
the wood the village now lacks. Nobody scripted it.

**Re-staffing changes the job, not the stats.** Randy the Woodcutter becomes *Randy (Guard)* — same
attributes, same skills. The village has a weak guard until the Guardhouse **trains** a replacement
(training is a job with a duration; the trained guard carries the Guard skill template). The gap
between "Randy took up a spear" and "a trained guard stands the wall" is the village's window of
weakness, and it is visible from the road.

It also gives raiding a goal beyond loot: **bleed a settlement until it cannot field safety, then
walk in.**

### 5.4 Growth

- A prosperous settlement (needs met, gold accumulating, not recently attacked) **grows**: it
  spends gold on new buildings until its **slot cap** is reached.
- A settlement that cannot keep up with attacks — production halted, population falling — does not
  grow, and is visibly more open to attack. Suffering is legible from the road.
- At the slot cap, growth becomes a **settler caravan** (§7) that founds a hamlet on a
  **generator-placed hamlet site** (§5.9).
- Prosperity is shown as a readable tier — **hamlet / village / town** — so the player can read
  caravan likelihood at a glance.

### 5.5 Immigrants

When a settlement's population falls below its building count, an **immigrant caravan** may arrive
along the trade road. Rate is tied to **regional prosperity**: if every settlement in reach is
wrecked, nobody comes. The world can be exhausted; that pressure is intended.

Immigrant caravans are people on a road. They are raidable, capturable, and witnesses.

### 5.6 Named owners

Every staffed building shows **faction + owner name + job**: *Frank (Farmer)*. Names are generated.

- Kill or capture Frank and the building keeps his label, empty: *Frank's Farmhouse*. The village
  reads its own losses, and so does the player walking back through.
- An empty building owned by a faction you have broken can be **clicked: Inhabit / Assign worker**.
- Raise Frank and put him back and the label still says Frank. **That is why raise-in-place is
  more discoverable (§9): the villagers knew Frank.** A stranger skeleton at range is a shape; Frank
  at ten paces is a face.

### 5.7 The dead are buried — villages produce graves

When a human dies and **the guards become aware of the body** (a patrol finds it, a runner reports
it, it fell inside the walls), a **burial party** carries it to the village graveyard.

- The graveyard has a fixed set of graves. A body goes into the first empty one. **When every grave
  holds bones, a new grave is generated.** Graveyards grow with the village's losses.
- This is a **corpse-supply loop**: what the player kills on the road and leaves, the village
  collects and buries, and the player digs up later (`LOOT_SITES_SPEC.md` village graveyard /
  `valuable_grave`). Leaving bodies is not a waste — it is a deposit, at a delay and a notice cost.
- It is also a **race**: collect the corpse before the burial party does, or let them do the
  carrying and rob the grave at night.
- A body found by guards raises threat (Era I: "humans blame animals and outlaws"). A body that
  vanished before anyone found it raises nothing.

### 5.8 Foragers and mushrooms

- **Jobless villagers forage.** A villager with no job slot will, at random, walk out for berries
  and mushrooms and come back. They are the softest targets on the map and the most common
  witnesses.
- **Red mushrooms → health potions.** The market's potion stock comes from forage; a village short
  of it posts a forage bounty (§4.2), taken by low-level adventurers and druids.
- The player's own foragers (skeletons at Forage 2, goblins at 8) work the same nodes; potion
  ingredients are a blueprint-adjacent reason to own a market later.

### 5.9 Hamlet sites

**Ruled: placed at map generation, not at settler departure.** The world generator places **3–5
hamlet sites** per lordship when it generates the map — flat, road-adjacent, near water, empty —
the same way it places the village, the church, and the dens. **Maps are randomly generated for
the most part** (`WORLD_MAP_PLAN.md` §11, R4 shuffle), so the sites differ every run; what is fixed
is only *when* they are decided. Visible as clearings with survey stakes. A settler caravan walks
to the nearest unused one. Predictable to path, and readable: the player can see where a hamlet
*will* go and camp it. The same sites serve the player's own second settlement later.

---

## 6. Per-faction roster

Sorted from `RACES.md`. Categories are about *how they live on the map*, not alignment.

### 6.1 Settled — villages and holds (bounty sources, guild clientele)

| Faction / race | Home | Notes |
|---|---|---|
| **Human** (Lordship) | Villages, farms, the manor, the church | The full loop below. The manor is the largest flip in the game and already the victory condition. |
| **Mountain Dwarf** | Holds | Stone/mining economy; good-aligned, so the guild's best customer |
| **High Elf** | Enclaves | Research economy; wizards likely (§8.4) |
| **Halfling** | Hamlets with gardens | Foraging/food economy; soft target, high mercy cost |
| **Gray Dwarf, Gnome** | Mine / workshop enclaves | Small, specialised, blueprint-rich |

**Human village building list (the reference loop):**

| Building | Need | Job leaves the walls to… | When it falls |
|---|---|---|---|
| Farm | food | work the field | food drops, re-staff first |
| Woodcutter + Woodmill | wood | cut at the treeline | wood stops; mill must be repaired/rebuilt |
| Guardhouse | safety | patrol perimeter, escort caravans, rescue the downed (§11), **carry the dead to the graveyard (§5.7)**, **train replacements (§5.3)** | village pulls workers to fill; open to attack |
| Mine / Quarry | stone | dig at the deposit | growth stalls (stone is the growth material) |
| Market | gold | send traders along the road | sells potions, guides, **blueprints** (§12), **the badge finder (§4.4)**, **the mask (§8.6)** |
| Wizard Tower | knowledge | (stays home) | library + magic training; **a wizard sees through your disguise** (§8.4) |
| Church / chapel + graveyard | — | priest walks the cemetery | **a priest sees through your undead's disguise** (§8.4); graves fill and grow (§5.7) |

### 6.2 Camps — the same loop, smaller (raiding is a job)

| Faction / race | Home | Food | Raiding target | Prisoner use |
|---|---|---|---|---|
| **Goblin** | Camp | hunting/foraging | roads, farms, small villages | **food** |
| **Bandit** (= Human Outcast) | Hold | none produced | roads, caravans, farms | **ransom** (§10.2) |
| **Kobold** | Warren by a mine | foraging | mines, miners | — |
| **Gnoll** | Pack den | hunting | livestock, foragers | food |
| **Orc / Hobgoblin** | Warband camp | hunting + raiding | villages, other camps | labour / ransom |

Bandits are the one faction with **no production loop**: they exist only while there is a target
in reach and **move camp when the target is depleted**. Their economy is prisoners (§10.2). A
cleared bandit hold is also a recruitment source: they are Human Outcasts.

### 6.3 Wandering — monsters and events, no home

**Ogre, Troll, Minotaur, Giant.** Giant is new to the roster and not recruitable. Ogre and Troll
*are* recruitable rares, and the roster already says power attracts power: **a wandering troll met
at low Power is a threat; at high Power it is a recruit offer.** This is recruitment coming from the
world rather than a timer, in line with `ROGUELITE_REWORK.md` §7.

### 6.4 Hidden

**Dark Elf** — secluded enclaves you find, not villages you see. Research/blueprint targets.

---

## 7. Caravans

Three kinds, one behaviour: a group with cargo and escorts walking the trade road.

| Kind | Trigger | Outbound carries | Returns with |
|---|---|---|---|
| **Trade** | a stockpile exceeds surplus threshold | materials | **gold**, shortly after leaving the map |
| **Settler** | slot cap reached with growth gold | people + materials | (founds a hamlet on a generator-placed site, does not return) |
| **Immigrant** | regional prosperity, population shortfall | people | (joins a settlement) |

### 7.1 The choice

Raid the trade caravan outbound and take the **materials**; wait for the return leg and take the
**gold**. Both legs are visible from prosperity tier and from watching the road.

### 7.2 What gold does

The village *spends* it: guards, adventurer hires, repairs, growth. So prosperity is a loop the
player can **farm** (leave the village alive, rob every third caravan) or **break** (kill the
caravan; the village loses materials and gold and shrinks). Raiding is a dial.

### 7.3 Caravans respond

After a loss: more escorts, a different road, or a **posting at the guild for an escort job**.
Which means you can take the escort job, walk the caravan to the edge of the map, and rob it there
with the guards already dead by your hand and no village in sight. If seen, standing collapses. It
is the highest-risk, highest-reward move of the guild phase, and it needs no code of its own.

### 7.4 Caravans camp at night

A caravan that has not reached its destination by nightfall **makes camp**: tents, a fire, and
**one sentry** posted while the rest sleep. Day/night already pressures the player's trips; this
gives the night side of the road something to do.

- The sentry is the **only witness**. Take him while no other unit can see it — the ordinary
  witness rule (§8.1), no stealth stat (ruled) — and the camp is asleep.
- Sleeping units are downed-equivalent for capture purposes (§11.2): bind or slay, no fight, until
  someone wakes.
- A camp is a fixed point for a night — the one time a caravan can be *planned* against rather
  than intercepted.

---

## 8. Detection, disguise, and witnesses

Builds out `LOOT_SITES_SPEC.md` §6 note 4: **a witnessed crime lands only when the witness reaches
a settlement.**

### 8.1 The exclamation point

A unit that sees the Necromancer raising the dead (or sees undead unaccompanied by a plausible
living handler) gets a **!** and becomes a **runner** headed for a specific destination — the
nearest settlement, guardhouse, or the guild. Standing (§4.1) and threat drop **only on arrival**.

Every slip is therefore a chase decision: run him down before the gate, and that is another corpse
and another chance to be seen doing it.

**Ruled (§15, no. 15): what a unit can see is its attention range.** Every NPC has its own
**attention** range: longer by day, shorter at night, and later reduced by disguise (§8.5) and the
mask (§8.6). A sighting is anything that happens inside it. The range is per-unit data, so a guard
can watch further than a forager. It is the one input to the witness check; see §8.7 for the
Necromancer's side.

### 8.2 Who does what on sighting

| Witness | Reaction |
|---|---|
| Villager, worker, forager, trader | flees to nearest settlement (runner) |
| Guard | engages if the odds read well (§11 morale), else runs to the guardhouse |
| Adventurer | **two-step:** engage *or* fall back to the guild and report. **A report is what posts the bounty on you.** Class decides the odds: warriors engage, rogues report, rangers report *and* mark the trail (§4.5). |
| Priest / wizard | see §8.4 |

### 8.3 Parked skeletons

Holding/leashing skeletons out of sight (R2d's leash) lets you keep taking jobs. A parked squad is
**discoverable**: a patrol or hunter that finds it is a sighting too, of the squad rather than of
you. The stash spot is a real choice.

### 8.4 Two counter-classes

- **Wizards** (Wizard Tower, or an adventurer wizard on the road) see through **the Necromancer's** disguise, including the mask (§8.6).
- **Priests / clerics** (Church, or an adventurer cleric on the road) see through **the undead's** disguise (§8.5).

Both detectors exist as buildings *and* as adventurer classes (§4.5), so a village with neither is still not safe on the day a party walks past it.

A village with both a tower and a chapel is the hardest target on the map, and the order you hit
its buildings matters. A dead wizard is the rarest corpse you can raise.

### 8.5 Lifelike undead, vampires, thralls (later unlock)

- **Lifelike undead:** an unlocked ability that makes raised units pass at a distance. Only a
  priest/cleric can tell.
- **Vampires:** **elite undead** (an unlock, alongside ghouls and wraiths). A vampire creates
  **thralls** — living people turned, who keep their job and follow the vampire's orders. A thralled
  farmer farms the same field, and **can walk into town for basic tasks like trading**, because he
  is not dead. Thralls are how you shop at a market after the guild has closed.
- Vampires cost **blood**, which means prisoners (§10). That is the loop that makes capture worth
  the clicks.

### 8.6 The mask

A **market item, market only** (ruled — never a den or ruin find; the first slip should still be a
lesson and the mask should always cost gold). While worn:

- A witness reports **"a masked figure raising the dead."** That moves **threat** — the world knows
  something is out there; patrols thicken; a bounty on *the masked one* is posted — but **not guild
  standing**, because nobody can say it was you.
- **Wizards see through it.**
- The mask is protection bought with gold, not a reset. Standing still never recovers; the mask
  is how you avoid spending it. The world escalates around you regardless.

### 8.7 Hidden and Hunting — the stance, not an attack button

**Ruled (§15, no. 15).** `NECROMANCER_SPEC.md`'s "no attack button, ever" stands. Instead the
Necromancer has a **stance**:

| Stance | His 26px engage fires on… | His escort | Witnesses |
|---|---|---|---|
| **Hidden** (default) | hostiles only — he never starts a fight with the living | its own stance, unchanged | only what he does inside someone's attention range |
| **Hunting** | anything living within 26px is fair game | goes **Aggressive** (`ESCORT_SPEC.md`) | anyone whose attention range covers the kill is a witness |

The stance is a policy on him, the same way the escort's stance is a policy on the spell. Walking
up to a forager in Hunting *is* the attack; walking past one in Hidden is a stroll.

---

## 9. Take or raze — both, with different payoffs

| Approach | Cost | Payoff | Risk |
|---|---|---|---|
| **Raze** | full; you rebuild with your own blueprints and labour | nobody left to recognise anything; no faction memory of the place | slow; you lose the population you could have used |
| **Take** (flip owner, raise the workers in place) | nearly free to run — skeletons don't eat | the whole economy inherited intact | **high discoverability** — the villagers, the priest, the neighbours all knew Frank |
| **Take, thralled** (later) | a vampire and blood | inherited economy *and* market access | only a priest can tell |

### 9.1 Blueprints on flip

**Automatic.** You own the building; you can see how it is built. No research timer for building
types — a waiting mechanic in a game that already has enough clocks.

Acquisition routes, different costs, all instant:

- **Flip:** free, but loud. You conquered something, and that spreads.
- **Market:** gold, and quiet. Requires Unknown/Suspected standing, or a thrall.
- **Found:** some blueprints are loot in the world — the **Dark Altar is inside the first wolf
  den** (§3). Others can sit in dens, ruins, and on prisoners (§10.3).

**Research** (Laboratory) is for a different question: the **undead adaptation** of a blueprint —
the farm a skeleton can run without eating, the mill that doesn't look wrong from the road.
Research improves what you own; it never gates the basics.

**Ruled: flipping the manor grants the manor's own blueprint only.** The rest of what the lordship
knows is earned building by building.

---

## 10. Prisoners

Every faction with a home has one prisoner use. Same template.

### 10.1 Uses

| Faction | Prisoner use |
|---|---|
| Goblin, Gnoll | food |
| Bandit | **ransom** |
| Orc / Hobgoblin | labour or ransom |
| Human lordship | trial / hanging (a public event; a witness generator) |
| **Necromancer** | see below |

Any faction holding a captured **adventurer** is holding a badge (§4.4): the guild's recovery
bounty resolves as a rescue at that camp.

### 10.2 Ransom is the bandit economy

A village pays gold to get Frank back; the gold flows to the hold; the hold grows or moves.
Prisoners *are* what bandits produce, which puts bandits on the same template as everyone else with
a captive in place of a field.

### 10.3 The Necromancer's uses

Prisoners must be a **different resource from corpses**, or capture-or-slay is a fake choice.

1. **Sacrifice** at the Dark Altar for **stronger undead** (later unlock; extends the Altar's
   existing body-conversion role from `GAME_OUTLINE.md`).
2. **Trade to bandits** for gold (bandits as fence — the only buyer once the guild is shut).
3. **Search** — see what they carry: resources, and sometimes **blueprints**.
4. **Hire as mercenaries** — *the introduction to recruiting.* Hired, not recruited: they are paid,
   they leave when unpaid, and they do **not** come through the reputation-gated offer system of
   `ROGUELITE_REWORK.md` §7. Power still attracts power; this is coin attracting the desperate.
5. **Blood** for vampires (§8.5), once unlocked.
6. Living labour for buildings where undead would be spotted (a lesser version of 4).

### 10.4 Holding prisoners

**Ruled: prisoners need a building and they eat.** The **cell** (holding pen, dungeon — name open)
is a blueprint like any other, owned by every faction that takes prisoners (§10.1), and so is
flippable. Prisoners draw food from the holder's larder; an undead settlement with prisoners
therefore has a food need it would not otherwise have, which is the correct cost for the uses
above. A cell with no food is a cell with corpses in it.

---

## 11. Morale, surrender, downed, capture

Extends `COMBAT_SPEC.md` §5. Morale-driven routing stays as specced; this adds what happens at the
bottom of the health bar and gives routing a destination.

### 11.1 Thresholds by role

Surrender/rout thresholds are set **by role first, individual second**: farmers break early, guards
late, adventurers last. Goblins break **as a pack** (COMBAT_SPEC §7 pack morale reused). A routing
unit **is a witness runner** (§8.1): morale feeds standing and threat for free. Randy the Guard
routs like a woodcutter (§5.3) — the label changed, the man didn't.

### 11.2 Downed

At 0 hp a humanoid is **downed** ("unconscious"), lying where it fell, with a **bleed-out window**.
Wildlife does not down — a wolf kills, which preserves COMBAT_SPEC's "living recruits are never
killed by wildlife" through the rout check rather than this rule.

During the window:

- **Capture** (bind → prisoner) or **slay** (→ corpse, raisable).
- **Rescue — all factions.** Guards drag Frank back behind the wall; skeletons drag a downed orc
  home; goblins carry off their own. The window is a fight over bodies, which is exactly the fight a
  necromancer game wants.
- Expiry → dead. A corpse — and if guards learn of it, a grave (§5.7).

Sleeping units (caravan camps, §7.4) are treated as downed for capture until woken.

### 11.3 Batch commands

**Finish all / Bind all** as a single order over the field, or every fight ends in ten clicks.

### 11.4 The asymmetry

Undead have **no morale** (already specced; `alignment: "Undead"` skips the rout check). Living
recruits do. Humans break, skeletons don't. This spec adds nothing to that rule and relies on it.

---

## 12. Meta-progression

**Ruled: options only.** Complies with `ROGUELITE_REWORK.md` §2/§9 as written — unlocks widen the
option pool and never raise numbers. No amendment needed.

Two lanes, kept separate:

| Lane | Persists | Comes from |
|---|---|---|
| **Blueprints** (buildings only, for now) | across runs | the **world** — flipped, bought, or found (§9.1) |
| **Character XP tree** | across runs | banked XP (`ROGUELITE_REWORK.md` §9) — spells, undead unit types (vampires, lifelike undead), abilities (the Raven carrying items, §4.4) |

**Built 2026-09-26 (the XP half):** XP is banked the instant it is earned, levels follow the
formula in `docs/design/PROGRESSION.md`, and the first unlock is **Second Wake** (level 5: once per
run, he wakes at the Throne instead of the run ending). It is an ability, not a number, so it
complies with the options-only ruling.

- A blueprint once acquired is known forever; you still **build** it each run. "I got the Wizard
  Tower blueprint before I died" is a run that was worth playing. The **Dark Altar is the first
  blueprint every player earns** (§3), which makes the first den the first lesson in the rule.
- The guild phase is expected to **shrink** across runs as blueprints accumulate, not be removed.

---

## 13. Impact on existing documents

| Document | Effect |
|---|---|
| `ROGUELITE_REWORK.md` §2 | **Amended 2026-09-26 (§17 there):** "Resets every run: the settlement (Throne + starting skeletons only)" becomes **Throne only** — first dead come from the graves (§3). **Ruled: every run.** Built. |
| `ROGUELITE_REWORK.md` §3 | Era I gains a concrete activity (guild bounties in disguise); "Known" guild standing is **one** Era II trigger (ruled). |
| `ROGUELITE_REWORK.md` §7 | Guild **standing** added as a per-faction disposition alongside the five axes. Hired mercenaries (§10.3) are a paid channel, not a recruit offer. Wandering rares as recruit offers at high Power (§6.3). |
| `ROGUELITE_REWORK.md` §13–14 | **"Living village routines" leaves the R6 deferral.** The symmetry rule (§2) makes it a generalisation of the existing settlement, not a new system. Build order in §14 below. |
| `ROGUELITE_REWORK.md` §2/§9 | **Unchanged** — ruled options only. |
| `COMBAT_SPEC.md` C3 | Carrier for §11 (role thresholds, downed, bleed-out, rescue, batch orders, sleeping = downed). |
| `LOOT_SITES_SPEC.md` §6 | Witness runners (§8.1) are that note's R3 build, with destinations and the two-step adventurer. Village graveyard gains the growth rule (§5.7). |
| `RAVEN_SPEC.md` | Later XP-tree unlock: the Raven carries small items (first use: badges, §4.4) to a chosen point. Directed Raven scouting is still deferred; this is a narrower ability. |
| `GAME_OUTLINE.md` Dark Altar | Gains prisoner sacrifice (§10.3.1) as a later unlock; **no longer a starting building** (§3). Grudge tiers (Quiet → Noticed → Wrath) map naturally onto guild standing tiers; reconcile when the faction/grudge system is prompted. |
| `NECROMANCER_SPEC.md` | "No attack button, ever" stands; he gains the **Hidden / Hunting stance** (§8.7). |
| `ESCORT_SPEC.md` | Hunting puts the escort in **Aggressive** (§8.7). |
| `CLAUDE.md` | At L0, "`GameState` is the single source of truth" becomes "`GameState` is a façade over the player's settlement" (ruling 13, §2). |
| `RACES.md` | Housing styles already encode camp vs settled behaviour; §6 adds the map-level sort and a Giant (non-recruitable). Guard is a **skill template**, not a race (§5.3). |
| `WORLD_MAP_PLAN.md` | The guild sits on the trade road at the lordship / wilderness boundary; roadside graves between guild and den; camps in contested wilderness; **3–5 hamlet sites placed by the generator** in lordship territory (§5.9). **Random generation is the default** — §11's "rotate or relocate within a valid template" is the floor, not the ceiling. |
| `data/buildings.json` | Needs `faction` blueprint lists, `job` (what leaves the walls, to where), `need`, integrity, and `trains` (Guardhouse). New buildings: Guild, Cell, Graveyard-as-growable. |
| `data/world_sites.json` | Den loot table gains the Altar blueprint on the first-run den. |
| `data/adventurers.json` (new) or `followers.json` | Six class templates (§4.5): rarity weights, bounty preferences, rout threshold, detector flags (wizard: sees villain; cleric: sees undead), ranger `tracks`. |

---

## 14. Staged build plan

Each stage is playable and proves one thing. **L1–L3 fix the demo's "no reason to leave"; L4+ is
the game.** L1 needs the R4-lite run boundary (death ends run → summary → restart) to bank
anything; **that boundary was built 2026-09-26**, so the dependency is met.

| Stage | Builds | Exit |
|---|---|---|
| **L0 — Symmetry** | `Settlement` takes an `owner`; **its own stockpile, with `GameState` as a façade** (ruling 13); **job slots and integrity on the worker trip loop**, the §5.2 formula as a readout (ruling 14; the Throne: unlimited slots, 100% integrity); population pool; named owners (§5.6); click-to-assign on empty buildings. ~~No starting skeletons / no starting Altar~~ (§3) — **built 2026-09-26.** | The player's town runs unchanged on the generalised model. A second settlement owned by "human" exists and ticks. |
| **L1 — One village, three jobs** | Farm, Woodcutter+Mill, Guardhouse; re-staff priority with **Randy rule** and Guardhouse training (§5.3); workers walk out and back; **jobless foragers** (§5.8) | Kill a woodcutter, watch the village react. Nothing scripted. |
| **L2 — The Guild** | Guild building + faction; standing tiers; generated board with the den bounty; road spawn + first-run popup; **roadside graves**; **Altar blueprint in the den**; **attention ranges** (day/night) and witness runners with destinations (§8.1); the **Hidden / Hunting stance** (§8.7) | First run: walk the road, raise your first dead, clear the den, come home with the Altar. Get seen once, watch standing drop *when the runner arrives*. |
| **L3 — Downed and prisoners** | §11 downed/bleed-out/rescue/batch; capture → prisoner; **the Cell** (§10.4) with food upkeep; Necromancer uses 2–3 (trade, search); **burial parties and growing graveyards** (§5.7) | Capture-or-slay is a real choice because prisoners do something corpses don't. Bodies you leave come back as graves. |
| **L4 — Goblin camp and adventurers** | Camp on the template; raiding job; prisoners-as-food; bounties generated from raids; adventurers taking bounties; **the six classes with rarity and party composition** (§4.5); **due dates, MIA, badges, the finder** (§4.4); forage bounties | A bounty appears because goblins hit a farm. An adventurer walks out to it and doesn't come back. A recovery bounty follows. |
| **L5 — Caravans** | Trade caravan two-leg loop; gold spend; response to loss; escort posting; **night camps with a sentry** (§7.4) | Materials-or-gold is a visible choice; the escort-and-rob play and the sentry kill both work with no special code. |
| **L6 — Bandits, growth, immigrants** | Bandit hold with ransom economy and camp-move; slot cap + settler caravans to **generator-placed hamlet sites**; immigrant caravans on regional prosperity | The map's shape changes over a long run; the world can be exhausted. |
| **L7 — Market, Tower, Church, blueprints** | Market (potions from red mushrooms, guides, blueprints, badge finder, **mask** §8.6); Wizard Tower + Church as detectors (§8.4); blueprint-on-flip; persistent blueprint ledger | A dead run still banked a blueprint. Hitting order of a village's buildings matters. |
| **L8 — Take, thralls, sacrifice** | Flip owner + raise-in-place with discoverability; lifelike undead; vampires + thralls; Altar sacrifice; hired mercenaries | Both take and raze are played, for different reasons, in the same run. |

---

## 15. Rulings

**Issued 2026-09-26:**

1. **Meta-progression:** options only. `ROGUELITE_REWORK.md` §2/§9 stand.
2. **Spawn:** roadside at the lair's edge, lair a marked site.
3. **Era II trigger:** Known standing is one trigger, not the only one.
4. **Standing recovery:** never within a run (cheapest to build; the mask §8.6 is the protection).
5. **Known but open:** hard door for the guild; bandits are the fence.
6. **Prisoners:** a building (the Cell), a blueprint like any other; prisoners eat.
7. **Manor blueprint:** manor only; the rest is earned.
8. **Hamlet sites:** 3–5 per lordship, placed by the world generator at map creation (so they
   shuffle with the map), not chosen at settler departure. **Maps are randomly generated for the
   most part** — every playthrough should feel different.
9. **Starting skeletons:** none on any run. First dead always come from the roadside graves.
   *(Built 2026-09-26, with Raise Dead as the starting spell and 3 starting bones.)*
10. **Mask acquisition:** market only.
11. **Badge finder range:** whole map. There is no safe distance to carry a badge home.
12. **Silent sentry kill:** no stealth stat. "Unseen by any other unit" — the same rule as every
    other witness check.

**Issued later on 2026-09-26 (the L0 model):**

13. **Stockpiles:** each settlement has its **own** stockpile — resources, followers/population,
    Power. `GameState` becomes a façade over the player's settlement (§2).
14. **Production:** keep the worker trip loop. Staffing falls out of who is alive; building
    integrity multiplies each trip's yield; buildings get job slots (the player's Throne: unlimited
    slots, 100% integrity). The §5.2 formula is the design statement and readout, not a second
    economy.
15. **Attention and the stance:** NPCs get their own attention range (longer by day, shorter at
    night; later cut by disguise and the mask) that feeds the witness system (§8.1). The
    Necromancer gets a **Hidden / Hunting stance** instead of an attack button (§8.7).

**No open rulings.** Next step: L0/L1 prompts.

**Still open (playtest-era, not blocking):** druids calming dens (§4.5) — keep or cut once the
den fight has been felt.

---

## 16. Tunables

Surplus threshold per material; caravan off-map duration; escort count vs cargo value and recent
losses; night-camp trigger (distance remaining at dusk); re-staff delay; Guardhouse training
duration; bleed-out window; rescue range; standing drop per arrived runner and per adventurer
report; growth gold per building; slot caps per tier (hamlet / village / town); immigrant rate vs
regional prosperity; regional-prosperity floor below which nobody comes; bounty due dates by type;
badge finder cost; mask cost; graves per graveyard before growth; jobless-forager trip chance;
blood per thrall per day; prisoner food per day; role morale thresholds (farmer / guard /
adventurer / goblin pack).
