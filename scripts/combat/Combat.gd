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
## combat_name()        -> String   # for logs
## combat_profile()     -> Dictionary   # {profile, attack_attr, defence_key, reach_px}
## combat_defence(key)  -> int      # the attribute an attacker's profile names
## max_hp()             -> int
## hp                   : int       # property, not a method
## take_damage(n:int)   -> int      # returns damage actually applied
## is_alive()           -> bool
## hp_fraction()        -> float    # 0.0-1.0, for the flee thresholds
## ```
##
## `Laborer` implements it for every worker and recruit; `Wolf` implements it
## for the creature and `Necromancer` for the villain. A future raider or bounty
## monster implements the same seven and gets combat for free.
##
## `combat_might()` was the C1 shape and is **gone**, not deprecated -- see
## `is_combatant()`, whose job is to make a unit that still implements it fail
## loudly instead of fighting badly.
##
## ## The model, and what it deliberately leaves out
##
## An **opposed exchange**: both sides swing, both swings land, every
## EXCHANGE_INTERVAL seconds while engaged.
##
## ```
## damage = attack attribute + d3 - floor(defence attribute / 2)   (minimum 1)
## ```
##
## Which two attributes those are comes from the attacker's profile (below).
## `EXCHANGE_INTERVAL`, the d3, the minimum of 1 and both-swings-land are
## **unchanged since C1** -- the stat rework moved the vocabulary, not the model.
##
## No dodging, no criticals, no initiative, no armour. That is the whole system
## on purpose: it is a primitive for bounties and raids to build on, not a
## tactics layer, and every one of those omissions is a thing that would need
## balancing before the settlement loop it serves has even been proven.
##
## The minimum of 1 matters more than it looks: without it a Gnome (Strength 2)
## swinging at an Ogre (Endurance 8) would deal `2 + d3 - 4` = nothing, ever,
## and a fight between mismatched units would hang instead of resolving.
##
## ## Attack profiles (COMBAT_SPEC §3)
##
## The shape of the formula is unchanged since C1; what moved is the *stat
## vocabulary*. An attack has two independent properties -- how far it reaches
## and which attribute drives it -- and casters are not a special case, they are
## the third row of one table:
##
## | Profile | Reach   | Attacks with | Defended by  |
## |---------|---------|--------------|--------------|
## | Melee   | 1 cell  | Strength     | Endurance    |
## | Ranged  | 5 cells | Dexterity    | Speed        |
## | Arcane  | 5 cells | Intelligence | Intelligence |
##
## A unit's profile falls out of `profile_for()` -- highest of Str/Dex/Int, ties
## to Strength. **That rule is the whole of v1 and it costs no new data.** If a
## unit ever needs a hand-written profile, that is a signal the rule is wrong,
## not that the unit is special: the wolf is Melee and the Necromancer Arcane
## because their authored attributes say so, not because anything names them.
##
## Class (COMBAT_SPEC §10) and equipped weapon (§9) are the higher-priority
## rules 1 and 2, and both are unbuilt -- when they arrive they override the
## profile at the unit, not here.

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
##
## **Deliberately still here after C2.** COMBAT_SPEC §4.1 deletes it in favour
## of morale-driven routing -- but that is C3, and the amendment block (note 5)
## is explicit that C3 stays post-R2 *because* the R2 escort's interpose
## threshold reads this constant. Deleting it here would break a slice that has
## not been written yet.
const FLEE_HP_FRACTION: float = 0.3

## Attack profile names. Strings rather than an enum because they travel through
## `combat_profile()` dictionaries and into inspection payloads and JSON.
const PROFILE_MELEE := "Melee"
const PROFILE_RANGED := "Ranged"
const PROFILE_ARCANE := "Arcane"

## Reach per profile, in cells (COMBAT_SPEC §3). Nothing consumes reach in this
## slice -- engagement distance is still CombatSystem's own tuning -- but it is
## part of the profile contract because the R2 escort and sortie work is what
## will read it, and a profile that carried only half its meaning would have to
## be widened again then.
const REACH_MELEE_CELLS: float = 1.0
const REACH_RANGED_CELLS: float = 5.0

