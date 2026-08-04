extends Node
class_name VillainController
## Turns keyboard input into villain movement, and keeps the camera on him.
##
## Takes the villain it drives as a field (`villain`), set by Main -- it is
## deliberately not a singleton and does not look one up. Two villains would
## mean two controllers, which is the whole point of ROGUELITE_REWORK section
## 11's "no system may assume there is exactly one villain".
##
## ## Why the keyboard, and not click-to-move
##
## Left-click is already spoken for three times over: inspection, build
## placement, demolish, and Command Undead's rally point all read a left-click
## on the map, and `Main._unhandled_input` arbitrates between them by mode.
## Right-drag is camera pan. Adding "walk here" as a fourth meaning for a mouse
## button would mean every click first asking *which mode am I in* before it
## could ask *what did they click* -- which is exactly how an input layer rots.
## Hold-to-move on the keyboard is a separate channel entirely: it cannot
## collide with any click, it needs no mode, and it reads as direct control
## rather than as issuing an order (which matters, because ordering people
## about is the one thing this game's pillars rule out).
##
## ## WASD moves the man, arrows move the camera
##
## `GameCamera` used to pan on both WASD *and* the arrow keys. They are split
## now: **WASD drives the Necromancer, the arrow keys stay camera pan.** While
## follow mode is on the two read almost identically anyway -- moving him moves
## the view -- so the arrow keys are really "look away from him for a moment",
## and they drop follow exactly the way a right-drag does.

## Held-key movement. `Input.is_key_pressed` polling rather than
## `_unhandled_input`, because hold-to-move is a *state* ("is W down right
## now"), not an event, and rebuilding that state from key-down/key-up events
## desyncs the first time the window loses focus mid-hold.
const KEYS_UP := [KEY_W]
const KEYS_DOWN := [KEY_S]
const KEYS_LEFT := [KEY_A]
const KEYS_RIGHT := [KEY_D]

## Snaps the camera back onto him and re-engages follow. F for follow; Space was
## the other candidate and lost because it is the conventional pause key and
## this project will eventually want one.
const FOLLOW_KEY := KEY_F

# ---------------- Wiring (set by Main, same convention as the other systems) --
var villain: Necromancer = null
var camera: GameCamera = null

## Whether the camera is tracking him. Lives here rather than on `Necromancer`
## on purpose: where the camera points is a view concern, and putting it on the
## data object would be the same category error the token/data split just
## undid.
var following: bool = true

## Last seen value of `GameCamera.manual_pan_ticks`. Any change means the player
## panned by hand -- right-drag or arrow key -- and follow drops. Compared
## rather than polling `player_has_moved_camera` because that flag is also set
## by zooming, and zooming in on the man you are following should not stop
## following him.
var _last_pan_ticks: int = 0

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)

func _process(delta: float) -> void:
	if villain == null:
		return
	villain.step(_movement_input(), delta)
	_update_follow()

## Held-direction vector, unnormalised -- `Necromancer.step` normalises, so
## diagonals aren't faster.
##
## Returns zero while a text field has keyboard focus. The Economy tab's
## threshold `SpinBox`es are real text entry: without this guard, typing "30"
## into one would also walk the Necromancer across the map (and, before this
## pass, panned the camera -- the same bug, just less visible).
func _movement_input() -> Vector2:
	if _text_field_has_focus():
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if _any_pressed(KEYS_LEFT):
		dir.x -= 1.0
	if _any_pressed(KEYS_RIGHT):
		dir.x += 1.0
	if _any_pressed(KEYS_UP):
		dir.y -= 1.0
	if _any_pressed(KEYS_DOWN):
		dir.y += 1.0
	return dir

func _any_pressed(keys: Array) -> bool:
	for k in keys:
		if Input.is_key_pressed(k):
			return true
	return false

func _text_field_has_focus() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	# A SpinBox delegates focus to its internal LineEdit, so checking for the
	# LineEdit covers both.
	return focused is LineEdit

func _unhandled_input(event: InputEvent) -> void:
	# Discrete press, so this one is an event rather than a poll. It reaches
	# _unhandled_input only when no Control consumed it, which means a focused
	# SpinBox correctly eats an "f" the player was trying to type.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == FOLLOW_KEY:
		snap_to_villain()
		get_viewport().set_input_as_handled()

## Re-centres on him and re-engages follow. The escape hatch's way back in.
func snap_to_villain() -> void:
	if villain == null or camera == null:
		return
	following = true
	_last_pan_ticks = camera.manual_pan_ticks
	camera.center_on(villain.position)

func stop_following() -> void:
	following = false

func toggle_follow() -> void:
	if following:
		stop_following()
	else:
		snap_to_villain()

## Keeps him centred in the *visible* map band -- `GameCamera.center_on` already
## does that band arithmetic and already survives zooming, so following him is
## one call per frame rather than a second camera implementation.
func _update_follow() -> void:
	if camera == null:
		return
	if camera.manual_pan_ticks != _last_pan_ticks:
		_last_pan_ticks = camera.manual_pan_ticks
		following = false
	if following:
		camera.center_on(villain.position)

## Short HUD string. "Follow" rather than "Camera" because the player's mental
## model is of the camera being attached to him, not of a mode.
func follow_status_text() -> String:
	return "Following  [F]" if following else "Free camera  [F to follow]"
