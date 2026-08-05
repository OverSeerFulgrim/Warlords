extends Node2D
class_name Building
## A placed structure. For the prototype, buildings are simple: they exist on
## the grid, optionally tick out resources on a timer, optionally gate a
## species' recruitment (housing), and contribute to Power. Everything is now
## data-driven from data/buildings.json via BuildingCatalog -- see
## make_from_data() below -- rather than one hardcoded factory per building.

@export var building_id: String = ""
@export var display_name: String = ""
@export var category: String = ""  # "resource" | "housing" | "functional" | "main"
@export var resource_kind: String = ""   # "" if it doesn't passively generate
@export var resource_per_tick: int = 0
@export var tick_interval: float = 5.0
@export var power_value: int = 0
@export var sprite_path: String = ""  # res:// path to a texture; empty = no visual yet

## One line of "what is this for", shown by the inspection panel. Data, not
## code -- it comes straight from the buildings.json row, so adding a building
## never means adding a branch to a description function somewhere.
@export var description: String = ""

## Housing: which Follower.species this building's presence unlocks
## recruitment for. "" for buildings that aren't housing.
@export var housing_species: String = ""

## Intake capacity, for category == "housing_intake" (the Barracks, and only
## the Barracks). 0 for everything else. See SettlementGrid.barracks_capacity().
@export var capacity: int = 0

## For category == "housing_home": which race lives here. Drives the clustered
## housing style ("build next to an existing same-race house") and the
## per-race sprite/tint. "" for every other building.
@export var house_race_id: String = ""
## For category == "housing_home": whose house this is. Set by
## SettlementGrid.fund_house() at the same time as display_name, so the
## inspection panel can name the resident without going hunting through the
## roster for whoever happens to live at this cell.
@export var house_owner_name: String = ""
## Per-race colour wash applied to the sprite, so a street of goblin burrows
## reads differently from a minotaur's lodge without needing distinct art.
@export var sprite_tint: Color = Color.WHITE

## Main building only (category == "main"): the Crusade's actual target. See
## ThreatSystem._resolve_crusade(). Unused (0) for every other building.
@export var is_main_building: bool = false
@export var max_hp: int = 0
var hp: int = 0

var _tick_timer: float = 0.0
var cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	set_process(resource_kind != "")
	_setup_sprite()
	if max_hp > 0 and hp <= 0:
		hp = max_hp

## **Content height a building's art is drawn at, in world pixels. 104 = 1.63
## tiles.** It was `CELL_SIZE` (64), which made every structure exactly as big
## as the square of ground it sat on -- correct as a footprint, wrong as a
## building. A keep should loom over its tile.
##
## Deliberately a separate constant rather than `CELL_SIZE`: the cell is the
## *footprint* (one building, one tile, and the grid, walk speed and terrain
## atlas all depend on that number), while this is only how tall the picture is.
## Conflating them is what made the whole map read as miniature.
##
## **This used to be the longest side of the texture**, which put every building
## in a box regardless of what was in it: the Kenney house sprites sit on a
## 128x192 canvas with 141px of house in it, so a 104 cap drew a 76px house,
## while the crypt (whose art fills its canvas) got the full 104. Reading the
## number as a content height instead makes it mean one thing -- how tall the
## structure stands -- and lets width follow the art. See
## `Anchoring.scale_for_content_height`.
const SPRITE_MAX_SIDE: float = 104.0

func _setup_sprite() -> void:
	if sprite_path == "" or not ResourceLoader.exists(sprite_path):
		return
	var tex := load(sprite_path)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	# Every building is 1x1 on the grid for the prototype (see CLAUDE.md "Next
	# milestones" re: multi-cell footprints), but the source art wasn't
	# authored at a uniform size -- the commissioned pieces are 128px square and
	# the Kenney fantasy House/Tower/Castle sprites reused for the other types
	# are 2-7 cells wide/tall at native scale.
	#
	# **Scaled so the structure stands SPRITE_MAX_SIDE tall**, up or down. This
	# used to fit the texture's longest *side* into the cap, which measured the
	# canvas rather than the building -- a Kenney house on a 128x192 sheet came
	# out 28px shorter than the commissioned Throne even though both were asked
	# for the same number. Width now follows the art's own proportions, which is
	# how a wide low Bone Pile ends up wide and low.
	sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, SPRITE_MAX_SIDE)
	# **Bottom-centre of the cell, not top-left.** `centered = false` pinned the
	# texture's top-left to the cell origin, so anything drawn larger than one
	# tile grew down and right, across the neighbours. Buildings grow *upward*
	# out of their footprint, which is also what makes them read as standing on
	# the grid rather than floating over it.
	sprite.modulate = sprite_tint
	add_child(sprite)
	Anchoring.cell_base(sprite, float(SettlementGrid.CELL_SIZE))

