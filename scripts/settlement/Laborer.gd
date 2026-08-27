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

# --- Stats. Subclasses fill these from races.json (COMBAT_SPEC section 2). ---
#
# **Attributes and skills are two layers, and the distinction is load-bearing.**
# An attribute is what the unit *is* and moves rarely; a skill is what it has
# *learned* and moves slowly. Nothing here stores an effective value -- see
# `skill_for()` -- because a stored copy goes stale the moment gear, training or
# a trait moves the attribute underneath it.

## The nine, on the 1-10 Human-Peasant-is-5 scale. Baseline for Workers, rolled
## per-recruit for Followers.
var strength: int = 5
var dexterity: int = 5
var speed: int = 5
var endurance: int = 5
var intelligence: int = 5
var guile: int = 5
var perception: int = 5
var tact: int = 5
var loyalty: int = 5

## The twelve baselines, `skill name -> 1-10`. A Dictionary rather than twelve
## fields: every consumer looks them up by the node's own `skill_key` string,
## and twelve fields plus a twelve-arm match would be the same data written
## twice. Filled from the race's template plus overrides.
var skills: Dictionary = {}

var walk_speed: float = 1.0  # multiplier on 1 grid cell/sec

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

## `max_hp = 8 + Endurance * 2` (COMBAT_SPEC section 2.4). Computed, never
## stored: a stored copy would silently go stale the moment anything changed
## Endurance -- which the Barracks' training already does, and equipment will do
## more of.
##
## **The formula is the C1 one with Endurance substituted for Might**, and the
## roster was authored so that no shipped number moves: Skeleton Worker End 4
## keeps hp 16, the wolf's End 5 keeps 18, the Necromancer's End 6 keeps 20.
## Human Peasant 18, an Ogre recruit 24.
const HP_BASE: int = 8
const HP_PER_ENDURANCE: int = 2

func max_hp() -> int:
	return HP_BASE + maxi(1, endurance) * HP_PER_ENDURANCE

## Current hit points. Initialised by heal_full() in each subclass's `_init`
## (and again by RecruitGenerator once the stat rolls have settled), because
## Endurance isn't known until then and max_hp() depends on it.
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

## The Combatant contract's profile (COMBAT_SPEC section 3.1 rule 3). Derived
## from the unit's own attributes every time -- no race is named, and no unit
## carries a hand-written profile. A Goblin picks up a sling because Dexterity
## is its highest attribute, not because anything checked for "goblin".
func combat_profile() -> Dictionary:
	return Combat.profile_for(strength, dexterity, intelligence)

## One attribute by name, for whichever one an attacker's profile defends
## against. Deliberately the general accessor rather than three getters: the
## defence key is data travelling in a Dictionary, so resolving it has to be a
## lookup, and a new profile must not need a new method here.
func combat_defence(key: String) -> int:
	return attribute(key)

## Any of the nine, by name. Returns the Human Peasant reference for an unknown
## name, for the same reason RaceCatalog does: an "average" answer is a far less
## damaging failure than a zero, which would make a unit invulnerable to
## whichever profile named it.
func attribute(key: String) -> int:
	match key:
		"strength": return strength
		"dexterity": return dexterity
		"speed": return speed
		"endurance": return endurance
		"intelligence": return intelligence
		"guile": return guile
		"perception": return perception
		"tact": return tact
		"loyalty": return loyalty
		_:
			push_warning("Laborer: unknown attribute '%s'" % key)
			return RaceCatalog.REFERENCE_VALUE

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

## Carry capacity = **Endurance** (COMBAT_SPEC section 2.1, confirmed by the
## 2026-08-06 amendment note 2). An Ogre hauls 8 units per trip; a Gnome 3.
##
## Moved off Strength deliberately: Strength was already damage plus two labor
## skills, and adding carry would have rebuilt Might under a new name. Endurance
## carrying hp *and* load also opens a high-Endurance/low-Strength porter, which
## is a real build rather than a strictly-worse one.
func carry_capacity() -> int:
	return max(1, endurance)

## The **effective** skill for a node's `skill_key`: baseline plus the governing
## attribute's modifier, computed here and never stored (COMBAT_SPEC 2.3).
##
## Takes the node's own `skill_key` rather than switching on resource kind,
## because the two aren't 1:1 -- bones come from both carcasses (foraging:
## finding them in the underbrush) and graves (mining: digging). An unknown key
## falls back to Foraging, which is the pre-rework behaviour.
##
## This is where the rework pays out in the settlement: a Gray Dwarf's Mining 9
## and a Skeleton Worker's 3 were already different, but the governing attribute
## now drags them further apart, and gather time is `4.0s * 5 / skill` -- so the
## margin shows up in the trip loop rather than in a stat panel.
func skill_for(skill_key: String) -> int:
	var key: String = skill_key if skills.has(skill_key) else "foraging"
	var governing: String = RaceCatalog.governing_attribute(key)
	return RaceCatalog.effective_skill(int(skills.get(key, 1)), attribute(governing))

