class_name Prisoner
extends RefCounted
## **A living captive** (LIVING_WORLD_SPEC section 10, L3, 2026-09-27).
##
## Prisoners are a **different resource from corpses** (10.3), or capture-or-slay
## is a fake choice: a prisoner can be searched (once), sacrificed at the Dark
## Altar for a Ghoul, and -- later -- traded or hired. He eats (ruling 6).
##
## Two places he can be: **in tow**, on a rope behind the Necromancer who bound
## him (in `villain.prisoners` -- per-villain state on the villain), or **in a
## Cell** at home (`Settlement.prisoners`). In tow he is unbanked like any haul:
## if the man holding the rope falls, the rope goes slack.

var display_name: String = ""
var race_id: String = "human_peasant"
var faction: String = "human"
## Where he was taken, for the panel: "Harrowdale", "An Outlaw Cave".
var origin: String = ""
var sprite_path: String = ""
## The Villager he was, or null.
var person = null
var position: Vector2 = Vector2.ZERO
var in_cell: bool = false
var searched: bool = false
## Meals missed in a row. Fed resets it.
var missed_meals: int = 0

func status_line() -> String:
	var bits: Array = []
	bits.append("in the Cell" if in_cell else "on the rope")
	if missed_meals > 0:
		bits.append("hungry (%d missed)" % missed_meals)
	if searched:
		bits.append("searched")
	return ", ".join(bits)

func get_inspect_data() -> Dictionary:
	var rows: Array = [
		{"label": "Taken", "value": origin if origin != "" else "—"},
		{"label": "Held", "value": "In the Cell" if in_cell else "On a rope behind him"},
		{"label": "Fed", "value": "Missed %d meal%s" % [missed_meals, "" if missed_meals == 1 else "s"] if missed_meals > 0 else "Yes",
			"color": Color(1.0, 0.55, 0.4) if missed_meals > 0 else Color(0.8, 0.9, 0.8)},
		{"label": "Pockets", "value": "Searched" if searched else "Not searched yet"},
		{"label": "", "value": "A prisoner eats one food at dawn and at dusk. Two missed meals and he dies where he is held.", "muted": true},
	]
	return {
		"title": display_name,
		"subtitle": "Prisoner",
		"sprite": sprite_path,
		"description": "Alive, bound, and worth more to you that way than dead — for now.",
		"details": rows,
	}
