extends RefCounted
class_name Controls
## Every key the game reads, as named InputMap actions (review 2026-09-26: keys
## were hard-coded logical keycodes, so WASD fell apart on AZERTY).
##
## ## Physical keys, registered at startup
##
## Each default is bound by **physical** keycode -- the key's position, not its
## label -- so "the key where W is on a QWERTY board" moves him up on any layout.
## The actions are registered here rather than in project.godot so they can
## never be stripped by an editor re-save, and `ensure()` only adds an action
## that does not already exist: anything defined in Project Settings > Input Map
## wins, which is the path a rebinding screen will take.
##
## `label_for()` asks the OS what the key is called **on this keyboard**, so
## the controls list reads "Z" to a French player for the key a British one
## calls "W".

const ACTIONS := [
	# [action, human name, physical keycodes...]
	["move_up", "Walk north", KEY_W],
	["move_down", "Walk south", KEY_S],
	["move_left", "Walk west", KEY_A],
	["move_right", "Walk east", KEY_D],
	["pan_up", "Pan camera up", KEY_UP],
	["pan_down", "Pan camera down", KEY_DOWN],
	["pan_left", "Pan camera left", KEY_LEFT],
	["pan_right", "Pan camera right", KEY_RIGHT],
	["follow", "Camera follows him", KEY_F],
	["raise_dead", "Raise Dead (5 bones)", KEY_R],
	["stance", "Hidden / Hunting", KEY_H],
	["items", "Items (wear, drop, swap)", KEY_I],
	["escort", "Escort on / off", KEY_E],
	["rally", "Place the rally point", KEY_C],
	["build", "Build", KEY_B],
	["map", "The big map", KEY_M],
	["history", "History", KEY_L],
	["bind", "Bind the fallen near him (prisoners)", KEY_G],
	["finish", "Finish the fallen near him", KEY_X],
	["pause", "Pause", KEY_SPACE, KEY_P],
	["cancel", "Cancel / close / pause", KEY_ESCAPE],
	["debug_overlay", "Dev site overlay (debug builds)", KEY_F3],
]

## Mouse controls, for the controls list only -- they are not actions.
const MOUSE := [
	["Left click", "Inspect / place / choose"],
	["Right click", "Walk there"],
	["Right drag", "Pan the camera"],
	["Wheel", "Zoom"],
	["Minimap click", "Look there (right-click: walk there)"],
]

static func ensure() -> void:
	for row in ACTIONS:
		var action: String = row[0]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for i in range(2, row.size()):
			var ev := InputEventKey.new()
			ev.physical_keycode = row[i]
			InputMap.action_add_event(action, ev)

## What the first key bound to `action` is called on this keyboard.
static func label_for(action: String) -> String:
	ensure()
	var names: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: int = ev.keycode
			# Headless has no keyboard layout to ask; the physical code's own name is
			# the honest answer there.
			if k == 0 and DisplayServer.get_name() != "headless":
				k = DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)
			if k == 0:
				k = ev.physical_keycode
			names.append(OS.get_keycode_string(k))
	return " / ".join(names) if not names.is_empty() else "—"

## `[key label, what it does]` rows for every non-debug action, then the mouse.
static func reference_rows() -> Array:
	var out: Array = []
	for row in ACTIONS:
		if row[0] == "debug_overlay" and not OS.is_debug_build():
			continue
		out.append([label_for(row[0]), row[1]])
	for m in MOUSE:
		out.append(m)
	return out
