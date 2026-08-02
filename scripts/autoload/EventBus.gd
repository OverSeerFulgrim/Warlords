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
