class_name Laborer
extends RefCounted
## Everything needed to walk to a resource node and bring a load home: racial
## labor stats plus the trip-loop state machine WorkerSystem drives.
##
## **Why this exists.** Skeleton Workers and recruited Followers are still two
## deliberately different unit types -- Followers have traits, Guile/Influence/
## Loyalty, and take bounties and missions; Workers have none of that and never
## will (that separation is an explicit design call, see Worker.gd). But once
## recruits could be put to work, both needed the *same* trip loop, and a
## settled Gray Dwarf out-mining every skeleton you own is the whole point of
## recruiting one. So the labor half is factored out here and both extend it,
## rather than merging the two classes or duplicating the state machine.
##
## Read that boundary as: **this class is the job, not the person.** Anything
## about who someone is (traits, loyalty, race identity, bounty appetite)
## belongs on Worker/Follower, not here.
##
## `position` is authoritative simulation state -- see CLAUDE.md's convention
## about tokens being pure views. WorkerToken/FollowerToken read it and draw
## there; they never write it.

## The trip loop, per FOUNDATION_SPEC section 6:
##   walk to node -> gather until carry-full or node empty -> walk home ->
##   deposit -> repeat
## IDLE covers both "no job yet" and "nothing worth doing" (every priority is
## above its threshold, or the map is out of that resource).
enum TripStage { IDLE, WALK_TO_NODE, GATHERING, WALK_HOME }

# --- Labor stats. Subclasses fill these from races.json. ---
var might: int = 5           # also the carry capacity, per FOUNDATION_SPEC section 6
var walk_speed: float = 1.0  # multiplier on 1 grid cell/sec
var woodcutting: int = 5
var mining: int = 5
var foraging: int = 5

# --- Trip state (advanced by WorkerSystem, read by the tokens) ---
var position: Vector2 = Vector2.ZERO
var stage: int = TripStage.IDLE
var target_node = null        # ResourceNode; untyped to avoid a load-order dependency
var carrying_kind: String = ""
var carrying_amount: int = 0
var gather_timer: float = 0.0
## Where the current gather action's clock has to reach. Cached per action
## rather than recomputed each frame so a mid-trip stat change can't
## retroactively shorten work already done.
var gather_action_target: float = 0.0
## Idle wander bookkeeping -- only used while stage == IDLE.
var idle_target: Vector2 = Vector2.ZERO
var idle_wait: float = 0.0

## Name for logs and the HUD. Overridden by both subclasses, which keep their
## own `worker_name` / `follower_name` fields rather than sharing one -- those
## names are load-bearing at a lot of call sites and mean subtly different
## things ("Skeleton Worker #3" is a serial number, "Thokk" is a person).
func display_name() -> String:
	return "Laborer"

## False while a Follower is off on a bounty or mission. Workers are always
## available -- they have nothing else to do.
func can_labor() -> bool:
	return true

## Carry capacity = Might (FOUNDATION_SPEC section 6). An Ogre hauls 9 units
## per trip; a Gnome 2. This is what makes Might matter for labor without
## inventing a separate carry stat.
func carry_capacity() -> int:
	return max(1, might)

## Which labor skill applies to a given node. Takes the node's own skill_key
## rather than switching on resource kind, because the two aren't 1:1 -- bones
## come from both carcasses (foraging: finding them in the underbrush) and
## graves (mining: digging).
func skill_for(skill_key: String) -> int:
	match skill_key:
		"woodcutting":
			return woodcutting
		"mining":
			return mining
		"foraging":
			return foraging
		_:
			return foraging

## Pixels per second. FOUNDATION_SPEC section 4: walk speed 1.0 = 1 grid cell
## per second, so a 0.9 skeleton covers 0.9 cells/sec and a 1.2 gnoll 1.2.
func walk_speed_px() -> float:
	return walk_speed * float(SettlementGrid.CELL_SIZE)

func is_carrying_full() -> bool:
	return carrying_amount >= carry_capacity()

func carrying_kind_label() -> String:
	return carrying_kind.capitalize() if carrying_kind != "" else "nothing"

## Human-readable job state for the HUD info panel and the workforce summary.
func status_label() -> String:
	match stage:
		TripStage.WALK_TO_NODE:
			return "Walking to %s" % (target_node.display_name() if target_node else "?")
		TripStage.GATHERING:
			if target_node and target_node.node_type == "deer":
				return "Hunting deer"
			return "Gathering %s" % carrying_kind_label()
		TripStage.WALK_HOME:
			return "Hauling %d %s home" % [carrying_amount, carrying_kind_label()]
		_:
			return "Idle"

## Drops the current job and any claim on its node. Called when the node runs
## dry underneath them, when the priority list changes in a way that makes the
## current trip the wrong one, and when a Follower is pulled away onto a
## bounty mid-trip.
func abandon_trip() -> void:
	if target_node:
		target_node.claims = max(0, target_node.claims - 1)
		target_node.freeze(false)
	target_node = null
	stage = TripStage.IDLE
	gather_timer = 0.0

## Copies the four character stats / three labor skills for `race_id` straight
## off the race baseline, with no variance. Used by Worker (which is
## interchangeable by design); Follower rolls per-recruit variance instead --
## see RecruitGenerator.
func apply_race_baseline(race_id: String) -> void:
	if RaceCatalog.get_race(race_id).is_empty():
		push_warning("Laborer: no '%s' row in races.json -- keeping fallback stats." % race_id)
		return
	might = RaceCatalog.stat(race_id, "might")
	walk_speed = RaceCatalog.walk_speed(race_id)
	woodcutting = RaceCatalog.labor(race_id, "woodcutting")
	mining = RaceCatalog.labor(race_id, "mining")
	foraging = RaceCatalog.labor(race_id, "foraging")
