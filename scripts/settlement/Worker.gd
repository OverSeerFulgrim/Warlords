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
	# working-but-unbalanced worker rather than a crash.
	might = 4
	walk_speed = 0.9
	woodcutting = 3
	mining = 3
	foraging = 2
	apply_race_baseline(RACE_ID)
	# After the baseline, not before -- max_hp() reads Might. A skeleton's
	# Might 4 puts it at 16 hp.
	heal_full()

func display_name() -> String:
	return worker_name

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

func inspect_race_id() -> String:
	return RACE_ID

func inspect_category() -> String:
	return RaceCatalog.category(RACE_ID)

## Read from the race row rather than stored as fields. A Worker has no use for
## Guile, Influence or Loyalty -- it can't take a bounty, can't defect, and
## can't be talked to -- but the panel shows all four stats for every character,
## and a skeleton's are racial constants with no variance anyway. Making them
## fields would be three pieces of state that nothing but this panel reads.
func inspect_social_stats() -> Dictionary:
	return {
		"guile": RaceCatalog.stat(RACE_ID, "guile"),
		"influence": RaceCatalog.stat(RACE_ID, "influence"),
		"loyalty": RaceCatalog.stat(RACE_ID, "loyalty"),
	}

func inspect_subtitle() -> String:
	return "Skeleton Worker — %s" % inspect_category()

func inspect_description() -> String:
	return "Raised from your own stores and set to work. It eats nothing, sleeps never, and has no opinion about any of it."

func inspect_extra_rows() -> Array:
	return [
		{"label": "Upkeep", "value": "None — the undead don't eat"},
		{"label": "", "value": "Every Skeleton Worker is identical. There is no point comparing them.", "muted": true},
	]
