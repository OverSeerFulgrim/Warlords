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
## better of it.
signal necromancer_feared(predator_name: String)

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
