class_name Downed
extends RefCounted
## **A man at the bottom of his health bar** (LIVING_WORLD_SPEC section 11.2,
## L3, 2026-09-27). At 0 hp a humanoid does not die: he goes down where he fell,
## with a bleed-out window. During it he can be **bound** (a prisoner), **finished**
## (a corpse, raisable), or **rescued** by his own side. When the window runs out
## he dies of it.
##
## Data only; `Captives` owns the list, the clock and the view. `person` is the
## Villager he was (so a rescue gives the village its Frank back), or null for
## a site guardian, whose node is gone the moment it drops.

var display_name: String = ""
var race_id: String = "human_peasant"
## "human" (the village) or "outlaw". Decides who comes to rescue him.
var faction: String = "human"
var sprite_path: String = ""
var position: Vector2 = Vector2.ZERO
var bleed_left: float = 45.0
var bleed_total: float = 45.0
## Whoever put him down -- credited with the death if he bleeds out.
var killer = null
## The Villager he was, or null.
var person = null
## Where he was put down: "Harrowdale", "An Outlaw Cave".
var origin: String = ""
## A guard on his way to fetch him.
var rescuer = null
## A guard carrying him home. While set, he does not bleed.
var carrier = null

func is_carried() -> bool:
	return carrier != null

## The Combatant-ish questions the HUD and the minimap ask of anything drawn.
func is_alive() -> bool:
	return false

func combat_name() -> String:
	return display_name

func get_inspect_data() -> Dictionary:
	var rows: Array = [
		{"label": "Health", "value": "Down — 0 hp", "color": Color(1.0, 0.45, 0.45)},
	]
	if is_carried():
		rows.append({"label": "Now", "value": "Being carried home by %s" % String(carrier.villager_name)})
	else:
		rows.append({"label": "Bleeding out", "value": "%d s" % int(ceil(bleed_left)),
			"color": Color(1.0, 0.7, 0.4) if bleed_left > 15.0 else Color(1.0, 0.45, 0.45)})
	rows.append({"label": "", "value": "Stand over him: bind him (a prisoner — he eats, and he is worth more than a corpse) or finish him (a body to raise). Leave him and his own may drag him home.", "muted": true})
	return {
		"title": "%s — down" % display_name,
		"subtitle": "Unconscious, where he fell",
		"sprite": sprite_path,
		"description": "Not dead yet. He will be, if nobody decides otherwise.",
		"details": rows,
	}