func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		GameState.add_resource(resource_kind, resource_per_tick)

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

## Human-readable category, for the panel subtitle. Not derived from the raw
## category string because "housing_intake" and "housing_home" are internal
## routing names that mean nothing to a player.
const CATEGORY_LABEL := {
	"main": "Your seat of power",
	"resource": "Production",
	"functional": "Workshop building",
	"housing_intake": "Recruit intake",
	"housing_home": "Home",
	"housing": "Housing",
}

func get_inspect_data() -> Dictionary:
	var rows: Array = []

	if is_main_building and max_hp > 0:
		# The Crusade targets this and losing it is the fail state, so its
		# condition is the first thing worth reading.
		var hp_colour := Color(0.95, 0.6, 0.5) if hp < max_hp else Color(0.75, 0.9, 0.75)
		rows.append({"label": "Condition", "value": "%d / %d hp" % [hp, max_hp], "color": hp_colour})

	if resource_kind != "":
		rows.append({"label": "Produces", "value": "+%d %s every %ss" % [
			resource_per_tick, resource_kind, String.num(tick_interval, 0)]})

	if power_value > 0:
		rows.append({"label": "Power", "value": "+%d" % power_value})

	rows.append_array(_intake_rows())
	rows.append_array(_home_rows())

	if housing_species != "":
		rows.append({"label": "Houses", "value": housing_species})

	return {
		"title": display_name,
		"subtitle": CATEGORY_LABEL.get(category, category.capitalize()),
		"sprite": sprite_path,
		"description": description,
		"details": rows,
	}

## Barracks occupancy. Asks the SettlementGrid it is parented to rather than
## recounting the roster here, so "who counts as a resident" stays defined in
## exactly one place (it changed once already, when fund-a-house landed).
func _intake_rows() -> Array:
	if category != "housing_intake":
		return []
	var grid := get_parent()
	if grid == null or not grid.has_method("barracks_residents"):
		return [{"label": "Capacity", "value": "%d" % capacity}]
	var used: int = grid.barracks_residents()
	var row := {"label": "Residents", "value": "%d / %d" % [used, capacity]}
	if used >= capacity:
		row["color"] = Color(0.95, 0.70, 0.40)
		return [row, {"label": "", "value": "Full. New recruits can only be turned away until someone is given a house.", "muted": true}]
	return [row]

## A funded recruit house: who lives here, and the housing_style flavor that
## explains why they built it *there* -- the placement is the recruit's choice,
## not the player's, so the panel is where that choice gets explained.
func _home_rows() -> Array:
	if category != "housing_home":
		return []
	var race: Dictionary = RaceCatalog.get_race(house_race_id)
	var species: String = race.get("display_name", house_race_id)
	var rows: Array = []
	if house_owner_name != "":
		rows.append({"label": "Resident", "value": "%s — %s" % [house_owner_name, species]})
	else:
		rows.append({"label": "Resident", "value": species})
	var note: String = race.get("housing_note", "")
	if note != "":
		rows.append({"label": "Chose this spot", "value": note, "muted": true})
	return rows

## Builds a Building from a data/buildings.json row (fetched via
## BuildingCatalog.get_building(id)). This replaces the old one-factory-
## function-per-building approach now that the catalog is data-driven.
static func make_from_data(id: String, data: Dictionary) -> Building:
	var b := Building.new()
	b.building_id = id
	b.display_name = data.get("display_name", id)
	b.category = data.get("category", "")
	b.resource_kind = data.get("resource_kind", "")
	b.resource_per_tick = data.get("resource_per_tick", 0)
	b.tick_interval = data.get("tick_interval", 5.0)
	b.power_value = data.get("power_value", 0)
	b.sprite_path = data.get("sprite_path", "")
	b.description = data.get("description", "")
	b.housing_species = data.get("housing_species", "")
	b.capacity = data.get("capacity", 0)
	b.max_hp = data.get("max_hp", 0)
	b.is_main_building = b.category == "main"
	return b
