class_name VillageBuilding
extends Node2D
## One building of the village: a job site with **job slots** and an
## **integrity** (LIVING_WORLD_SPEC section 5.2, ruling 14), or a house.
##
## The data lives on the node on purpose, the same call `ResourceNode` and
## `WorldSite` make: where it stands *is* its gameplay content (workers walk to
## it), so a separate data object would only be a second position to keep in
## step.
##
## **Named for its first owner** (section 5.6). The farm Frank works is
## *Frank's Farm* for the rest of the run -- including after Frank is dead and
## the slot stands empty, which is how the village reads its own losses.

## "farm", "woodcutter", "mill", "guardhouse", or "house".
var building_id: String = ""
var kind_name: String = ""        # "Farm", "Woodcutter's Hut" ...
var display_name: String = ""     # "Frank's Farm" once it has an owner
var owner_name: String = ""       # the first person who worked or lived here
var job: String = ""              # the job its slots hold ("" for the mill and houses)
var need: String = ""             # "food" / "wood" / "safety"
var slots: int = 0
## 0-1. Multiplies every load banked here (ruling 14). A destroyed building
## (0) banks nothing until it is repaired.
var integrity: float = 1.0
## Loads carried by this building's workers are banked at this building
## instead -- the woodcutters' logs go to the mill.
var banks_at: VillageBuilding = null
## The Guardhouse trains new guards.
var trains: bool = false
var sprite_path: String = ""
var size_px: float = 64.0
## Filled in by Village every time staffing changes: who holds a slot here.
var staff: Array = []
## For houses: who lives here.
var residents: Array = []
## A read-only question back to the village, for the panel's stores row.
var village = null

var _sprite: Sprite2D

func setup(data: Dictionary, at: Vector2) -> void:
	building_id = String(data.get("id", ""))
	kind_name = String(data.get("name", "Building"))
	display_name = kind_name
	job = String(data.get("job", ""))
	need = String(data.get("need", ""))
	slots = int(data.get("slots", 0))
	integrity = float(data.get("integrity", 1.0))
	trains = bool(data.get("trains", false))
	sprite_path = String(data.get("sprite", ""))
	size_px = float(data.get("size", 64.0))
	position = at
	name = "Village_%s" % building_id

func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex: Texture2D = load(sprite_path)
		_sprite.texture = tex
		_sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, size_px)
		Anchoring.foot(_sprite)
	_refresh_tint()

## Names the building after its first owner, once. "Frank's Farm".
func claim_name(person_name: String) -> void:
	if owner_name != "" or person_name == "":
		return
	owner_name = person_name
	display_name = "%s's %s" % [person_name, kind_name.trim_prefix("The ")]

func free_slots() -> int:
	return maxi(0, slots - staff.size())

func is_house() -> bool:
	return building_id.begins_with("house")

## Where its workers' loads land.
func bank_point() -> VillageBuilding:
	return banks_at if banks_at != null else self

## Damage takes integrity with it; zero is "destroyed" and banks nothing.
func damage(fraction: float) -> void:
	integrity = clampf(integrity - fraction, 0.0, 1.0)
	_refresh_tint()

func repair(fraction: float) -> void:
	integrity = clampf(integrity + fraction, 0.0, 1.0)
	_refresh_tint()

func _refresh_tint() -> void:
	if _sprite == null:
		return
	var g: float = lerpf(0.45, 1.0, integrity)
	_sprite.modulate = Color(g, g, g, 1.0)

func hit_radius() -> float:
	if _sprite == null or _sprite.texture == null:
		return 28.0
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(20.0, maxf(drawn.x, drawn.y) * Anchoring.HIT_RADIUS_FRACTION)

## Buildings are drawn from the foot up, so the click point is the middle of
## the drawn body rather than the foot.
func hit_centre() -> Vector2:
	if _sprite == null or _sprite.texture == null:
		return position
	return position - Vector2(0, Anchoring.drawn_content_size(_sprite).y * 0.5)

func get_inspect_data() -> Dictionary:
	var rows: Array = []
	var faction: String = village.display_name if village else "The village"
	rows.append({"label": "Belongs to", "value": faction})
	if is_house():
		var names: Array = residents.filter(func(v): return not v.dead).map(func(v): return v.label())
		rows.append({"label": "Lives here", "value": ", ".join(names) if not names.is_empty() else "Nobody, now"})
	else:
		if slots > 0:
			var names: Array = staff.map(func(v): return v.label())
			rows.append({"label": "Staff", "value": "%s  (%d / %d)" % [
				", ".join(names) if not names.is_empty() else "empty", staff.size(), slots]})
			if staff.is_empty():
				rows.append({"label": "", "value": "Nobody works here now.", "color": Color(1.0, 0.6, 0.45)})
		rows.append({"label": "Integrity", "value": "%d%%" % int(round(integrity * 100.0))})
		if village and need != "":
			rows.append({"label": "Output", "value": village.production_readout(self)})
		if trains:
			rows.append({"label": "Trains", "value": "New guards, %d s each" % int(village.train_seconds() if village else 0)})
	if village:
		rows.append({"label": "Village stores", "value": village.settlement.stock_line(), "muted": true})
	return {
		"title": display_name,
		"subtitle": "%s — %s" % [kind_name, faction] if display_name != kind_name else faction,
		"sprite": sprite_path,
		"description": _description(),
		"details": rows,
	}

func _description() -> String:
	match building_id:
		"farm": return "The village eats what comes out of these fields. Farmers walk out, cut, and carry it back here."
		"woodcutter": return "The woodcutters live and keep their axes here, and carry every log to the mill."
		"mill": return "Every log the village cuts is banked here. Damage it and every load is worth less."
		"guardhouse": return "Where the guards muster -- and where a man handed a spear is taught to hold it."
		_: return "Smoke from the chimney. Somebody lives here."
