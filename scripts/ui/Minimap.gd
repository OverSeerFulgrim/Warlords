extends Control
class_name Minimap
## The whole region at one pixel per cell, so 9216px of world is legible in a
## 144px box.
##
## ## Why it costs nothing
##
## Two textures and four shapes. The terrain image is built **once** (one pixel
## per cell, coloured by `WorldMap.minimap_color_at`, which samples the actual
## tile art) and never rebuilt. The fog is **the very same `ImageTexture` the
## world fog draws** -- drawn again here over the terrain, at a different size.
## So "remembered terrain shows, unexplored does not" needs no second copy of
## the fog state and cannot drift from it.
##
## ## What it deliberately does not show
##
## **No live HOSTILE or NEUTRAL contents.** No wolf, no deer, no patrols --
## knowing where the wolf is from across the map would undo the fog.
##
## **Your own units are not intelligence about the world**, so they are drawn
## (R1 playtest request #4, designer decision 2026-08-27). Workers, followers
## and bound undead show as dim dots; together with the lair ring and the
## villain they answer "where am I, where are my people, and which way is home",
## which is orientation rather than reconnaissance. The rule the original
## wording was reaching for was never "hide everything" -- it was "the fog must
## not be readable from the HUD", and a dot on ground your own worker is
## standing in reveals nothing the world view was not already showing.
##
## A dot is drawn only where the fog says VISIBLE or REMEMBERED. Since friendly
## units light their own ground (`FogOfWar.UNIT_REVEAL_RADIUS_CELLS`) that is
## always true today -- the check is there so it stays true if that ever changes,
## rather than because it currently filters anything.
##
## ## Clicking it
##
## Left-click centres the camera there; right-click walks the Necromancer there
## (playtest requests #1 and #2). Both convert through `_from_map()`, the exact
## inverse of the `_to_map()` the markers are drawn with. The control consumes
## the click so it never reaches `Main._unhandled_input` as a world click --
## which is also why `mouse_filter` is STOP rather than the IGNORE it used to be.

## Colours chosen to survive on top of dark terrain at 3-4px.
const LAIR_COLOR := Color(0.55, 0.85, 0.55)
const VILLAIN_COLOR := Color(1.0, 0.85, 0.35)
## Friendly units. A desaturated blue-grey, picked to sit clearly apart from
## both markers above at the 2px these are drawn at: the lair is green and the
## villain is warm yellow, so a cool dim tone cannot be mistaken for either even
## when a dot is directly beside the ring. Dim on purpose -- thirty of these
## must read as "my people are over there", not out-shout the two markers that
## actually orient you.
const FRIENDLY_COLOR := Color(0.45, 0.62, 0.78, 0.85)
const FRIENDLY_DOT_RADIUS := 2.0
const BORDER_COLOR := Color(0.45, 0.45, 0.55, 0.8)
const VIEW_COLOR := Color(1.0, 1.0, 1.0, 0.25)

## Left-click: centre the camera here. Right-click: walk the Necromancer here.
## Both carry an engine-space world position; Main decides what they mean, the
## same way it arbitrates a click on the world itself.
signal camera_requested(world_pos: Vector2)
signal move_requested(world_pos: Vector2)

var world: WorldMap = null
var fog: FogOfWar = null
var villain: Necromancer = null
var camera: GameCamera = null
## Answers "which friendly units exist right now". A callable rather than a
## reference to WorkerSystem, so this stays a view with no idea what a Worker
## is -- and so a second villain's minimap would simply be handed a different
## one (ROGUELITE_REWORK section 11).
var units_source: Callable = Callable()

## **Debug only, and off unless F3 is on.** Returns engine-space points to mark
## with a flat yellow dot — the dev site overlay (`DebugSiteOverlay.gd`), which
## returns an empty Array whenever it is hidden.
##
## This is the one deliberate exception to the "no live contents" rule in this
## file's header, and it is not really an exception at all: it is unreachable in
## an exported build (the F3 handler is behind `OS.is_debug_build()`), it is off
## by default, and a tester who switched it on knows the fog is not telling them
## the truth any more. Left unset, this draws nothing and costs one `is_valid()`.
var debug_markers_source: Callable = Callable()

const DEBUG_MARKER_COLOR := Color(1.0, 0.95, 0.25, 0.9)

var _terrain_texture: ImageTexture

