extends Node2D
class_name FogOfWar
## Three-state fog over the world map: unexplored, remembered, visible.
##
## ## One node, one small texture
##
## 20,736 cells, and **no node and no draw call per cell.** The fog state is a
## 144x144 `Image` -- literally one pixel per cell -- uploaded to an
## `ImageTexture` and stretched over the map in a single `draw_texture_rect`.
## Updating a move costs a few hundred pixel writes and one 82KB upload, and
## only happens when the villain crosses a cell boundary. A `_draw` loop over
## every cell, or (worse) a ColorRect per cell, is the trap this stage is full
## of; this is the way around it.
##
## Filtering is **linear** on purpose: the texture is an alpha mask, so
## interpolation gives a soft one-cell falloff at the fog edge instead of a
## staircase. The terrain layer underneath is nearest-filtered for the opposite
## reason -- there, interpolation would sample across an atlas seam.
##
## ## Where it sits in the layering
##
## A child of the settlement layer with a high `z_index`, so it covers terrain,
## buildings and units -- and, being an ordinary Node2D, it is still underneath
## the HUD, which lives in its own `CanvasLayer`. That is the same lesson as
## DayNightCycle's `CanvasModulate`, which darkens the settlement and
## deliberately leaves the HUD legible. **Do not move this into `hud_root`.**
##
## Units in fog are painted over rather than each unit testing the fog itself:
## unexplored ground hides them completely, remembered ground leaves a smudge.
## The interaction half of "no live contents" is one guard in `Main._inspect_at`,
## which refuses to pick anything in a cell that isn't currently visible.

enum State { UNEXPLORED, REMEMBERED, VISIBLE }

## How far the Necromancer sees. **Tunable.** WORLD_MAP_PLAN §12 puts *scouting*
## reveal at 8-12 cells, but that is the Raven's number (rework §6) and the
## Raven is R2; a man on foot at night sees less than a bird in daylight.
const REVEAL_RADIUS_CELLS: float = 7.0

## Remembered ground. Dark enough that a wolf standing in it is a shape rather
## than a readable token, light enough that terrain still tells you where you
## have been.
const COLOR_UNEXPLORED := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_REMEMBERED := Color(0.02, 0.02, 0.05, 0.62)
const COLOR_VISIBLE := Color(0.0, 0.0, 0.0, 0.0)

var world: WorldMap = null

var _state: PackedByteArray = PackedByteArray()
## Cells that can never fall back to remembered -- the lair band. See
## reveal_permanently().
var _permanent: PackedByteArray = PackedByteArray()
## Indices currently lit by the villain, so the next move knows what to dim.
var _lit: PackedInt32Array = PackedInt32Array()
var _last_cell: Vector2i = Vector2i(-9999, -9999)

var _image: Image
var _texture: ImageTexture

func setup(p_world: WorldMap) -> void:
	world = p_world
	z_index = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var count: int = world.width * world.height
	_state.resize(count)
	_permanent.resize(count)
	_state.fill(State.UNEXPLORED)
	_permanent.fill(0)
	_image = Image.create_empty(world.width, world.height, false, Image.FORMAT_RGBA8)
	_image.fill(COLOR_UNEXPLORED)
	_texture = ImageTexture.create_from_image(_image)
	queue_redraw()

func _draw() -> void:
	if _texture == null or world == null:
		return
	draw_texture_rect(_texture, world.bounds_px(), false)

# ---------------- Reveal -----------------------------------------------------

## **The lair band never dims.** Fiction: it is his own domain, and he knows
## where his own skeletons are. Mechanics: the settlement layer is a management
## screen, and having the workforce vanish into a memory haze the moment he
## steps out of the valley would break the half of the game that was already
## working. Everything beyond the band obeys the ordinary three states.
func reveal_permanently(cells: Rect2i) -> void:
	for y in range(cells.position.y, cells.position.y + cells.size.y):
		for x in range(cells.position.x, cells.position.x + cells.size.x):
			if not world.in_bounds(Vector2i(x, y)):
				continue
			var i: int = y * world.width + x
			_permanent[i] = 1
			_set_state(i, State.VISIBLE)
	_texture.update(_image)
	queue_redraw()

## Call every frame with the villain's position; it early-outs unless he has
## crossed into a new cell, which is what keeps this off the frame budget.
func update_for(point: Vector2) -> void:
	if world == null:
		return
	var cell: Vector2i = world.cell_at(point)
	if cell == _last_cell:
		return
	_last_cell = cell
	_relight(cell)

func _relight(centre: Vector2i) -> void:
	# Everything the last position lit falls back to remembered first...
	for i in _lit:
		if _permanent[i] == 0:
			_set_state(i, State.REMEMBERED)
	_lit.resize(0)
	# ...then the new disc lights up. Circular rather than square so the
	# revealed shape reads as sight, not as a scanned rectangle.
	var r: int = int(ceil(REVEAL_RADIUS_CELLS))
	var r_sq: float = REVEAL_RADIUS_CELLS * REVEAL_RADIUS_CELLS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dy * dy) > r_sq:
				continue
			var c := centre + Vector2i(dx, dy)
			if not world.in_bounds(c):
				continue
			var i: int = c.y * world.width + c.x
			_lit.append(i)
			_set_state(i, State.VISIBLE)
	_texture.update(_image)
	queue_redraw()

func _set_state(index: int, state: int) -> void:
	if _state[index] == state:
		return
	_state[index] = state
	var colour: Color = COLOR_VISIBLE
	if state == State.UNEXPLORED:
		colour = COLOR_UNEXPLORED
	elif state == State.REMEMBERED:
		colour = COLOR_REMEMBERED
	_image.set_pixel(index % world.width, index / world.width, colour)

# ---------------- Queries ----------------------------------------------------

func state_at(point: Vector2) -> int:
	if world == null:
		return State.VISIBLE
	var cell: Vector2i = world.cell_at(point)
	if not world.in_bounds(cell):
		return State.UNEXPLORED
	return _state[cell.y * world.width + cell.x]

## The interaction half of "remembered ground shows no live contents": Main
## refuses to inspect anything standing in a cell that isn't lit right now.
func is_visible_at(point: Vector2) -> bool:
	return state_at(point) == State.VISIBLE

func explored_count() -> int:
	var n: int = 0
	for s in _state:
		if s != State.UNEXPLORED:
			n += 1
	return n
