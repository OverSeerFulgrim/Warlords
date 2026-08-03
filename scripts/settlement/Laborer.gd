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
## FLEEING is the combat addition: dropped their job and running for their idle
## anchor (their house, or the keep). They rejoin the loop as IDLE on arrival.
enum TripStage { IDLE, WALK_TO_NODE, GATHERING, WALK_HOME, FLEEING }

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

# ---------------- Combat (the Combatant contract -- see Combat.gd) ----------
#
# Every laborer can be attacked, so HP lives on the base class rather than on
# Worker and Follower separately. What *happens* when one drops is completely
# different for the two (a skeleton is destroyed, a recruit is only ever
# injured) -- that policy is CombatSystem's, not this class's.

## `max_hp = 8 + Might * 2`. Computed, never stored: Might is already the stat
## that makes a unit durable in every other system (it's carry capacity too),
## and a stored copy would silently go stale the moment anything changed Might
## -- which the Blacksmith's +1 Might already does, and equipment will do more
## of. Human Peasant 18, Skeleton Worker 16, an Ogre recruit 26.
const HP_BASE: int = 8
const HP_PER_MIGHT: int = 2

func max_hp() -> int:
	return HP_BASE + maxi(1, might) * HP_PER_MIGHT

## Current hit points. Initialised by heal_full() in each subclass's `_init`
## (and again by RecruitGenerator once the stat rolls have settled), because
## Might isn't known until then and max_hp() depends on it.
var hp: int = 1

## True while a living recruit is recovering from being beaten up. They keep
## their place on the roster and stay visible on the map -- they just can't be
## given a job (see can_work_now) until healed back to full.
##
## Only Followers are ever injured; a Worker that loses a fight is destroyed
## outright. The flag lives here anyway so `can_work_now()` is one check for the
## whole labor pool rather than a type test in WorkerSystem.
var is_injured: bool = false

## True while bound to the Necromancer's rally point by Command Undead. A
## rallied unit leaves the labor pool entirely (see can_labor) and UndeadCommand
## drives its movement instead of WorkerSystem's trip loop. Only ever set on
## undead -- see is_undead().
var rallied: bool = false

## Whether Command Undead reaches this unit. Read from races.json's `alignment`
## rather than from the class, so the ghouls and wraiths on the roadmap become
## commandable the day they exist and no living race ever can -- the spell binds
## the dead, not "things that are Workers".
func is_undead() -> bool:
	return RaceCatalog.get_race(inspect_race_id()).get("alignment", "") == "Undead"

## True while locked into an Engagement. The trip loop skips anyone with this
## set -- a unit trading blows with a wolf must not also be strolling off to a
## tree, and this is a cheaper way to say that than teaching every stage
## handler about combat.
var in_combat: bool = false

func heal_full() -> void:
	hp = max_hp()

## Returns the damage actually applied (clipped at 0 hp), so callers can log
## the real number rather than the roll.
func take_damage(amount: int) -> int:
	var before: int = hp
	hp = maxi(0, hp - maxi(0, amount))
	return before - hp

## Returns hp actually restored. Capped at max_hp -- see MoraleSystem for the
## +2-per-meal living regen and CombatSystem for skeleton repair at the Throne.
func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(max_hp(), hp + maxi(0, amount))
	return hp - before

func is_alive() -> bool:
	return hp > 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(1, max_hp()))

func combat_might() -> int:
	return might

func combat_name() -> String:
	return display_name()

## Whether this unit will pick up a *new* job. Distinct from `can_labor()`,
## which answers "is this unit in the labor pool at all" -- an injured recruit
## stays in the pool (so they still walk home, still idle by their house, still
## show up in the workforce summary) but is never handed a gathering trip.
## Taking them out of the pool entirely would freeze them mid-map wherever the
## wolf left them.
func can_work_now() -> bool:
	return not is_injured

## Drop everything and run for the idle anchor. Used both by units breaking off
## a fight and by bystanders scattering from one.
func begin_flee() -> void:
	abandon_trip()
	carrying_amount = 0
	carrying_kind = ""
	stage = TripStage.FLEEING

