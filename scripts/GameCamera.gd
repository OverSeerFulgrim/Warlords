extends Camera2D
class_name GameCamera
## Simple pan (right-click drag, or WASD/arrows) + zoom (scroll wheel) camera
## controller for the settlement view. Deliberately minimal -- no inertia, no
## edge-scrolling, no smoothing curves -- matches the "keep it simple, AoE/
## Majesty-ish" scope call rather than a full RimWorld-style camera rig.

@export var zoom_min: float = 0.35
@export var zoom_max: float = 1.4
@export var zoom_step: float = 0.1
@export var pan_speed: float = 420.0

var _dragging: bool = false

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

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if move != Vector2.ZERO:
		position += move.normalized() * pan_speed * delta * zoom.x

func _apply_zoom(delta: float) -> void:
	var z: float = clamp(zoom.x + delta, zoom_min, zoom_max)
	zoom = Vector2(z, z)
