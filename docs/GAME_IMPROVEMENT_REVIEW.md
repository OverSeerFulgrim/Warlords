# Warlords — Game Improvement Review

**Status:** Review draft, non-authoritative  
**Date:** 2026-08-05  
**Purpose:** Identify what the current prototype is missing, recommend the next development priorities, and provide a focused checklist for design review.

This document does not replace `ROGUELITE_REWORK.md`, the R2 specifications, or the established implementation roadmap. It is a product-level assessment intended to help decide whether that roadmap is proving the right player experience.

---

## 1. Executive assessment

Warlords has a strong technical and systemic foundation. The settlement economy, worker behavior, recruitment foundation, combat primitive, controllable Necromancer, world map, fog of war, and travel model provide enough machinery to support the intended game.

The main problem is not a lack of systems. It is that the existing systems do not yet form a complete, consequential player loop.

The game currently has:

- a settlement worth maintaining;
- a large world worth looking at;
- a controllable villain who can travel through it;
- resources, followers, threats, and combat systems capable of creating consequences.

It does not yet have a sufficiently strong reason to leave the settlement, a tense decision about when to return, or a real penalty for failing to return. Until those pieces connect, the project will continue to feel like a settlement prototype attached to an exploratory map rather than a villain-focused roguelite.

The most important design test is:

> Does the player regularly ask, “Do I risk one more grave, or turn back with what I have?”

The next milestone should be judged primarily by whether it creates that question.

---

## 2. Highest-priority missing feature: the complete sortie loop

The core loop should be:

> Prepare at the lair → leave with an escort → discover a site → make a risky choice → carry the result → decide whether to continue → return to the Throne → bank the haul.

The smallest useful implementation needs only one or two grave types. It should include:

- loot that cannot be produced safely at home;
- limited party carrying capacity;
- time spent excavating, looting, or performing a ritual;
- loot remaining at the site when the party cannot carry it all;
- automatic deposit near the Throne;
- a clear audiovisual deposit payoff;
- loss of all unbanked loot when the Necromancer dies;
- enough distance, danger, and time pressure to make continuing a real gamble.

### Recommendation

Build a thin end-to-end slice before implementing the entire R2 site catalog. Begin with:

1. one safe introductory grave;
2. one valuable grave with a meaningful choice;
3. carrying and overflow;
4. return and deposit;
5. death and loss.

Expand the encounter catalog only after this small loop is enjoyable. Ten site types cannot compensate for an unsatisfying return loop, while a compelling two-site loop proves that additional content is worth producing.

### Review questions

- Is field loot valuable enough to justify leaving home?
- Does limited capacity create decisions rather than inconvenience?
- Is the return journey meaningfully different when carrying valuables?
- Can the player understand exactly what will be lost before taking another risk?
- Does depositing the haul feel like a reward rather than a bookkeeping event?

---

## 3. The Necromancer needs distinctive field actions

Direct movement makes the Necromancer physically present in the world, but movement by itself does not fully deliver the villain fantasy. He needs a small toolkit of actions that only he can perform.

Strong initial candidates are:

- raise a corpse as a temporary or permanent skeleton;
- extract Dark Essence from a supernatural site;
- steal from, desecrate, restore, or conceal a grave;
- bind nearby undead into an escort;
- sacrifice loot or a minion to escape danger;
- perceive supernatural clues hidden from ordinary units.

### Recommendation

Choose approximately three field actions for the first playable loop. Each should create a tradeoff, change the world, or expose the player to risk. Avoid building a large spell tree until these basic actions are satisfying.

### Review questions

- Does controlling the Necromancer feel different from controlling an ordinary adventurer?
- Do his actions express necromancy through consequences, not only visuals?
- Does every action have a cost, risk, or opportunity cost?
- Can the player tell why the Necromancer personally had to be present?

---

## 4. Travel needs decisions, not only elapsed time

The world-map scale and major travel bands are largely working, but travel risks becoming empty walking if decisions occur only at destinations.

Useful travel decisions include:

- safe wilderness versus a faster exposed road;
- returning before dusk versus investigating another site;
- crossing behind a patrol versus taking a long detour;
- bringing more skeletons versus preserving settlement labor;
- carrying mundane resources versus dropping them for a relic;
- helping, robbing, killing, avoiding, or misleading a traveler.

### Recommendation

Add a small number of legible route pressures rather than frequent random interruptions. The journey should shape the expedition without becoming attrition or busywork.

### Review questions

