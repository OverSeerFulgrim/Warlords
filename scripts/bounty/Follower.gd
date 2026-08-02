class_name Follower
extends Laborer
## A recruited settler. Deliberately not a Node -- followers are lightweight
## data objects; only the ones actively doing something on-screen need a
## visual representation. Keeps the "hundreds of followers" case cheap.
##
## Extends `Laborer` because recruits work: a settled Gray Dwarf out-mines
## every skeleton you own, which is most of the reason to recruit one. Might
## and the three labor skills, plus the whole trip-loop state machine, live on
## the base class; everything below is what makes a Follower a *person* rather
## than a job -- name, race identity, traits, the three social stats, and the
## bounty/mission behaviour Workers will never have.

var follower_name: String
var species: String  # display name of the race: "Orc", "Gray Dwarf", "Skeleton", ...

## races.json key ("gray_dwarf"). Blank for the legacy hand-built followers and
## for anything recruited through the old followers.json templates -- code that
## reads this must tolerate "".
var race_id: String = ""
var category: String = ""  # "Warrior" / "Economy" / "Research" / "Foraging" / "Versatile"
var rarity: String = ""    # "Common" / "Uncommon" / "Rare"

## Rolled the 5% exceptional bonus on their category-defining stat
## (FOUNDATION_SPEC section 3). Surfaced in the UI with a star -- these are
## "the recruits worth funding houses for early", so the player has to be able
## to see it.
var is_exceptional: bool = false

var traits: Array[String] = []  # e.g. ["Greedy", "Loyal", "Bloodthirsty", "Cowardly", "Fanatic"]

# Social stats. Might lives on Laborer (it's carry capacity as well as combat
# muscle). Kept to four total on purpose -- this is a settlement builder, not
# an RPG, and stat bloat is the fastest way to blow the prototype's scope.
var guile: int = 1
var influence: int = 1
var loyalty: int = 5  # 0-10. Low loyalty = betrayal/defection risk.

var is_busy: bool = false

func _init(p_name: String, p_species: String, p_traits: Array[String] = [],
		p_might: int = 1, p_guile: int = 1, p_influence: int = 1, p_loyalty: int = 5) -> void:
	follower_name = p_name
	species = p_species
	traits = p_traits
	might = p_might
	guile = p_guile
	influence = p_influence
	loyalty = p_loyalty

func display_name() -> String:
	return follower_name

## Followers stop gathering while they're away on a bounty or mission -- the
## trip loop skips anyone this returns false for, and WorkerSystem abandons
## whatever trip they were mid-way through.
func can_labor() -> bool:
	return not is_busy

## Name with the exceptional star, for lists and the info panel.
func label() -> String:
	return ("★ " + follower_name) if is_exceptional else follower_name

func has_trait(t: String) -> bool:
	return traits.has(t)

## Majesty-style decision: does this follower want to answer this bounty?
## Returns true/false rather than a hard command -- the player never directly
## orders anyone, only incentivizes.
func evaluate_bounty(bounty) -> bool:
	if is_busy:
		return false

	var interest: float = 0.0

	# Reward always matters, scaled down so it combines cleanly with trait bonuses.
	interest += float(bounty.reward) * 0.1

	# Species/trait affinities pull interest up or down.
	if has_trait("Greedy"):
		interest += float(bounty.reward) * 0.15
	if has_trait("Bloodthirsty") and bounty.bounty_type == "Harvest":
		interest += 3.0
	if has_trait("Fanatic") and bounty.bounty_type == "Reanimation":
		interest += 3.0
	if has_trait("Cowardly") and bounty.risk > 5:
		interest -= 4.0
	if has_trait("Loyal"):
		interest += 1.0  # loyal followers help out even for modest bounties

	# High-risk bounties need a little extra pull for anyone but the reckless.
	interest -= float(bounty.risk) * 0.2

	# A bit of per-follower randomness so the board doesn't feel like a solved
	# spreadsheet -- two goblins with identical stats can still choose differently.
	interest += randf_range(-1.5, 1.5)

	return interest >= 3.0

## Stat check used by MissionSystem. Returns a score to compare against a
## mission's difficulty; the caller decides the SUCCESS / COMPLICATED /
## FAILURE band.
func mission_check(relevant_stat: String) -> int:
	var base: int = 1
	match relevant_stat:
		"might":
			base = might
		"guile":
			base = guile
		"influence":
			base = influence
		_:
			base = 1
	return base + randi_range(0, 3)
