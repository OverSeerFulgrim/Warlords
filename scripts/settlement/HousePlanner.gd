class_name HousePlanner
extends RefCounted
## Picks the grid cell a recruit builds their own house on, by their race's
## `housing_style` from races.json / RACES.md.
##
## The design point (GAME_OUTLINE pillar 4, "the town grows organically") is
## that **the recruit chooses, not the player** -- you pay for the house, they
## decide where it goes, and the settlement's final shape emerges from who you
## recruited. A goblin-heavy town knots together; an ogre-minotaur town
## sprawls.
##
## **Nothing here may ever block.** Every style degrades: preferred rule ->
## communal -> any free cell at all. RACES.md says this explicitly of Gnolls
## ("clustering is preference-not-guarantee"), and the same has to hold for
## every style, because a full or awkwardly-shaped grid must not leave the
## player having paid 6 wood / 4 stone for nothing.

## Chebyshev gap a "spaced" race insists on. RACES.md says "e.g. 2+ empty
## cells", so a house needs no neighbour within 2 cells -- distance >= 3.
const SPACED_MIN_DISTANCE: int = 3

## "Near" for clustered/communal: within this Chebyshev distance of the thing
## they want to be near.
const NEAR_DISTANCE: int = 2

## Returns the chosen cell, or Vector2i(-1, -1) if the grid is genuinely full.
static func find_cell(settlement, race_id: String, resource_field) -> Vector2i:
	var free_cells: Array = _free_cells(settlement)
	if free_cells.is_empty():
		return Vector2i(-1, -1)

	var style: String = RaceCatalog.get_race(race_id).get("housing_style", "communal")
	var preferred: Array = []
	match style:
		"clustered":
			preferred = _clustered(settlement, race_id, free_cells)
		"spaced":
			preferred = _spaced(settlement, free_cells)
		"near_feature":
			preferred = _near_feature(settlement, race_id, free_cells, resource_field)
		"edge":
			preferred = _edge(settlement, free_cells)
		_:  # "communal", "none", or anything unrecognised
			preferred = _communal(settlement, free_cells)

	if not preferred.is_empty():
		return preferred[0]
	# Preference unsatisfiable -> communal -> anywhere. Never block.
	var fallback: Array = _communal(settlement, free_cells)
	if not fallback.is_empty():
		return fallback[0]
	return free_cells[0]

# ---------------- Styles ----------------

## Adjacent to an existing house of the *same race* if there is one, else near
## the town centre. Goblin, Kobold, Gnoll, Halfling.
##
## Note Gnolls want to be away from other races too, but RACES.md settles that
## as preference-not-guarantee with no enforced minimum distance -- so it is
## deliberately not modelled as a hard constraint here.
static func _clustered(settlement, race_id: String, free_cells: Array) -> Array:
	var kin: Array = _house_cells_of_race(settlement, race_id)
	if not kin.is_empty():
		var adjacent: Array = free_cells.filter(func(c): return _min_chebyshev(c, kin) == 1)
		if not adjacent.is_empty():
			return _sorted_by_distance_to(adjacent, kin[0])
	return _communal(settlement, free_cells)

## Near any existing house, or the town centre when there are none yet.
## Orc, Hobgoblin, Human Outcast -- and the universal fallback.
static func _communal(settlement, free_cells: Array) -> Array:
	var anchors: Array = _all_house_cells(settlement)
	if anchors.is_empty():
		anchors = [_town_centre(settlement)]
	var near: Array = free_cells.filter(func(c): return _min_chebyshev(c, anchors) <= NEAR_DISTANCE)
	if near.is_empty():
		# Nothing close is free -- just take the closest thing there is.
		return _sorted_by_min_distance(free_cells, anchors)
	return _sorted_by_min_distance(near, anchors)

## At least SPACED_MIN_DISTANCE from every other house. Ogre, Troll, Minotaur,
## High Elf. Sorted by *most* isolated first -- a minotaur takes the roomiest
## spot available, not merely a legal one.
static func _spaced(settlement, free_cells: Array) -> Array:
	var houses: Array = _all_house_cells(settlement)
	if houses.is_empty():
		# First house in town: any cell qualifies, so pick one well clear of
		# the Throne so the town has room to grow around them.
		return _sorted_by_distance_to(free_cells, _town_centre(settlement), true)
	var ok: Array = free_cells.filter(func(c): return _min_chebyshev(c, houses) >= SPACED_MIN_DISTANCE)
	if ok.is_empty():
		return []
	ok.sort_custom(func(a, b): return _min_chebyshev(a, houses) > _min_chebyshev(b, houses))
	return ok