## Which attribute defends against each profile.
const DEFENCE_FOR_PROFILE := {
	PROFILE_MELEE: "endurance",
	PROFILE_RANGED: "speed",
	PROFILE_ARCANE: "intelligence",
}

## Which attribute each profile attacks with. Here for symmetry and for anything
## that wants to explain a profile to the player; the attack *value* travels in
## the profile dictionary itself (see `profile_for`).
const ATTACK_FOR_PROFILE := {
	PROFILE_MELEE: "strength",
	PROFILE_RANGED: "dexterity",
	PROFILE_ARCANE: "intelligence",
}

## COMBAT_SPEC §3.1 rule 3: highest of Strength / Dexterity / Intelligence,
## ties resolve Strength > Dexterity > Intelligence.
##
## Returns the Combatant contract's profile dictionary:
##
##   {profile, attack_attr, defence_key, reach_px}
##
## Note the asymmetry in those two middle keys, which is the point of their
## names: **`attack_attr` is a value** (the attacker knows its own number) while
## **`defence_key` is a name** (the defender has to be asked, through
## `combat_defence()`). Passing the attacker's number and the defender's key is
## what lets one formula serve three profiles with no branching.
static func profile_for(strength: int, dexterity: int, intelligence: int) -> Dictionary:
	var name: String = PROFILE_MELEE
	var attack: int = strength
	# `>` not `>=` in both tests, so equal values fall through to the earlier
	# profile -- which is exactly the Str > Dex > Int tie order.
	if dexterity > attack:
		name = PROFILE_RANGED
		attack = dexterity
	if intelligence > attack:
		name = PROFILE_ARCANE
		attack = intelligence
	return {
		"profile": name,
		"attack_attr": attack,
		"defence_key": DEFENCE_FOR_PROFILE[name],
		"reach_px": reach_px_for(name),
	}

static func reach_px_for(profile_name: String) -> float:
	var cells: float = REACH_MELEE_CELLS if profile_name == PROFILE_MELEE else REACH_RANGED_CELLS
	return cells * float(SettlementGrid.CELL_SIZE)

## One side's swing. Public and static because it's the smallest reusable
## piece: an abstract bounty resolution that wants "how much would an Orc hurt a
## bandit" can call this without constructing anything.
##
## Takes the attacker's attack attribute and the defender's *defending*
## attribute -- which pair that is comes from the attacker's profile, not from
## here. This function still knows nothing about anyone.
static func damage_roll(attack_value: int, defence_value: int) -> int:
	var mitigation: int = int(floor(float(defence_value) / 2.0))
	return maxi(MIN_DAMAGE, attack_value + randi_range(1, DAMAGE_DIE) - mitigation)

## One full opposed exchange between two Combatants. **Both swings land even if
## one is lethal** -- the exchange is simultaneous, so a dying skeleton still
## gets its last hit in. That's deliberate: it's what lets a doomed defender
## contribute to driving a wolf off, which is the difference between a loss and
## a total loss.
##
## Returns what happened, so callers can log it without re-deriving anything:
## `{damage_to_a, damage_to_b, a_alive, b_alive}`.
static func exchange(a, b) -> Dictionary:
	# Each side swings with its OWN profile, so a Melee wolf biting an Arcane
	# Necromancer is resolved Str-vs-End one way and Int-vs-Int the other, in
	# the same exchange, with no branch.
	var pa: Dictionary = a.combat_profile()
	var pb: Dictionary = b.combat_profile()
	var to_b: int = damage_roll(pa["attack_attr"], b.combat_defence(pa["defence_key"]))
	var to_a: int = damage_roll(pb["attack_attr"], a.combat_defence(pb["defence_key"]))
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
	# **Kept in step with the contract, always.** This list is the only thing
	# standing between a half-migrated unit and a fight where it silently deals
	# minimum damage forever -- which is precisely what would have happened
	# across the C2 rework if `combat_might` had been left in here.
	for m in ["combat_name", "combat_profile", "combat_defence", "max_hp",
			"take_damage", "is_alive", "hp_fraction"]:
		if not x.has_method(m):
			return false
	return true
