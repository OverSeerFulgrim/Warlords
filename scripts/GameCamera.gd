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
##
## ## The right button means two things, decided in one place
##
## A right **drag** pans. A right **tap** walks the Necromancer (R1 playtest
## request #2). Both gestures start with the same press, so the split has to be
## made by something that sees the whole gesture -- press, motion, release --
## and this node is the only thing that already did. It therefore owns the
## decision outright and announces the tap as `right_tapped`; **nothing else in
## the project may test `MOUSE_BUTTON_RIGHT`**, or one gesture will fire both
## meanings.
##
## The thresholds are deliberately loose: a "tap" is under TAP_MAX_DRAG_PX of
## travel and under TAP_MAX_SECONDS held. A pan that happens to be tiny is
## indistinguishable from a tap and is treated as one, which is the right way
## round -- the cost is a short walk the player can cancel with any key, where
## the reverse would be a click that silently does nothing.

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

## Emitted on a right-click *tap* -- press and release in nearly the same place,
## quickly -- with the world position under the cursor. Main decides what it
## means; see the class header for why this node is the one that decides a tap
## happened at all.
signal right_tapped(world_pos: Vector2)

## Past this much travel, or this long held, the gesture is a pan and no tap is
## emitted on release. Both have to be exceeded to *stay* a tap.
const TAP_MAX_DRAG_PX: float = 6.0
const TAP_MAX_SECONDS: float = 0.25

var _dragging: bool = false
## Gesture bookkeeping for the tap/drag split. `_drag_px` accumulates absolute
## motion rather than start-to-end distance, so a wiggle that returns to where
## it started is still a pan.
var _press_time: float = 0.0
var _drag_px: float = 0.0

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
			# Right-drag rather than left-drag: left-click is spoken for by
			# build-menu placement (Main.gd enters "pending placement" mode
			# and listens for a left-click on the grid), so panning moved to
			# the button that's actually free. Matches the AoE/Majesty
			# convention of left = select/act, right = pan anyway.
			if event.pressed:
				_dragging = true
				_press_time = _now()
				_drag_px = 0.0
			else:
				_dragging = false
				if _was_a_tap():
					right_tapped.emit(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		# Accumulated first: a gesture is a pan the moment it moves far enough,
		# even if the player then drags back to where they started.
		_drag_px += event.relative.length()
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

## Whether the right-button gesture that just ended was a tap rather than a pan.
##
## A tiny pan does move the camera by those few pixels before this decides it
## was a tap. That is accepted: at any usable zoom, six pixels of camera drift is
## invisible, and the alternative -- holding the pan until the gesture resolves
## -- makes every real pan start with a lurch.
func _was_a_tap() -> bool:
	return _drag_px <= TAP_MAX_DRAG_PX and (_now() - _press_time) <= TAP_MAX_SECONDS

## Wall-clock, not game time. Gesture timing is a property of the player's hand
## and must not scale with `Engine.time_scale` -- at the debug 60x this is the
## one clock in the project that should keep ticking at 1x. (The CLAUDE.md rule
## against `Time.get_ticks_msec()` is about *gameplay* timers, which this is
## explicitly not.)
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

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
