class_name Engagement
extends RefCounted
## One ongoing fight: a single attacker against however many defenders have
## piled in. Owns nothing but the clock and the participant list -- the damage
## itself is `Combat.exchange()`, and what happens to a unit that drops is the
## caller's business (see CombatSystem).
##
## Split from `Combat` because that file is a pure formula anything can call,
## and this is the bookkeeping for a fight that lasts over time. A bounty that
## wants an instant abstract resolution calls `Combat.exchange()` in a loop and
## never touches this; a raid that wants a fight the player can watch on the map
## builds one of these.
##
## **Many-defenders is modelled as the attacker fighting each one in turn**,
## one exchange per defender per tick. That is not a tactics model -- it just
## means three orcs beat a wolf roughly three times as fast as one, which is the
## only property the emergent-defence rule (CombatSystem) needs from it.

## The lone attacker. Everything in `defenders` is fighting it.
var attacker
var defenders: Array = []

var _timer: float = 0.0

## Set by whoever resolves the fight when it should stop running.
var finished: bool = false

func _init(p_attacker) -> void:
	attacker = p_attacker

func add_defender(d) -> bool:
	if d == null or defenders.has(d):
		return false
	defenders.append(d)
	return true

func remove_defender(d) -> void:
	defenders.erase(d)

func has_defenders() -> bool:
	return not defenders.is_empty()

## Advances the fight clock. Returns an Array of per-defender exchange results
## (empty on the frames between exchanges), each entry
## `{defender, damage_to_attacker, damage_to_defender, ...}` -- see
## Combat.exchange(), plus the `defender` key so the caller knows who it was.
##
## Runs a `while` rather than an `if` so a very high debug time scale (60x) can
## resolve more than one exchange in a frame instead of silently slowing combat
## down relative to everything else.
func tick(delta: float) -> Array:
	var results: Array = []
	if finished or attacker == null or not attacker.is_alive() or defenders.is_empty():
		return results
	_timer += delta
	while _timer >= Combat.EXCHANGE_INTERVAL:
		_timer -= Combat.EXCHANGE_INTERVAL
		for d in defenders.duplicate():
			if not attacker.is_alive():
				break
			if d == null or not d.is_alive():
				continue
			var r: Dictionary = Combat.exchange(attacker, d)
			r["defender"] = d
			results.append(r)
	return results
