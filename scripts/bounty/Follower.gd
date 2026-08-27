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

# **The nine attributes all live on Laborer now** (COMBAT_SPEC section 2.1) --
# including Guile and Loyalty, which used to be declared here. Redeclaring them
# would shadow the base class's fields, and every consumer reads them through
# `attribute()` anyway.
#
# `influence` is **retired, not moved**: it was vague and barely read, and
# Leadership (Tact) and Mercantile (Guile) cover what it gestured at, both as
# trainable skills rather than a fixed attribute (COMBAT_SPEC section 2.1).

var is_busy: bool = false

# ---------------- Morale & meals (FOUNDATION_SPEC section 8) ----------------

## 1-10, starts at 7. Per-recruit rather than one settlement-wide meter --
## FOUNDATION_SPEC section 8 calls that out explicitly ("cheap now, enables
## 'the hungry ogre riots first' later"), and it is what lets the feeding order
## actually matter: the faithful get fed, malcontents starve.
var morale: int = 7

## Meal bookkeeping for the current dawn->dawn cycle (2 meals: dawn + dusk).
## Reset at each dawn, after the previous cycle has been scored for the
## fed-all-day morale bonus.
var meals_eaten_this_cycle: int = 0
var meals_missed_this_cycle: int = 0

## Set when morale first bottoms out at 1 and the departure warning fires.
## They then leave on the *next* missed meal, not immediately -- the warning is
## a chance to recover, not a formality.
var departure_warned: bool = false

# ---------------- Housing (FOUNDATION_SPEC section 9, fund-a-house) ----------

## False while they're still living in the Barracks and occupying a slot.
var is_housed: bool = false
## Grid cell of their own house once funded. (-1,-1) while unhoused.
var house_cell: Vector2i = Vector2i(-1, -1)

const MORALE_MIN: int = 1
const MORALE_MAX: int = 10
const MORALE_START: int = 7

func adjust_morale(delta: int) -> void:
	morale = clampi(morale + delta, MORALE_MIN, MORALE_MAX)

## How they feel about you on the way out, for the departure-memory system
## (GAME_OUTLINE gap #6) -- stored, never read yet.
##
## Loyalty is the anchor because it is the stat that already means "how much
## slack do they cut you": a Loyalty-10 fanatic who starved out still half
## understands (+2), a Loyalty-3 goblin leaves bitter (-5). Morale at the
## moment of leaving nudges it, though in practice that's almost always 1,
## since starvation is currently the only way anyone departs.
func departure_disposition() -> int:
	return clampi(loyalty - 8 + (morale - MORALE_MIN), -10, 10)

## Attributes arrive as a Dictionary rather than as positional arguments. Nine
## of them would be an unreadable call site, and every caller already has them
## in a Dictionary -- RecruitGenerator rolls one, the event templates author
## one. Anything the Dictionary omits keeps the Laborer default of 5.
func _init(p_name: String, p_species: String, p_traits: Array[String] = [],
		p_attributes: Dictionary = {}) -> void:
	follower_name = p_name
	species = p_species
	traits = p_traits
	apply_attributes(p_attributes)
	# Last, because max_hp() reads Endurance. RecruitGenerator calls heal_full()
	# again after its exceptional-attribute bump for the same reason.
	heal_full()

func display_name() -> String:
	return follower_name

## Followers stop gathering while they're away on a bounty or mission -- the
## trip loop skips anyone this returns false for, and WorkerSystem abandons
## whatever trip they were mid-way through.
func can_labor() -> bool:
	return not is_busy and super()

## Name with the exceptional star, for lists and the info panel.
func label() -> String:
	return ("★ " + follower_name) if is_exceptional else follower_name

func has_trait(t: String) -> bool:
	return traits.has(t)

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

func inspect_race_id() -> String:
	return race_id

func inspect_category() -> String:
	return category

func inspect_subtitle() -> String:
	var cat: String = category if category != "" else "Recruit"
	return "%s — %s" % [species, cat]

## Derived rather than hand-written per race: rarity and category already say
## what kind of recruit this is, and alignment says how they'll get on with the
## rest of the settlement once rivalries exist.
func inspect_description() -> String:
	var parts: Array = []
	if rarity != "":
		parts.append("%s %s recruit." % [rarity, category.to_lower() if category != "" else ""])
	var alignment: String = RaceCatalog.get_race(race_id).get("alignment", "")
	if alignment != "":
		parts.append("%s-aligned." % alignment)
	if is_exceptional:
		parts.append("Exceptional — a cut above their own kin.")
	return " ".join(parts).strip_edges()

func inspect_extra_rows() -> Array:
	var rows: Array = []

	# Morale first: it is the thing that changes, and the thing that decides
	# whether this recruit is about to steal from you or walk out.
	var morale_row := {"label": "Morale", "value": "%d / 10" % morale}
	if morale <= MORALE_MIN:
		morale_row["color"] = Color(1.0, 0.45, 0.45)
	elif morale <= 3:
		morale_row["color"] = Color(0.95, 0.70, 0.40)
	rows.append(morale_row)
	if departure_warned:
		rows.append({"label": "", "value": "Warned: will leave on the next missed meal.",
			"color": Color(1.0, 0.45, 0.45)})

	rows.append({"label": "Eats", "value": "%s per meal, twice a day"
		% String.num(RaceCatalog.food_per_meal(race_id), 2)})

	if is_housed:
		rows.append({"label": "Lives at", "value": "Their own house, cell %s" % house_cell})
	else:
		rows.append({"label": "Lives at", "value": "The Barracks — occupying a slot"})

	if is_busy:
		rows.append({"label": "", "value": "Away on a bounty or mission — not gathering.", "muted": true})

	if not traits.is_empty():
		rows.append({"label": "Traits", "value": ", ".join(traits)})

	return rows

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
##
## `relevant_stat` is now any of the nine attributes or any of the twelve
## skills, resolved in that order -- a mission that wants raw muscle names
## "strength", one that wants a negotiator names "mercantile" and gets the
## effective value with Guile already folded in. Missions authored against the
## retired four-stat names fall through to the attribute lookup's own
## average-rather-than-zero fallback.
func mission_check(relevant_stat: String) -> int:
	var base: int = attribute(relevant_stat) if RaceCatalog.attributes(race_id).has(relevant_stat) \
		else skill_for(relevant_stat)
	return base + randi_range(0, 3)
