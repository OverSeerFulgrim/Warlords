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

## Housing: which Follower.species this building's presence unlocks
## recruitment for. "" for buildings that aren't housing.
@export var housing_species: String = ""

## Intake capacity, for category == "housing_intake" (the Barracks, and only
## the Barracks). 0 for everything else. See SettlementGrid.barracks_capacity().
@export var capacity: int = 0

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

func _setup_sprite() -> void:
	if sprite_path == "" or not ResourceLoader.exists(sprite_path):
		return
	var tex := load(sprite_path)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false  # align to the same top-left grid convention as `position`
	# Every building is 1x1 on the grid for the prototype (see CLAUDE.md "Next
	# milestones" re: multi-cell footprints), but the source art wasn't
	# authored at a uniform size -- the Kenney fantasy House/Tower/Castle
	# sprites reused for the new building types are 2-7 cells wide/tall at
	# native scale. Scale down (never up) so nothing sprawls past its own
	# tile, matching the same target_size/src.x pattern FollowerToken already
	# uses for portraits. Reads SettlementGrid.CELL_SIZE rather than
	# redefining the constant here, so there's one source of truth for it.
	var src: Vector2 = tex.get_size()
	var largest_side: float = max(src.x, src.y)
	if largest_side > SettlementGrid.CELL_SIZE:
		var scale_factor: float = SettlementGrid.CELL_SIZE / largest_side
		sprite.scale = Vector2.ONE * scale_factor
	add_child(sprite)

func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		GameState.add_resource(resource_kind, resource_per_tick)

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
	b.housing_species = data.get("housing_species", "")
	b.capacity = data.get("capacity", 0)
	b.max_hp = data.get("max_hp", 0)
	b.is_main_building = b.category == "main"
	return b