- Can the player explain why they chose a particular route?
- Does dusk change a route decision before it becomes a punishment?
- Are dangerous areas telegraphed clearly enough to make failure feel chosen?
- Does the map contain meaningful stops at the intended 10–20 second sortie scale?

---

## 5. The world must visibly respond to the player

The planned five-axis reputation system is one of the project's strongest differentiators. Its value will come from visible consequences, not from displaying five additional numbers.

Examples of visible responses:

- repeated grave robbery produces guarded cemeteries and church investigations;
- mercy attracts refugees, outcasts, and grateful survivors;
- public victories attract warriors and increase military patrols;
- accumulated wealth attracts merchants, opportunists, and thieves;
- forbidden knowledge attracts scholars and cultists while alarming the church;
- destroyed evidence reduces immediate notice but strengthens a cruelty reputation if discovered later.

### Recommendation

For every reputation change, identify at least one world behavior, recruitment consequence, or content-pool change that it can eventually produce. Prefer visible reactions over passive modifiers.

### Review questions

- Can the player see that the world is reacting to their specific deeds?
- Do different reputations support genuinely different run stories?
- Are cruelty and mercy both useful identities rather than a good/evil choice?
- Does increased notoriety create opportunity as well as danger?

---

## 6. Failure and extraction need to become real

The Necromancer can currently die, but the run continues after announcing that it would have ended. This is appropriate during early construction, but it prevents the exploration loop from carrying its intended emotional weight.

The minimum useful run boundary is:

- death ends the current run;
- fleeing ends the run alive and preserves the appropriate extracted rewards;
- taking the manor produces victory;
- a concise summary records discoveries, deeds, followers lost, loot banked, and cause of death;
- the player can immediately begin another run.

### Recommendation

Introduce a lightweight test-run ending before balancing a large encounter catalog. Full meta-progression can remain deferred, but playtests need real failure in order to measure risk.

### Review questions

- Did the player understand why the run ended?
- Could the loss have been avoided through an earlier decision?
- Was fleeing a legitimate choice rather than a disguised failure button?
- Does the summary make the failed run feel like a story worth remembering?

---

## 7. The settlement should power and complicate sorties

The settlement and exploration layers should not feel like separate games. The settlement should prepare expeditions, continue operating while the player is away, and create consequences that follow the player into the field.

Good connections include:

- escorting skeletons stop gathering while bound to the Necromancer;
- buildings unlock field actions, preparation options, or recovery services;
- food shortages and low morale create reasons to return;
- injured followers require treatment at home;
- deposited relics enable particular strategies;
- the player sets economic priorities before leaving and returns to the result;
- a poorly prepared settlement can suffer while its strongest defenders are away.

### Recommendation

Require every major settlement feature to answer one of two questions:

1. How does this prepare the next sortie?
2. How can leaving on a sortie make this harder to manage?

Features that answer neither question should be deferred or reconsidered.

---

## 8. Followers need memorable identities

The project already supports races, stats, labor skills, morale, housing, traits, injuries, and desertion. The missing layer is a stronger sense that individual followers accumulate history.

Useful additions include:

- one clearly communicated strength and complication per follower;
- remembered rescues, injuries, betrayals, victories, and near-deaths;
- reactions to the Necromancer's reputation and choices;
- a small number of important relationships rather than a dense invisible simulation;
- named chronicle moments when a follower changes the outcome of a run.

### Recommendation

Prioritize story-generating consequences over additional attributes. A follower who saved the Necromancer and later deserted during a famine is more memorable than a follower with six minor statistical bonuses.

---

## 9. Feedback, usability, and presentation

The current build is readable and functional, but many actions do not yet have enough sensory or informational impact.

Missing or underdeveloped feedback includes:

- construction, combat, discovery, ritual, deposit, dusk, and warning sounds;
- hit reactions, death effects, ritual effects, and harvesting effects;
- visible carried-loot indicators;
- site interaction progress and cancellation feedback;
- distinct danger silhouettes and site markers;
- a stronger transition into dusk and night;
- contextual onboarding for movement, camera follow, building, priorities, and the first sortie;
- clearer explanation of why an action is unavailable;
- a more compact contextual command bar that reveals detail when needed.

### Recommendation

Polish the feedback around the thin sortie slice before applying the same treatment everywhere. The first grave, first full inventory, first dangerous return, first deposit, and first death should all feel unmistakable.

---

## 10. Technical support the design still needs

### Persistent regression tests

Only the sprite-scale and travel-time verification scenes are currently committed. Previous development history describes larger integration harnesses, but those checks cannot presently be rerun.

Recommended persistent checks:

- clean headless boot;
- one complete worker gather-and-deposit trip;
- foundation economy and Barracks progression;
- site interaction and charge behavior;
- carry-capacity and exact-overflow arithmetic;
- deposit occurring only at the Throne;
- death clearing all unbanked loot before other handlers read it;
- Raven honesty and no-fog-reveal invariant;
- all data-file resource paths resolving;
- world sites and patrol routes standing on walkable terrain.

Add a small automated CI workflow once these checks are stable.

### Reproducible run seeds

The eventual game depends on shuffled locations, encounter selections, recruits, loot, and combat rolls. An explicit run seed should be introduced before procedural run generation.

The seed should:

- be owned by the run rather than scattered global randomness;
- appear in logs and run summaries;
- be accepted as an optional new-run input;
- reproduce world generation and content selection;
- allow combat and cosmetic randomness to use separate streams if necessary.

### Transitional-system containment

Several legacy systems remain active or constructed while their replacements are scheduled for later stages. Timed recruitment, legacy reputation, the old victory condition, abstract missions, and the old bounty implementation should be clearly feature-gated so they do not contaminate R2 playtests.

### Input and project structure

- Move hard-coded movement and camera keys into Godot's Input Map before adding remapping or controller support.
- Continue extracting responsibilities from `Main.gd` when those areas are touched.
- Do not pause feature work for a wholesale architecture rewrite.
- Keep future verification harnesses committed rather than treating them as disposable smoke tests.

---

## 11. Repository and documentation hygiene

Before beginning a large implementation pass:

- commit or deliberately discard the pending R2 specifications, prompts, and art assets;
- add a `.gitattributes` policy so line-ending changes do not obscure real modifications;
- update `README.md` to describe the current Godot version and current rework phase;
- update or replace `CURRENT_STATE.md`, which still describes several completed R2 specifications as missing;
- clearly label superseded design documents;
- ensure every roadmap document distinguishes implemented, verified, drafted, and deferred work.

This work is not player-facing, but it reduces the chance of implementing an obsolete design or losing untracked decisions.

---

## 12. Recommended development order

### Immediate gate

1. Complete the R1 travel-feel playtest.
2. Complete the six foundation criteria in one uninterrupted session.
3. Finish the travel-harness P0 correction.
4. Clean and commit the current documentation and worktree state.

### Core proof

5. Implement one safe grave and one meaningful grave choice.
6. Implement carrying, exact overflow, return, and Throne deposit.
7. Make Necromancer death destroy the haul and end the test run.
8. Playtest until “one more grave or turn back?” is a real decision.

### R2 expansion

9. Expand the site and loot catalog.
10. Add escort behavior and the settlement-labor tradeoff.
11. Add the Raven's honest passive pings.
12. Improve feedback and onboarding around the completed loop.

### Subsequent stages

13. Implement reputation and visible world reactions.
14. Implement the full run lifecycle and map shuffle.
15. Add explicit run seeds and reproducible run summaries.
16. Build meta-progression only after repeated runs are enjoyable without it.

---

## 13. Features to defer

The following features should not take priority over proving the core sortie loop:

- additional villain classes;
- multiplayer;
- a large crafting system;
- dozens of buildings or relics;
- a living-village daily simulation;
- complex follower relationship graphs;
- extensive visual redesign;
- the complete meta-progression hub;
- large volumes of encounter writing before the interaction grammar is proven.

The project already has substantial breadth. The current need is depth, consequence, and cohesion.

---

## 14. R2 review criteria

R2 should be considered successful only when a playtester can answer “yes” to most of the following:

- I had a clear reason to leave the lair.
- I made at least one meaningful preparation choice before leaving.
- I encountered something I could not obtain safely at home.
- I understood the danger before committing to it.
- Carry capacity forced a real choice.
- I considered returning home before my capacity was full.
- Dusk, injury, enemies, or settlement conditions affected my decision.
- I understood what would be lost if the Necromancer died.
- Returning and depositing the haul felt rewarding.
- The settlement was meaningfully different when I returned.
- I wanted to leave again for a reason other than completing a test checklist.

If these conditions are not met, the next step should be tuning the loop—not adding another major system.

---

## 15. Decision summary

The recommended direction is:

> Stop expanding breadth temporarily. Build one narrow, polished, consequential sortie from grave to deposit to possible death. Use that slice to prove the game's central emotional question, then expand content around what the playtest demonstrates.

Warlords already has enough structure to become a compelling villain roguelite. The next improvement is making its settlement, world, Necromancer, followers, clock, danger, and rewards all matter during the same player decision.
