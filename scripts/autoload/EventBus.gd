extends Node
## EventBus (Autoload singleton)
## Decoupled signal hub. Systems that don't need to know about each other
## directly (SettlementGrid, BountyBoard, ThreatSystem, EventSystem,
## MissionSystem, UI) all talk through here instead of holding references
## to one another. Keeps the prototype easy to rewire while balancing.

# Settlement
signal building_placed(building, cell: Vector2i)
signal building_removed(building, cell: Vector2i)
signal building_count_changed(count: int)
signal build_failed(reason: String)  # not enough resources / cell occupied
signal main_building_damaged(building)  # hp changed outside the normal placement flow (Crusade)

# Bounty board
signal bounty_posted(bounty)
signal bounty_accepted(bounty, follower)
signal bounty_completed(bounty, follower, success: bool)

# Followers
signal follower_recruited(follower)
signal follower_count_changed(count: int)
## A generated recruit did NOT join -- player declined, or the Barracks was
## full. Carries the Follower that was rolled so departure-memory
## (GAME_OUTLINE gap #6) can eventually remember who was sent away and how.
signal recruit_turned_away(follower, reason: String)

# Meals / morale (see MoraleSystem.gd, FOUNDATION_SPEC section 8)
## One meal tick resolved. (phase: "Dawn"/"Dusk", fed count, shorted count)
signal meal_served(phase: String, fed: int, shorted: int)
signal morale_changed(follower, new_morale: int)
## Low-morale mischief: a small resource loss with flavor text.
signal recruit_misbehaved(follower, text: String, kind: String, amount: int)
## Morale bottomed out -- they leave on the next missed meal unless fed.
signal recruit_departure_warning(follower)
signal recruit_departed(follower, reason: String)

# Housing (fund-a-house, FOUNDATION_SPEC section 9)
signal recruit_housed(follower, cell: Vector2i)

# Workers (resource gathering -- see Worker.gd / WorkerSystem.gd)
signal worker_count_changed(count: int)
## Currently unemitted: assignment moved from per-worker to the global
## priority list (which has its own priorities_changed below). Kept because a
## per-worker manual override is a flagged later add -- see GAME_OUTLINE
## Stage 1 -- and that's exactly what would emit this again.
signal worker_assignment_changed(worker)
## A worker finished a trip and banked its load. (worker, kind, amount)
signal worker_deposited(worker, kind: String, amount: int)

# Resource nodes / priorities (see ResourceNode.gd / ResourceField.gd)
signal resource_node_depleted(node)
## Emitted when the player reorders the list or edits a threshold, so the UI
## can re-render without polling WorkerSystem every frame.
signal priorities_changed

# Day/night (see DayNightCycle.gd). Berry regrowth and deer respawn hang off
# dawn_started; the meal ticks will hang off both.
signal dawn_started(day_number: int)
signal dusk_started(day_number: int)
## Fires only when the sub-phase word changes (Dawn/Daylight/Dusk/Night), not
## every frame -- it exists so the HUD clock can be signal-driven.
signal day_phase_changed(label: String)

# Combat / wildlife (see CombatSystem.gd, Wolf.gd, Combat.gd)
signal wolf_spawned(wolf)
signal wolf_departed(wolf, reason: String)
## Killed outright rather than driven off -- leaves a gatherable carcass.
signal wolf_killed(at: Vector2, bones: int)
## A fight began. Names rather than objects because the only consumer is the
## log, and an attacker can outlive the unit it was fighting.
signal combat_started(attacker_name: String, defender_name: String)
## A Warrior-category (or Might >= 6) recruit waded in unbidden -- the
## emergent-defence rule. This is the one the player is meant to notice.
signal combat_joined(follower, attacker_name: String)
## A Skeleton Worker was destroyed. Workers are the only unit wildlife can kill.
signal worker_destroyed(worker, cause: String)
## A living recruit broke off below 30% hp. Never fatal -- see CombatSystem.
signal recruit_injured(follower, cause: String)
signal recruit_recovered(follower)
## A predator ate a deer: the map loses the food, nobody gets hurt.
signal deer_taken_by_predator(node, predator_name: String)
## Flavor only: something hostile came too close to the Necromancer and thought
## better of it. Only fires while he is **inside his own lair band** -- the aura
## is a position now, not a flag (NECROMANCER_SPEC section 5, and see
## `CombatSystem.aura_protects_villain()`).
signal necromancer_feared(predator_name: String)
## He is in a fight. Either he walked to within 26px of something hostile
## (walking in is attacking) or something hit him first and he answered.
## **Carries the villain object** -- never assume there is one of him.
signal villain_engaged(villain, foe_name: String)
## He is out of it: he walked beyond his casting reach, or the fight ended under
## him. `reason` is for the log, not for logic.
signal villain_disengaged(villain, foe_name: String, reason: String)
## One unit's hp visibly changed, for the floating numbers (`CombatFeedback.gd`,
## COMBAT_FEEDBACK_SPEC §2). `kind` is "damage" or "heal"; `amount` is always
## positive and always the hp *actually* applied, not the roll.
##
## **`unit` is the data object, never a token** -- the layer reads
## `unit.position` at emit time, because a token's position is a frame stale.
##
## Emitted by `CombatSystem` alone. `Combat.gd` (the formula) and
## `Engagement.gd` (the clock) stay signal-free by design: both of their headers
## say they know nothing about anyone, and a view is not a good enough reason to
## make that stop being true. Anything else that ever changes hp -- traps, the
## crusade, a spell -- emits this from its own policy layer.
signal damage_shown(unit, amount: int, kind: String)

