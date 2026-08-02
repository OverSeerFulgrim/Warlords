extends Node2D
class_name SettlementGrid
## Minimal grid placement system. Deliberately not using Godot's TileMap for
## the prototype -- a plain Dictionary of Vector2i -> Building is easier to
## reason about and enough for validating the core loop.

const CELL_SIZE: int = 64
const GRID_WIDTH: int = 10
const GRID_HEIGHT: int = 8

var cells: Dictionary = {}  # Vector2i -> Building

func can_place(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= GRID_WIDTH or cell.y >= GRID_HEIGHT:
		return false
	return not cells.has(cell)

func place_building(building: Building, cell: Vector2i) -> bool:
	if not can_place(cell):
		return false
	cells[cell] = building
	building.cell = cell
	building.position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
	add_child(building)
	EventBus.building_placed.emit(building, cell)
	EventBus.building_count_changed.emit(cells.size())
	GameState.recompute_power(_total_building_power())
	return true

func remove_building(cell: Vector2i) -> bool:
	if not cells.has(cell):
		return false
	var building: Building = cells[cell]
	if building.is_main_building:
		return false  # the player's home can't be demolished
	cells.erase(cell)
	building.queue_free()
	EventBus.building_removed.emit(building, cell)
	EventBus.building_count_changed.emit(cells.size())
	GameState.recompute_power(_total_building_power())
	return true

## Sum of every placed building's individual power_value -- what
## GameState.recompute_power actually consumes now, instead of a flat
## per-building constant that made buildings.json's power_value dead data.
func _total_building_power() -> int:
	var total := 0
	for b in cells.values():
		total += b.power_value
	return total

func cell_from_world(world_pos: Vector2) -> Vector2i:
	# floori(), not int() -- int() truncates toward zero, so a click a few
	# pixels above/left of the grid origin (a small negative world coordinate)
	# would truncate to 0 and silently resolve to a valid on-grid cell instead
	# of correctly landing outside it. floori() rounds toward negative
	# infinity, which is what "which cell is this point in" actually means.
	return Vector2i(floori(world_pos.x / CELL_SIZE), floori(world_pos.y / CELL_SIZE))

func building_count() -> int:
	return cells.size()

## True if a building with this building_id exists anywhere in the
## settlement. Used for the Workshop tech-gate and for Blacksmith/Barracks
## action-button checks.
func has_building(building_id: String) -> bool:
	for b in cells.values():
		if b.building_id == building_id:
			return true
	return false

## True if a housing building for this Follower species exists -- the hard
## gate that recruitment (EventSystem) checks before adding a follower.
func has_housing_for(species: String) -> bool:
	for b in cells.values():
		if b.housing_species == species:
			return true
	return false

## The player's home building (category == "main"), or null if somehow not
## placed yet. ThreatSystem's Crusade resolution targets this.
func get_main_building() -> Building:
	for b in cells.values():
		if b.is_main_building:
			return b
	return null

# ---------------- Barracks intake (FOUNDATION_SPEC section 9) ----------------

## The Barracks, or null if not built yet. There can only ever be one -- the
## catalog entry is `"unique": true`, so BuildingCatalog.buildable_ids() drops
## it from the build menu once placed.
func get_barracks() -> Building:
	for b in cells.values():
		if b.category == "housing_intake":
			return b
	return null

func has_barracks() -> bool:
	return get_barracks() != null

## Total resident slots. 0 with no Barracks, which is what gates recruitment
## entirely -- no Barracks, nowhere to put anyone, no recruit events.
func barracks_capacity() -> int:
	var b := get_barracks()
	return b.capacity if b else 0

## Residents are simply every follower on the roster. That's exact *for now*
## because fund-a-house isn't built yet, so nobody has ever moved out of the
## Barracks -- once it is (GAME_OUTLINE gap #4), this needs to count only
## followers still resident rather than the whole roster.
func barracks_residents() -> int:
	return GameState.followers.size()

func barracks_free_slots() -> int:
	return max(0, barracks_capacity() - barracks_residents())
