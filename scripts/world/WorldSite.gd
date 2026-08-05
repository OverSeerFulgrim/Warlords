extends Node2D
class_name WorldSite
## A fixed, inert thing standing in the world: a village building, the sealed
## ritual ground, a roadside landmark.
##
## **Deliberately not a `Building`.** `Building` is a settlement citizen -- it
## has a cost, a catalog entry, a power value, a grid cell, and it emits
## `building_placed`. None of that is true of somebody else's house. A world
## site is a sprite, a position, and an inspection payload; giving it the
## settlement's machinery would mean the player's Power score counted the human
## lord's manor.
##
## Everything it says comes from `data/world_sites.json`, so adding a hamlet is
## a data edit. It implements `get_inspect_data()` and nothing else, which is
## the whole contract for being clickable (see InspectionPanel.gd).

var site_id: String = ""
var display_name: String = "Ruin"
var subtitle: String = ""
var description: String = ""
var detail_rows: Array = []
var sprite_path: String = ""
## Radius in pixels for click selection, derived from the drawn size.
var pick_radius: float = 32.0

var _sprite: Sprite2D

## `size_px` is the drawn width; every commissioned/pack sprite in this project
## is far larger than its on-screen size and gets scaled down at use.
func setup(data: Dictionary, world_position: Vector2, size_px: float) -> void:
	site_id = String(data.get("id", ""))
	display_name = String(data.get("name", "Ruin"))
	subtitle = String(data.get("subtitle", ""))
	description = String(data.get("description", ""))
	detail_rows = data.get("details", [])
	sprite_path = String(data.get("sprite", ""))
	position = world_position
	pick_radius = maxf(18.0, size_px * 0.6)

	_sprite = Sprite2D.new()
	_sprite.centered = true
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex: Texture2D = load(sprite_path)
		_sprite.texture = tex
		if tex.get_size().x > 0.0:
			_sprite.scale = Vector2.ONE * (size_px / tex.get_size().x)
	else:
		push_warning("WorldSite '%s': sprite not found at %s" % [site_id, sprite_path])
	if data.has("modulate"):
		_sprite.modulate = Color(String(data["modulate"]))
	add_child(_sprite)
	# A house stands on the ground at its position, like everything else. At
	# village sizes a centred sprite buries the lower half of the building.
	Anchoring.foot(_sprite)
	# Under the units (workers are z 0, the villain 5, the wolf 6) but over
	# terrain: a patrol walking past a house should pass in front of it.
	z_index = -1

func hit_radius() -> float:
	return pick_radius

func get_inspect_data() -> Dictionary:
	var rows: Array = []
	for row in detail_rows:
		rows.append({"label": String(row.get("label", "")), "value": String(row.get("value", "")),
			"muted": bool(row.get("muted", false))})
	return {
		"title": display_name,
		"subtitle": subtitle,
		"sprite": sprite_path,
		"description": description,
		"details": rows,
	}
