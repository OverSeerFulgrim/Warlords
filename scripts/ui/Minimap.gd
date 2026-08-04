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
## **No live contents.** No workers, no wolf, no deer, no patrols -- knowing
## where the wolf is from across the map would undo the fog. The only markers
## are the lair and the Necromancer himself, which are not intelligence about
## the world; they are the answer to "where am I and which way is home".

## Colours chosen to survive on top of dark terrain at 3-4px.
const LAIR_COLOR := Color(0.55, 0.85, 0.55)
const VILLAIN_COLOR := Color(1.0, 0.85, 0.35)
const BORDER_COLOR := Color(0.45, 0.45, 0.55, 0.8)
const VIEW_COLOR := Color(1.0, 1.0, 1.0, 0.25)

var world: WorldMap = null
var fog: FogOfWar = null
var villain: Necromancer = null
var camera: GameCamera = null

var _terrain_texture: ImageTexture

func setup(p_world: WorldMap, p_fog: FogOfWar, p_villain: Necromancer, p_camera: GameCamera) -> void:
	world = p_world
	fog = p_fog
	villain = p_villain
	camera = p_camera
	# Nearest: at one pixel per cell there is nothing to interpolate, and
	# smoothing would blur the coastline of the fog into the terrain.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if villain:
		draw_circle(_to_map(villain.position), 2.5, VILLAIN_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

func _scale() -> Vector2:
	return size / Vector2(maxi(1, world.width), maxi(1, world.height))

## Engine-space point -> a position inside this control.
func _to_map(point: Vector2) -> Vector2:
	var cell: Vector2 = (point - world.origin_px) / float(WorldMap.CELL_SIZE)
	return cell * _scale()