# The villain (see scripts/villain/Necromancer.gd)
## He hit 0 hp. **Carries the villain object** rather than assuming there is one
## of him -- ROGUELITE_REWORK section 11. Emitted from Necromancer.take_damage()
## so that *anything* which can damage him announces it, not just CombatSystem.
##
## Nothing ends the run on this yet: the run lifecycle is rework stage R4. For
## now Main logs it, loudly, so the moment is impossible to miss in testing.
signal villain_died(villain, cause: String)
## A journey milestone -- left the lair band, reached a landmark, came home.
## Carries the elapsed game-seconds so the log can show pacing without
## recomputing it. See TravelLog.gd: travel time is WORLD_MAP_PLAN §3's exit
## criterion, so it is instrumented rather than eyeballed.
signal travel_noted(text: String, elapsed_seconds: float)

# Lootable sites (see scripts/world/WorldSite.gd, LOOT_SITES_SPEC.md section 9)
#
# **Every one of these carries the villain object.** Never assume there is one
# of him (ROGUELITE_REWORK section 11) -- and mind the arity: a handler missing
# an argument connects fine and fails silently at emit (CLAUDE.md gotcha).
## A site paid out. `loot` is what actually reached his hands, not what was
## rolled -- the difference is the remainder left at the site (SORTIE_SPEC 4).
signal site_looted(villain, site, loot: Dictionary)
## One entry of a choice sheet was answered. Carries the choice id, not the
## label: labels are content and change with a copy edit.
signal site_choice_resolved(villain, site, choice_id: String)
## A relic reached his hands. It does nothing yet -- effects activate on deposit
## (LOOT_SITES_SPEC section 7), and this fires at the moment of finding.
signal relic_found(villain, relic_id: String)
## **The ledger R3 will read.** `axes` is R3's five, e.g. {"wealth": 1}; R2
## consumes none of it beyond a log line. Emitted from Necromancer.record_deed()
## so the array and the signal cannot disagree about what happened.
signal deed_committed(villain, deed_id: String, axes: Dictionary)
## Something posted at a site has decided he is a problem.
signal site_guardian_engaged(villain, site)

# The return leg (see scripts/villain/SortieSystem.gd, SORTIE_SPEC.md section 9)
## **The haul became real.** Emitted at the Throne, after `GameState` has taken
## it -- the banking rule (ROGUELITE_REWORK section 1) at sortie scale. `load`
## is everything banked this deposit, villain and escort together; `relics` is
## what woke up.
signal sortie_deposited(villain, load: Dictionary, relics: Array)
## He put something down. `to_site` is the site it went to -- the one he was
## standing at, or the `dropped_cache` that just appeared to hold it. **Never
## null:** the 2026-08-29 amendment struck destruction, so a drop always has
## somewhere to land.
signal sortie_load_dropped(villain, kind: String, amount: int, to_site)
## A cache appeared in open country because he dropped something there. The
## other half of the two drop paths, and the hook R3's scavengers want: this is
## the moment an abandoned haul becomes somebody else's problem to find.
signal sortie_cache_created(villain, cache)
## A relic reached the lair and woke up. `relic_found` fires when it is picked
## up and grants nothing; this is where its effect starts (LOOT_SITES 7).
signal relic_banked(villain, relic_id: String)

# Command Undead (the Necromancer's first spell -- see UndeadCommand.gd)
## Cast, moved, or re-ordered. Carries the new order and how many undead answered.
signal undead_commanded(at: Vector2, order_name: String, bound: int)
signal undead_dismissed

# Threat
signal threat_tier_escalated(new_tier: int)
signal crusade_incoming
signal crusade_survived

# Random events
signal event_triggered(event_data)
signal event_resolved(event_data, choice_index: int)

# Missions
signal mission_dispatched(mission, party: Array)
signal mission_resolved(mission, party: Array, outcome: String)