## Adjacent to the map feature the race cares about: stone for both dwarf
## varieties, the Workshop for gnomes. Falls through to communal if the
## feature doesn't exist yet (no Workshop built, say).
static func _near_feature(settlement, race_id: String, free_cells: Array, resource_field) -> Array:
	var target: Vector2 = Vector2.INF

	if race_id == "gnome":
		var workshop: Building = _building_by_id(settlement, "workshop")
		if workshop:
			target = _cell_to_world(workshop.cell)
	else:
		# Gray Dwarf / Mountain Dwarf: the Stone Deposit.
		if resource_field:
			for n in resource_field.nodes:
				if n.node_type == "stone_deposit":
					target = n.position
					break

	if target == Vector2.INF:
		return []
	return _sorted_by_world_distance(free_cells, target)

## The settlement's rim, furthest from the centre. Dark Elf -- secluded.
static func _edge(settlement, free_cells: Array) -> Array:
	var rim: Array = free_cells.filter(func(c):
		return c.x == 0 or c.y == 0 \
			or c.x == SettlementGrid.GRID_WIDTH - 1 or c.y == SettlementGrid.GRID_HEIGHT - 1)
	if rim.is_empty():
		return []
	return _sorted_by_distance_to(rim, _town_centre(settlement), true)

# ---------------- Helpers ----------------

static func _free_cells(settlement) -> Array:
	var out: Array = []
	for y in range(SettlementGrid.GRID_HEIGHT):
		for x in range(SettlementGrid.GRID_WIDTH):
			var c := Vector2i(x, y)
			if settlement.can_place(c):
				out.append(c)
	return out

static func _all_house_cells(settlement) -> Array:
	var out: Array = []
	for b in settlement.cells.values():
		if b.category == "housing_home":
			out.append(b.cell)
	return out

static func _house_cells_of_race(settlement, race_id: String) -> Array:
	var out: Array = []
	for b in settlement.cells.values():
		if b.category == "housing_home" and b.house_race_id == race_id:
			out.append(b.cell)
	return out

static func _building_by_id(settlement, id: String) -> Building:
	for b in settlement.cells.values():
		if b.building_id == id:
			return b
	return null

## The Throne is the town's anchor. It sits at (0,0) -- a corner rather than a
## literal middle -- so "town centre" here means "where the settlement started
## and grew out from", which is the sense the housing styles actually want.
static func _town_centre(settlement) -> Vector2i:
	var main: Building = settlement.get_main_building()
	return main.cell if main else Vector2i.ZERO

static func _cell_to_world(cell: Vector2i) -> Vector2:
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	return Vector2(cell.x * SettlementGrid.CELL_SIZE + half, cell.y * SettlementGrid.CELL_SIZE + half)

## Chebyshev (king-move) distance -- diagonals count as 1, which is the right
## metric for "adjacent" and "2 cells clear" on a square grid.
static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func _min_chebyshev(c: Vector2i, others: Array) -> int:
	var best: int = 9999
	for o in others:
		best = mini(best, _chebyshev(c, o))
	return best

static func _sorted_by_distance_to(cells: Array, anchor: Vector2i, descending: bool = false) -> Array:
	var out: Array = cells.duplicate()
	if descending:
		out.sort_custom(func(a, b): return _chebyshev(a, anchor) > _chebyshev(b, anchor))
	else:
		out.sort_custom(func(a, b): return _chebyshev(a, anchor) < _chebyshev(b, anchor))
	return out

static func _sorted_by_min_distance(cells: Array, anchors: Array) -> Array:
	var out: Array = cells.duplicate()
	out.sort_custom(func(a, b): return _min_chebyshev(a, anchors) < _min_chebyshev(b, anchors))
	return out

static func _sorted_by_world_distance(cells: Array, target: Vector2) -> Array:
	var out: Array = cells.duplicate()
	out.sort_custom(func(a, b):
		return _cell_to_world(a).distance_squared_to(target) < _cell_to_world(b).distance_squared_to(target))
	return out