## The unmodified authored value, for anything that wants to show the two apart.
## The inspection panel prints effective, because effective is what the game
## actually uses.
func skill_baseline(skill_key: String) -> int:
	return int(skills.get(skill_key, 1))

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

## Untrained skills are hidden rather than printed as 1s. Twelve skills is more
## than a panel can show without becoming a spreadsheet, and a race's identity
## is in the handful it is actually good at -- a Gnoll's Foraging 10, not its
## Research 1. The threshold is the template floor: at or below it, the race was
## never taught the thing.
const SKILL_SHOWN_ABOVE: int = 1

## Attributes are shown in COMBAT_SPEC section 2.1's own two groups, abbreviated
## to three letters so nine numbers fit on two lines. The profile row above them
## says which of the nine is currently doing the fighting, because that is the
## one the player most needs and it is derived rather than authored.
func _attribute_rows() -> Array:
	var p: Dictionary = combat_profile()
	return [
		{"label": "Profile", "value": "%s — %s %d vs %s" % [
			p["profile"], Combat.ATTACK_FOR_PROFILE[p["profile"]].capitalize(),
			p["attack_attr"], String(p["defence_key"]).capitalize()]},
		{"label": "Physical", "value": "Str %d   Dex %d   Spd %d   End %d" % [
			strength, dexterity, speed, endurance]},
		{"label": "Social", "value": "Int %d   Gui %d   Per %d   Tac %d   Loy %d" % [
			intelligence, guile, perception, tact, loyalty]},
	]

## **Effective** values, not baselines -- effective is what the game uses, and
## showing the authored number next to a gather time it does not explain would
## be worse than showing nothing.
func _skills_row() -> Dictionary:
	var shown: Array = []
	for key in RaceCatalog.all_skill_names():
		if int(skills.get(key, 0)) <= SKILL_SHOWN_ABOVE:
			continue
		shown.append("%s %d" % [String(key).capitalize(), skill_for(key)])
	if shown.is_empty():
		return {"label": "Skills", "value": "None trained", "muted": true}
	return {"label": "Skills", "value": "   ".join(shown)}

func get_inspect_data() -> Dictionary:
	var rows: Array = [
		{"label": "Activity", "value": status_label()},
		_hp_row(),
	]
	rows.append_array(_attribute_rows())
	rows.append(_skills_row())
	rows.append_array([
		{"label": "Carries", "value": "%d per trip" % carry_capacity()},
		{"label": "Walk speed", "value": "%s cells/sec" % String.num(walk_speed, 2)},
	])
	rows.append_array(inspect_extra_rows())
	return {
		"title": display_name(),
		"subtitle": inspect_subtitle(),
		"sprite": RaceCatalog.sprite(inspect_race_id()),
		"description": inspect_description(),
		"details": rows,
	}

## Copies the nine attributes and twelve skill baselines for `race_id` straight
## off the race row, with no variance. Used by Worker (which is interchangeable
## by design); Follower rolls per-recruit variance instead -- see
## RecruitGenerator.
func apply_race_baseline(race_id: String) -> void:
	if RaceCatalog.get_race(race_id).is_empty():
		push_warning("Laborer: no '%s' row in races.json -- keeping fallback stats." % race_id)
		return
	apply_attributes(RaceCatalog.attributes(race_id))
	skills = RaceCatalog.skill_baselines(race_id)
	walk_speed = RaceCatalog.walk_speed(race_id)

## Writes whichever of the nine a Dictionary carries, leaving the rest where
## they were. Shared by the race baseline and by RecruitGenerator's rolls, so
## exactly one place knows the field names.
func apply_attributes(attrs: Dictionary) -> void:
	strength = int(attrs.get("strength", strength))
	dexterity = int(attrs.get("dexterity", dexterity))
	speed = int(attrs.get("speed", speed))
	endurance = int(attrs.get("endurance", endurance))
	intelligence = int(attrs.get("intelligence", intelligence))
	guile = int(attrs.get("guile", guile))
	perception = int(attrs.get("perception", perception))
	tact = int(attrs.get("tact", tact))
	loyalty = int(attrs.get("loyalty", loyalty))
