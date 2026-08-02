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

func display_name() -> String:
	return worker_name
