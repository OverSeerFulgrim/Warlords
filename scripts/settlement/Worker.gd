class_name Worker
extends Laborer
## A Skeleton Worker: the undead labor unit, deliberately NOT a Follower.
## Followers are the roster/story unit type (traits, rolled attributes, morale,
## bounties and missions); Workers only gather. That split is an explicit
## design call, not an accident of history -- don't merge them without
## re-confirming it.
##
## Since recruits can now work too, the trip loop itself lives in `Laborer`
## (which both extend). What's left here is what makes a Worker a Worker:
## fixed skeleton stats and nothing else. Note there is still no `is_busy` and
## no bounty behaviour -- a Worker cannot be pulled off labor, because labor is
## all it is.
##
## Workers stay non-individual: stats are read straight from the race baseline
## with **no per-recruit RNG variance**, unlike living recruits
## (FOUNDATION_SPEC section 3 explicitly exempts Skeleton Workers from the
## `baseline + d3 - d3` roll -- "they're interchangeable by design"). Two
## skeletons are the same skeleton.

const RACE_ID := "skeleton_worker"

var worker_name: String
## **Which dead thing it is** (LIVING_WORLD L3, 2026-09-27). A Skeleton Worker by
## default; a Ghoul, summoned at the Altar for a living sacrifice, is the same
## unit type with the workbook's Ghoul row -- the trip loop, Command Undead and
## the escort all read `alignment`, not the class, so it joins every one of them.
var race_id: String = RACE_ID

func _init(p_name: String, p_race: String = RACE_ID) -> void:
	worker_name = p_name
	race_id = p_race
	# Fallbacks if races.json is missing the row -- degrades to a
	# working-but-unbalanced worker rather than a crash. Endurance 4 is the
	# value that keeps hp at the shipped 16.
	apply_attributes({
		"strength": 4, "dexterity": 2, "speed": 4, "endurance": 4,
		"intelligence": 1, "guile": 1, "perception": 2, "tact": 1, "loyalty": 10,
	})
	walk_speed = 0.9
	skills = {"woodcutting": 3, "mining": 3, "foraging": 2}
	apply_race_baseline(race_id)
	# After the baseline, not before -- max_hp() reads Endurance. A skeleton's
	# Endurance 4 puts it at 16 hp, exactly where its old Might 4 did.
	heal_full()

func display_name() -> String:
	return worker_name

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

func inspect_race_id() -> String:
	return race_id

func is_ghoul() -> bool:
	return race_id == "ghoul"

func inspect_category() -> String:
	return RaceCatalog.category(race_id)

func inspect_subtitle() -> String:
	return "%s — %s" % [String(RaceCatalog.get_race(race_id).get("display_name", "Skeleton Worker")), inspect_category()]

func inspect_description() -> String:
	if is_ghoul():
		return "A living man went onto the Altar and this got up. Stronger than bone, hungrier than it lets on, and yours."
	return "Raised from your own stores and set to work. It eats nothing, sleeps never, and has no opinion about any of it."

func inspect_extra_rows() -> Array:
	if is_ghoul():
		return [
			{"label": "Upkeep", "value": "None — the undead don't eat"},
			{"label": "", "value": "Summoned at the Dark Altar for a living sacrifice. Command Undead binds it like any of the dead.", "muted": true},
		]
	return [
		{"label": "Upkeep", "value": "None — the undead don't eat"},
		{"label": "", "value": "Every Skeleton Worker is identical. There is no point comparing them.", "muted": true},
	]
