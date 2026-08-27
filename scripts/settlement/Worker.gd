class_name Worker
extends Laborer
## A Skeleton Worker: the undead labor unit, deliberately NOT a Follower.
## Followers are the roster/story unit type (traits, Guile/Influence/Loyalty,
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

func _init(p_name: String) -> void:
	worker_name = p_name
	# Fallbacks if races.json is missing the row -- degrades to a
	# working-but-unbalanced worker rather than a crash. Endurance 4 is the
	# value that keeps hp at the shipped 16.
	apply_attributes({
		"strength": 4, "dexterity": 2, "speed": 4, "endurance": 4,
		"intelligence": 1, "guile": 1, "perception": 2, "tact": 1, "loyalty": 10,
	})
	walk_speed = 0.9
	skills = {"woodcutting": 3, "mining": 3, "foraging": 2}
	apply_race_baseline(RACE_ID)
	# After the baseline, not before -- max_hp() reads Endurance. A skeleton's
	# Endurance 4 puts it at 16 hp, exactly where its old Might 4 did.
	heal_full()

func display_name() -> String:
	return worker_name

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

func inspect_race_id() -> String:
	return RACE_ID

func inspect_category() -> String:
	return RaceCatalog.category(RACE_ID)

func inspect_subtitle() -> String:
	return "Skeleton Worker — %s" % inspect_category()

func inspect_description() -> String:
	return "Raised from your own stores and set to work. It eats nothing, sleeps never, and has no opinion about any of it."

func inspect_extra_rows() -> Array:
	return [
		{"label": "Upkeep", "value": "None — the undead don't eat"},
		{"label": "", "value": "Every Skeleton Worker is identical. There is no point comparing them.", "muted": true},
	]
