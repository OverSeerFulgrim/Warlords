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
## only happens when a light source crosses a cell boundary. A `_draw` loop over
## every cell, or (worse) a ColorRect per cell, is the trap this stage is full
## of; this is the way around it.
##
## ## Many sources, one lit set
##
## The villain is no longer the only thing that lights ground: **every friendly
## unit carries a smaller disc** (playtest request #3, designer decision
## 2026-08-27). `update_for()` therefore takes a *list* of sources and rebuilds
## the whole lit set from it, rather than moving one disc around.
##
## Rebuilding wholesale rather than diffing is deliberate. Overlapping discs
## make "which cell does this unit still own" a reference-counting problem, and
## a refcount that leaks by one leaves a cell permanently lit -- the exact bug
## the three-state fog exists to prevent. Rebuilding cannot leak: what is lit is
## a pure function of where the sources are this frame.
##
## What keeps that off the frame budget is the **early-out**: the rebuild only
## runs when some source has crossed a cell boundary. With 33 bound undead
## standing still that is one PackedInt32Array compare per frame and nothing
## else. See `update_for()`.
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

## Fires when any cell's state changed. The minimap draws this same texture on
## top of its terrain image, so it redraws off this rather than polling -- and
## it only fires when a light source crosses a cell boundary. The minimap's
## friendly dots ride on the same signal, which is exactly right: a dot at one
## pixel per cell only needs redrawing when its unit changes cell.
signal changed

enum State { UNEXPLORED, REMEMBERED, VISIBLE }

## How far the Necromancer sees. **Tunable.** WORLD_MAP_PLAN §12 puts *scouting*
## reveal at 8-12 cells, but that is the Raven's number (rework §6) and the
## Raven is R2; a man on foot at night sees less than a bird in daylight.
const REVEAL_RADIUS_CELLS: float = 7.0

## How far a friendly unit lights the ground it is standing on -- workers,
## followers and bound undead alike. **Tunable.**
##
## Deliberately less than half the villain's 7: they are labourers with their
## eyes on the job, not a man scouting a valley, and a radius that read as
## "scouting" would make walking out there yourself the slower way to see
## anything. It is lit-while-present exactly like his: when the unit leaves,
## the cell drops back to REMEMBERED. Nothing here becomes permanent -- that is
## `reveal_permanently()`, which is the lair band and only the lair band.
const UNIT_REVEAL_RADIUS_CELLS: float = 3.0

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
## Indices currently lit by *any* source, so the next rebuild knows what to dim.
## May hold the same index twice where two discs overlap; harmless, because
## dimming is idempotent and `_set_state` early-outs on an unchanged cell.
var _lit: PackedInt32Array = PackedInt32Array()

## The cell each source occupied at the last rebuild, flattened to x,y pairs.
## Compared wholesale to decide whether anything moved -- see `update_for()`.
var _last_cells: PackedInt32Array = PackedInt32Array()

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
	changed.emit()

## Call every frame with every light source: an Array of `[position, radius]`
## pairs, villain first by convention (nothing depends on the order).
##
## **It early-outs unless some source has crossed into a new cell.** That is the
## whole performance story: with 33 bound undead standing around the Throne this
## is one `PackedInt32Array` compare per frame and no pixel writes at all, and a
## single worker stepping over a boundary costs one rebuild.
##
## The comparison key holds each source's cell as an x,y pair rather than a
## flattened index, so an out-of-bounds source (a unit walking the rim) cannot
## alias onto a different cell's index and freeze the fog on a false match.
func update_for(sources: Array) -> void:
	if world == null:
		return
	var cells := PackedInt32Array()
	cells.resize(sources.size() * 2)
	for i in range(sources.size()):
		var c: Vector2i = world.cell_at(sources[i][0])
		cells[i * 2] = c.x
		cells[i * 2 + 1] = c.y
	# Length changes too, so a unit dying or being recruited relights on its own.
	if cells == _last_cells:
		return
	_last_cells = cells
	_relight(sources)

func _relight(sources: Array) -> void:
	# Everything the last rebuild lit falls back to remembered first...
	for i in _lit:
		if _permanent[i] == 0:
			_set_state(i, State.REMEMBERED)
	_lit.resize(0)
	# ...then every source lights its own disc.
	for s in sources:
		_light_disc(world.cell_at(s[0]), float(s[1]))
	_texture.update(_image)
	queue_redraw()
	changed.emit()

## One source's disc. Circular rather than square so the revealed shape reads as
## sight, not as a scanned rectangle.
func _light_disc(centre: Vector2i, radius: float) -> void:
	var r: int = int(ceil(radius))
	var r_sq: float = radius * radius
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

## The dimming mask itself, so the minimap can draw exactly the same fog over
## its own terrain image instead of maintaining a second copy of the state.
func fog_texture() -> Texture2D:
	return _texture

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
