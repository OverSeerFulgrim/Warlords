# Trait Roster — recruit personalities

Companion to `RACES.md`. Traits are the *individual* personality layer on top of race: race sets your baselines, traits set who you are. They affect daily settlement life now, and combat, bounty, mission and relationship behavior as those systems land. This table should become `data/traits.json`.

> **Stat model.** This file was rewritten against the reworked stat system (attributes / condition / skills — see "Stat targets" below). The previous version targeted the retired Might/Guile/Influence/Loyalty four-stat model; two traits changed what they modify as a result, and four had their combat effects redefined. `TRAITS_IMPLEMENTATION_PLAN.md` owns the build order and marks which effects are buildable today versus blocked on the stat rework.

## Rules

- Every generated recruit rolls **1 trait, plus a 30% chance of a second**. Skeleton Workers roll none (interchangeable by design).
- **Conflict pairs never co-occur** (listed below). Reroll the second trait on conflict.
- Traits are **hidden at the gate and revealed in the Barracks.** A recruit offer shows race, class, best skills, and a line of dialogue that *hints* at their traits without naming them — Grukk's "feed me lots and lots and I'll smack thems that need smackin', but otherwise… don't wake me up!" is a Glutton and a Lazy talking, and the player has to hear it. Full trait names appear once they're living in the Barracks. This is what makes the Barracks a trial period rather than a slot counter, and it's why evicting someone costs more disposition than turning them away at the gate.
- Effects are **hooks, data-driven**: each trait lists effect keys the code reads. Systems that don't exist yet have their hooks defined now so traits don't need reauthoring when those land.

## Stat targets

Traits may modify **attributes** and **skills**. They may not modify condition — morale, hp, hunger and disease are simulated state, and a trait that "sets" them would fight the systems that own them. Traits influence condition indirectly, through the morale and combat rules below.

| Layer | Values | Traits may grant |
|---|---|---|
| **Attributes** | Strength, Dexterity, Speed, Endurance, Intelligence, Guile, Perception, Tact, Loyalty | yes, ±1 |
| **Skills** | Woodcutting, Mining, Foraging, Hunting, Fishing, Crafting, Trapper, Scouting, Mercantile, Research, Surgeon, Leadership | yes, ±1 |
| **Condition** | hp, morale, hunger, disease | no — modify the *rules*, not the value |

Note that an attribute bonus is **lumpier than a skill bonus**. Skills derive as `skill + floor((governing_attribute − 5) / 2)`, so +1 to an attribute is worth +1 to its skills only when it crosses an odd boundary — Perception 6→7 helps, 5→6 does nothing. That's acceptable (it makes the bonus matter more on races already strong in that attribute, which reads as "plays to their strength"), but it's a real asymmetry when balancing Keen-eyed and Sticky-fingered against Charming.

## The traits

