class_name Combat
extends RefCounted
## The combat formula. **One function, deliberately** -- Stage-4 bounty
## resolution and Stage-5 raids are planned consumers, and the wolf is only the
## first caller. Nothing in this file knows what a wolf, a worker or a resource
## node is; it takes two Combatants and hits them together.
##
## If you find yourself writing a second damage formula somewhere else, that's
## the mistake this file exists to prevent.
##
## ## The Combatant contract
##
## Duck-typed, same as `get_inspect_data()` (see InspectionPanel.gd) -- GDScript
## has no `interface`. Anything that fights implements:
##
## ```
## combat_name()      -> String   # for logs
## combat_might()     -> int      # the only stat combat reads
## max_hp()           -> int
## hp                 : int       # property, not a method
## take_damage(n:int) -> int      # returns damage actually applied
## is_alive()         -> bool
## hp_fraction()      -> float    # 0.0-1.0, for the flee thresholds
## ```
##
## `Laborer` implements it for every worker and recruit; `Wolf` implements it
## for the creature. A future raider or bounty monster implements the same six
## and gets combat for free.
##
## ## The model, and what it deliberately leaves out
##
## An **opposed exchange**: both sides swing, both swings land, every
## EXCHANGE_INTERVAL seconds while engaged.
##
## ```
## damage = attacker Might + d3 - floor(defender Might / 2)      (minimum 1)
## ```
##
## No dodging, no criticals, no ranged attacks, no initiative, no armour. Might
## is the only stat that matters. That is the whole system on purpose: it is a
## primitive for bounties and raids to build on, not a tactics layer, and every
## one of those omissions is a thing that would need balancing before the
## settlement loop it serves has even been proven.
##
## The minimum of 1 matters more than it looks: without it a Gnome (Might 2)
## swinging at an Ogre (Might 9) would deal `2 + d3 - 4` = nothing, ever, and a
## fight between mismatched units would hang instead of resolving.

## Seconds between exchanges while two units are engaged. A delta accumulator
## drives it (see Engagement), so it inherits the debug time scale like every
## other timer in the project.
const EXCHANGE_INTERVAL: float = 1.5

## d3, per the same die the recruit stat roll uses (FOUNDATION_SPEC section 3).
const DAMAGE_DIE: int = 3

## A swing always accomplishes something. See the class header.
const MIN_DAMAGE: int = 1

## Below this fraction of max hp, a living recruit breaks off and runs home.
## Living recruits are never killed by wildlife (see CombatSystem), so this is
## what makes that promise true rather than a special case at 0 hp.
const FLEE_HP_FRACTION: float = 0.3

## One side's swing. Public and static because it's the smallest reusable
## piece: an abstract bounty resolution that wants "how much would an Orc hurt a
## bandit" can call this without constructing anything.
static func damage_roll(attacker_might: int, defender_might: int) -> int:
	var mitigation: int = int(floor(float(defender_might) / 2.0))
	return maxi(MIN_DAMAGE, attacker_might + randi_range(1, DAMAGE_DIE) - mitigation)

## One full opposed exchange between two Combatants. **Both swings land even if
## one is lethal** -- the exchange is simultaneous, so a dying skeleton still
## gets its last hit in. That's deliberate: it's what lets a doomed defender
## contribute to driving a wolf off, which is the difference between a loss and
## a total loss.
##
## Returns what happened, so callers can log it without re-deriving anything:
## `{damage_to_a, damage_to_b, a_alive, b_alive}`.
static func exchange(a, b) -> Dictionary:
	var to_b: int = damage_roll(a.combat_might(), b.combat_might())
	var to_a: int = damage_roll(b.combat_might(), a.combat_might())
	var dealt_b: int = b.take_damage(to_b)
	var dealt_a: int = a.take_damage(to_a)
	return {
		"damage_to_a": dealt_a,
		"damage_to_b": dealt_b,
		"a_alive": a.is_alive(),
		"b_alive": b.is_alive(),
	}

## Sanity check for anything about to be handed to exchange(). Cheap insurance
## against a new unit type being wired in half-implemented -- combat failing
## loudly at the call site beats it silently dealing 0 damage forever.
static func is_combatant(x) -> bool:
	if x == null:
		return false
	for m in ["combat_name", "combat_might", "max_hp", "take_damage", "is_alive", "hp_fraction"]:
		if not x.has_method(m):
			return false
	return true