func setup(p_world: WorldMap, p_fog: FogOfWar, p_villain: Necromancer, p_camera: GameCamera) -> void:
	world = p_world
	fog = p_fog
	villain = p_villain
	camera = p_camera
	# Nearest: at one pixel per cell there is nothing to interpolate, and
	# smoothing would blur the coastline of the fog into the terrain.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# STOP, not IGNORE: the minimap is clickable now, and a click it handles
	# must not also fall through to Main as a click on the world behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_terrain_texture()
	if fog:
		fog.changed.connect(queue_redraw)
	queue_redraw()

func _build_terrain_texture() -> void:
	if world == null:
		return
	var img := Image.create_empty(world.width, world.height, false, Image.FORMAT_RGBA8)
	for y in range(world.height):
		for x in range(world.width):
			img.set_pixel(x, y, world.minimap_color_at(Vector2i(x, y)))
	_terrain_texture = ImageTexture.create_from_image(img)

func _draw() -> void:
	if world == null or _terrain_texture == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_terrain_texture, rect, false)
	if fog and fog.fog_texture():
		draw_texture_rect(fog.fog_texture(), rect, false)

	# Where the camera is looking. Cheap orientation cue and the only thing that
	# makes the minimap answer "which bit of this am I looking at".
	if camera:
		var view: Vector2 = camera.get_viewport_rect().size / maxf(0.01, camera.zoom.x)
		var top_left: Vector2 = camera.position - view * 0.5
		draw_rect(Rect2(_to_map(top_left), view / float(WorldMap.CELL_SIZE) * _scale()),
			VIEW_COLOR, false, 1.0)

	if world.lair_band.size.x > 0:
		var lair: Vector2 = _to_map(world.cell_centre_px(
			world.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2)))
		# A ring rather than a dot: it has to stay findable on top of the bright
		# bone-coloured ground it sits on.
		draw_circle(lair, 4.0, LAIR_COLOR, false, 1.5)
		draw_circle(lair, 1.5, LAIR_COLOR)
	# Friendly dots go *under* the villain marker: he is the one you look for,
	# and a worker standing on him must not hide him.
	_draw_friendly_units()
	_draw_debug_markers()
	if villain:
		draw_circle(_to_map(villain.position), 2.5, VILLAIN_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

## Dev site overlay dots. Empty unless F3 is on in a debug build -- see
## `debug_markers_source`. Deliberately drawn WITHOUT the fog check the friendly
## dots use: seeing sites through unexplored ground is the entire purpose, and
## it is exactly why this can never be a shipped feature.
func _draw_debug_markers() -> void:
	if not debug_markers_source.is_valid():
		return
	for point in debug_markers_source.call():
		draw_circle(_to_map(point), 1.8, DEBUG_MARKER_COLOR)

## Your own units, and only where the fog already admits they are there.
func _draw_friendly_units() -> void:
	if not units_source.is_valid():
		return
	for u in units_source.call():
		if not u.is_alive():
			continue
		# Belt and braces -- friendly units light their own ground, so this is
		# an assertion that the two systems agree rather than a live filter.
		if fog and fog.state_at(u.position) == FogOfWar.State.UNEXPLORED:
			continue
		draw_circle(_to_map(u.position), FRIENDLY_DOT_RADIUS, FRIENDLY_COLOR)

func _scale() -> Vector2:
	return size / Vector2(maxi(1, world.width), maxi(1, world.height))

## Engine-space point -> a position inside this control.
func _to_map(point: Vector2) -> Vector2:
	var cell: Vector2 = (point - world.origin_px) / float(WorldMap.CELL_SIZE)
	return cell * _scale()

## The exact inverse of `_to_map`: a position inside this control -> the
## engine-space point it stands for. Written as the algebraic inverse rather
## than re-derived, so the two cannot drift apart if `_scale()` ever changes.
func _from_map(point: Vector2) -> Vector2:
	var cell: Vector2 = point / _scale()
	return cell * float(WorldMap.CELL_SIZE) + world.origin_px

## Clicks on the minimap. `_gui_input` rather than `_unhandled_input` because
## this is a Control and the click is *for* it -- accepting the event here is
## what stops it reaching Main as a click on the world.
##
## Both buttons are handled on press. The right button does **not** go through
## GameCamera's tap/drag split: a drag across the minimap is not a camera pan,
## it is a click on a different cell, so there is no second meaning to separate
## out and nothing to wait for.
func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		camera_requested.emit(_from_map(event.position))
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		move_requested.emit(_from_map(event.position))
		accept_event()