| Trait | Daily life (live now) | Combat (needs the stat rework) | Later-system hooks |
|---|---|---|---|
| **Loyal** | +1 Loyalty; gives a second warning before deserting | — | never ambushes after departure |
| **Fanatic** | Never deserts; missed meals cost morale to a floor of 2, never below | **Never routs**, whatever happens to the people beside them | +1 on villainy bounties for the cause; unsettles Good-aligned housemates (relationship −1) |
| **Greedy** | Theft chance at low morale doubled; +1 morale on any day the settlement gains coin or essence | — | picks the highest-*reward* bounty regardless of risk; demands +20% bounty pay |
| **Cowardly** | — | **Won't engage without an ally within 3 cells**; routs 2 morale earlier than default | refuses bounties with difficulty ≥ 6; +1 stealth (caution pays) |
| **Brave** | — | Routs 2 morale later than default; auto-joins nearby fights from 5 cells (default 3) | accepts any difficulty; −1 stealth (bold, not subtle) |
| **Bloodthirsty** | — | +1 damage; **+1 morale on a kill**; friction events they're in always escalate | prefers violent bounties; +1 grudge on stealth failure (leaves a mess) |
| **Industrious** | +20% gather/work speed; −1 morale on a full idle day | — | trains 2× speed |
| **Lazy** | −20% gather/work speed; +1 baseline morale (easily content) | — | trains at half speed; won't accept gathering bounties |
| **Glutton** | 1.5× food per meal; +1 morale when fully fed; 2× morale loss when shorted | — | — |
| **Ascetic** | 0.5× food per meal; first missed meal each cycle costs no morale | — | — |
| **Charming** | **+1 Leadership** | Steadies nearby units through the Leadership rule — a Charming recruit keeps the troll pointed at the enemy | +1 starting relationship with everyone; better trade mission prices |
| **Grumpy** | Morale events from neighbors don't affect them | — | −1 starting relationship with everyone; immune to friction morale loss |
| **Pack-minded** | +1 morale while housed adjacent to another house; −1 if Spaced-style isolated | Routs 1 morale earlier when no ally is within 3 cells | +1 on bounties taken alongside another follower |
| **Loner** | +1 morale in a Spaced/Edge house; −1 in Clustered housing | **Loses no morale when allies fall** — they weren't attached | works/fights better alone: +1 when no ally within 3 cells |
| **Sticky-fingered** | +1 Guile; rare petty theft even at good morale (1 resource, flavor log) | — | +1 stealth on theft-type bounties |
| **Keen-eyed** | **+1 Perception** | Feeds combat judgement via `Tact + floor((Perception − 5) / 2)`; spots ambushes | halves departure-ambush penalty |

**Conflicts:** Industrious↔Lazy, Glutton↔Ascetic, Charming↔Grumpy, Cowardly↔Brave, Pack-minded↔Loner, Fanatic↔Cowardly. Loyal conflicts with nothing — anyone can be loyal.

## What changed from the four-stat version, and why

Four entries were retargeted or redefined. Recorded here so the reasoning survives:

- **Charming: +1 Influence → +1 Leadership.** Influence is retired. Leadership is the skill that carries what Influence was gesturing at, it's trainable where Influence wasn't, and it plugs Charming straight into the guidance rule — a Charming recruit standing near a low-Tact ogre is the difference between a battle line and a wandering ogre.
- **Keen-eyed: +1 Foraging → +1 Perception.** Foraging is now governed by Perception, so granting the attribute gets the foraging bonus *and* Scouting *and* a contribution to combat judgement. "Spots ambushes" stops being a bespoke hook and becomes what the attribute already does.
- **Cowardly and Brave: hp thresholds → morale and backup.** Routing is morale-driven now, not a flat hp percentage, so "flees at 50% hp" no longer describes anything the code does. Cowardly refusing to engage without backup is the sharper version of the same idea and it makes a Cowardly recruit genuinely awkward to place rather than just statistically worse.
- **Bloodthirsty gained `+1 morale on a kill`**, because combat morale now exists to be gained. It makes them a rout-resistant anchor as long as they're winning, and a liability the moment they aren't.

**Loner's combat line is new and worth keeping.** Immunity to ally-death morale loss makes the trait mechanically real in a fight rather than purely a housing modifier, and it's the correct reading of the personality.

**No new traits were added.** There's a visible gap — nothing rolls a Tact bonus, so the "battle-smart veteran" archetype has no trait representing it. That's a deliberate hold: adding traits is cheap and adding the *right* traits needs the combat system running first. Revisit after the rework lands.

## Relationship to other systems

- **Race passives** (troll regeneration, kobold traps, halfling cooking) are a separate, deferred concept — racial biology, not personality. Don't merge them into traits.
- **Classes** (shaman, wizard, and the other per-race magic users) are a third layer again — role, not personality and not biology. A trait never grants a class.
- The **old template traits** (followers.json era) map onto this set where names collide (Loyal, Greedy, Bloodthirsty, Cowardly, Fanatic keep their `evaluate_bounty` meanings); the rest of the old pool retires.
- **Race-weighted trait odds** (goblins lean Sticky-fingered, dwarves lean Industrious) are a nice later touch — the JSON should allow an optional per-race weight field, but v1 rolls from a flat pool.
