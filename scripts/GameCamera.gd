extends Camera2D
class_name GameCamera
## Simple pan (right-click drag, or the arrow keys) + zoom (scroll wheel) camera
## controller for the settlement view. Deliberately minimal -- no inertia, no
## edge-scrolling, no smoothing curves -- matches the "keep it simple, AoE/
## Majesty-ish" scope call rather than a full RimWorld-style camera rig.
##
## **WASD used to pan here too, and deliberately no longer does.** Those keys
## now drive the Necromancer (see VillainController), and the two would have
## fought over every keystroke. The split is: **WASD moves the man, arrows move
## the camera.** With follow mode on they read almost identically anyway --
## moving him moves the view -- so the arrow keys are really "look away from him
## for a moment", and like a right-drag they drop follow.

## Zoom-out floor. Was 0.35, which framed a settlement nicely and showed about
## 60 cells of a 144-cell world -- less than half of it, with no way to see
## where you were going. At 0.12 a 1400px window covers ~180 cells, so the whole
## region fits with margin and the player can actually plan a route.
@export var zoom_min: float = 0.12
@export var zoom_max: float = 1.4
@export var zoom_step: float = 0.1
## Multiplied by `zoom.x`, so panning covers the same *screen* distance per
## second at every zoom level -- which means zoomed out you cross the world at a
## useful rate rather than crawling.
@export var pan_speed: float = 420.0

## The world rectangle the view is kept inside, in engine space. Set by Main
## from WorldMap.bounds_px(). Zero-size means unclamped (the settlement-only
## behaviour this camera had before the world existed).
var world_bounds: Rect2 = Rect2()

## Screen-space pixels along the top and bottom that the HUD covers. The map
## is only actually visible *between* them, so centring something on the raw
## window centre puts it low behind the command bar. Set by Main from the real
## panel heights -- see Main._sync_camera_insets().
var ui_top_inset: float = 0.0
var ui_bottom_inset: float = 0.0

var _dragging: bool = false

## True once the player has panned or zoomed. The initial framing re-applies
## itself on window resize, but only while this is false -- once you've moved
## the camera yourself, a resize must not yank the view back to the Throne.
var player_has_moved_camera: bool = false

## Bumped once per *manual pan* -- a right-drag or an arrow key. Deliberately
## separate from `player_has_moved_camera`, which zooming also sets: dropping
## Necromancer-follow is what panning means, and zooming in on the man you are
## following must not stop following him. VillainController watches this for a
## change rather than reading a boolean, so re-engaging follow doesn't have to
## reach in and clear someone else's flag.
var manual_pan_ticks: int = 0

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Scroll up = zoom in (bigger), scroll down = zoom out (smaller) --
		# matches how `zoom` empirically renders in this project's viewport
		# setup, verified by live testing rather than assumed from docs.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-drag rather than left-drag: left-click is now spoken for
			# by build-menu placement (Main.gd enters "pending placement"
			# mode and listens for a left-click on the grid), so panning
			# moved to the button that's actually free. Matches the AoE/
			# Majesty convention of left = select/act, right = pan anyway.
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative * zoom.x
		_clamp_to_world()
		_note_manual_pan()

## Arrow keys only -- WASD belongs to the Necromancer now (see the class header).
func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if move != Vector2.ZERO:
		position += move.normalized() * pan_speed * delta * zoom.x
		_clamp_to_world()
		_note_manual_pan()

## Pan, specifically -- see manual_pan_ticks for why zoom is not this.
func _note_manual_pan() -> void:
	player_has_moved_camera = true
	manual_pan_ticks += 1

func _apply_zoom(delta: float) -> void:
	var z: float = clamp(zoom.x + delta, zoom_min, zoom_max)
	zoom = Vector2(z, z)
	# Zooming out near an edge can pull the void into view, so the clamp has to
	# re-run afterwards rather than only when panning.
	_clamp_to_world()
	player_has_moved_camera = true

## Keeps the viewport inside `world_bounds`. Done in code rather than with
## Camera2D's built-in `limit_*` properties because those clamp what is *drawn*
## while leaving `position` free to wander off, which turns a drag into a dead
## zone: you keep dragging and nothing moves, then it lurches when you come back.
##
## An axis where the world is smaller than the view is centred instead of
## clamped -- otherwise the map would be pinned to one edge with all the slack
## on the other.
func _clamp_to_world() -> void:
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	var half: Vector2 = get_viewport_rect().size * 0.5 / maxf(0.01, zoom.x)
	var lo: Vector2 = world_bounds.position + half
	var hi: Vector2 = world_bounds.position + world_bounds.size - half
	position.x = (world_bounds.position.x + world_bounds.size.x * 0.5) if lo.x > hi.x \
		else clampf(position.x, lo.x, hi.x)
	position.y = (world_bounds.position.y + world_bounds.size.y * 0.5) if lo.y > hi.y \
		else clampf(position.y, lo.y, hi.y)

## Frames `world_pos` in the middle of the *visible* map area -- the band
## between the top resource bar and the bottom command bar -- rather than the
## middle of the window.
##
## A Camera2D draws its own `position` at the raw window centre, so centring on
## the visible band means deliberately offsetting away from that:
##
##     screen_y = window_h/2 + (world_y - camera_y) * zoom
##
## Solving for the camera position that puts `world_pos` at the visible band's
## centre gives the subtraction below. Dividing by zoom converts the
## screen-space inset into world units, so the framing survives zooming.
func center_on(world_pos: Vector2) -> void:
	var view: Vector2 = get_viewport_rect().size
	var visible_centre_y: float = (ui_top_inset + (view.y - ui_bottom_inset)) * 0.5
	var offset_px: float = visible_centre_y - view.y * 0.5
	position = Vector2(world_pos.x, world_pos.y - offset_px / maxf(0.01, zoom.y))
	# Framing loses to the world edge: following the Necromancer into a corner
	# must not show the void behind the map. He drifts off the exact centre
	# there, which is correct -- there is nothing more to pan to.
	_clamp_to_world()