## Where they mill about with nothing to do. Defaults to the keep for Workers
## and for recruits still in the Barracks; once a recruit's house is funded it
## moves to their own doorstep, which is what makes a settled town look
## settled. Note this is *only* the idle anchor -- loads are still deposited at
## the keep, so a housed dwarf still walks their stone back to the Throne.
var idle_anchor: Vector2 = Vector2.ZERO
const IDLE_WANDER_RADIUS: float = 34.0

## Name for logs and the HUD. Overridden by both subclasses, which keep their
## own `worker_name` / `follower_name` fields rather than sharing one -- those
## names are load-bearing at a lot of call sites and mean subtly different
## things ("Skeleton Worker #3" is a serial number, "Thokk" is a person).
func display_name() -> String:
	return "Laborer"

## Whether this unit is in the labor pool at all. False while a Follower is off
## on a bounty or mission, and false for any undead currently bound to a rally
## point -- Command Undead takes them off the workforce for as long as it holds,
## which is the whole cost of casting it.
func can_labor() -> bool:
	return not rallied

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
	if in_combat:
		return "Fighting"
	if rallied:
		return "Bound to the rally point"
	match stage:
		TripStage.WALK_TO_NODE:
			return "Walking to %s" % (target_node.display_name() if target_node else "?")
		TripStage.GATHERING:
			if target_node and target_node.node_type == "deer":
				return "Hunting deer"
			return "Gathering %s" % carrying_kind_label()
		TripStage.WALK_HOME:
			return "Hauling %d %s home" % [carrying_amount, carrying_kind_label()]
		TripStage.FLEEING:
			return "Fleeing home"
		_:
			return "Recovering" if is_injured else "Idle"

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

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------
#
# Assembled here because the *shape* of a character panel is the same for a
# skeleton and a gray dwarf -- activity, stats, labor skills, carry, speed. The
# parts that genuinely differ are the four hooks below, which each subclass
# fills in. That keeps the per-object knowledge on the per-object script
# without making both of them re-list the same eight rows.

## races.json key, for the portrait and the race name.
func inspect_race_id() -> String:
	return ""

## "Warrior" / "Economy" / "Labor" ... -- what this unit is *for*.
func inspect_category() -> String:
	return ""

## The three social stats. Only Might lives on Laborer (it doubles as carry
## capacity); Guile/Influence/Loyalty are Follower's, and Worker reads them off
## the flat skeleton baseline rather than storing fields it never uses.
func inspect_social_stats() -> Dictionary:
	return {"guile": 0, "influence": 0, "loyalty": 0}

## Rows appended after the shared block -- morale, housing, traits. Empty for
## anything that has none of those.
func inspect_extra_rows() -> Array:
	return []

func inspect_subtitle() -> String:
	return ""

func inspect_description() -> String:
	return ""

## Colour-coded so a hurt unit is legible at a glance, the same way morale is.
## The "8 + Might x2" note is deliberate: Might driving durability is the single
## thing a player needs to understand about this combat system.
func _hp_row() -> Dictionary:
	var row := {"label": "Health", "value": "%d / %d hp" % [hp, max_hp()]}
	if is_injured:
		row["value"] += "  — Injured, not working"
		row["color"] = Color(1.0, 0.45, 0.45)
	elif hp_fraction() < Combat.FLEE_HP_FRACTION:
		row["color"] = Color(1.0, 0.45, 0.45)
	elif hp < max_hp():
		row["color"] = Color(0.95, 0.70, 0.40)
	return row

func get_inspect_data() -> Dictionary:
	var social: Dictionary = inspect_social_stats()
	var rows: Array = [
		{"label": "Activity", "value": status_label()},
		_hp_row(),
		{"label": "Stats", "value": "Might %d   Guile %d   Influence %d   Loyalty %d" % [
			might, social.get("guile", 0), social.get("influence", 0), social.get("loyalty", 0)]},
		{"label": "Labor", "value": "Woodcutting %d   Mining %d   Foraging %d" % [
			woodcutting, mining, foraging]},
		{"label": "Carries", "value": "%d per trip" % carry_capacity()},
		{"label": "Walk speed", "value": "%s cells/sec" % String.num(walk_speed, 2)},
	]
	rows.append_array(inspect_extra_rows())
	return {
		"title": display_name(),
		"subtitle": inspect_subtitle(),
		"sprite": RaceCatalog.sprite(inspect_race_id()),
		"description": inspect_description(),
		"details": rows,
	}

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
