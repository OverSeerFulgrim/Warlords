extends Node
## The demo shell (review 2026-09-26, section 5): named key bindings by physical
## key, pause, the confirm on abandoning a run, the title, and the dev tools
## kept out of release builds. Since 2026-09-27 also the UI kit on the menus.
##
##   godot --headless --path . res://tools/verify_demo_shell.tscn

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	print("\n=== The demo shell ===\n")
	_actions()
	_no_hard_coded_keys()
	await _walking_is_an_action()
	await _pause()
	await _escape_pauses_when_nothing_is_open()
	_abandon_is_confirmed()
	_title()
	_ui_kit()
	_release_builds()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().paused = false
	get_tree().quit(1 if _failed > 0 else 0)

func _actions() -> void:
	print("-- Every key is a named action, bound by physical key --")
	for row in Controls.ACTIONS:
		_check("%s is registered" % row[0], InputMap.has_action(row[0]))
	var wasd_physical: bool = true
	for a in ["move_up", "move_down", "move_left", "move_right"]:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev.physical_keycode == 0 or ev.keycode != 0):
				wasd_physical = false
	_check("walking is bound by key position, not key label (AZERTY-safe)", wasd_physical)
	_check("the controls list names every player action", Controls.reference_rows().size() >= Controls.ACTIONS.size() - 1)
	_check("...with a key label for each", Controls.reference_rows().all(func(r): return String(r[0]) != "" and String(r[0]) != "—"))

func _no_hard_coded_keys() -> void:
	print("-- No gameplay script reads a raw keycode --")
	var offenders: Array = []
	for path in _scripts("res://scripts"):
		if path.ends_with("Controls.gd"):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		for needle in ["is_key_pressed(", "keycode ==", "keycode=="]:
			if src.contains(needle):
				offenders.append("%s (%s)" % [path.get_file(), needle])
	_check("none", offenders.is_empty(), str(offenders))

func _walking_is_an_action() -> void:
	print("-- WASD drives him through the action map --")
	var v: Necromancer = _main.villain
	v.place_at(_main.world_map.cell_centre_px(Vector2i(30, 62)))
	var start: Vector2 = v.position
	Input.action_press("move_right")
	await _wait(0.4)
	Input.action_release("move_right")
	_check("move_right walked him east", v.position.x > start.x + 8.0,
		"%.1f -> %.1f" % [start.x, v.position.x])

func _pause() -> void:
	print("-- Pause stops the world and gives it back --")
	var pm: PauseMenu = _main.pause_menu
	_main._open_pause_menu()
	_check("the menu is open", pm.is_open())
	_check("...and the tree is paused", get_tree().paused)
	_check("...and the menu still takes input", pm.process_mode == Node.PROCESS_MODE_ALWAYS)
	var t0: float = _main.run_lifecycle.run_seconds
	for i in range(10):
		await get_tree().process_frame
	_check("...and the run clock stood still", is_equal_approx(_main.run_lifecycle.run_seconds, t0))
	pm.close()
	_check("closing it unpauses", not pm.is_open() and not get_tree().paused)
	_main.run_summary.visible = true
	_main._open_pause_menu()
	_check("it will not open over the run-end screen", not pm.is_open())
	_main.run_summary.visible = false

func _escape_pauses_when_nothing_is_open() -> void:
	print("-- Esc closes the panel first, then pauses --")
	var pm: PauseMenu = _main.pause_menu
	_main._inspect(_main.necromancer_token, _main.inspector_actions.necromancer_actions)
	_press("cancel")
	await get_tree().process_frame
	_check("the first Esc closes the inspector", not _main.inspector.is_open() and not pm.is_open())
	_press("cancel")
	await get_tree().process_frame
	_check("the second one pauses", pm.is_open())
	_press("cancel")
	await get_tree().process_frame
	_check("...and Esc again resumes", not pm.is_open() and not get_tree().paused)
	_press("pause")
	await get_tree().process_frame
	_check("Space pauses too", pm.is_open())
	pm.close()

func _abandon_is_confirmed() -> void:
	print("-- Surrender asks first --")
	var rl: RunLifecycle = _main.run_lifecycle
	var pm: PauseMenu = _main.pause_menu
	_main._surrender_and_restart()
	_check("Surrender opens the confirm, it does not end the run", pm.is_open() and not rl.ended)
	pm.close()
	_check("...and backing out leaves the run running", not rl.ended and not get_tree().paused)
	rl.pause_on_end = false
	pm.abandon_confirmed.emit()
	_check("confirming ends it", rl.ended and String(rl.summary.get("ending", "")) == "abandoned")

func _title() -> void:
	print("-- The title --")
	var ts: TitleScreen = _main.title_screen
	_check("a harness never sees the title (it is not the running scene)", not ts.is_showing())
	ts.show_title({"level": 3, "xp": 420, "runs": 4, "last_epitaph": "Run 4 — a test."})
	get_tree().paused = true
	_check("it can be shown", ts.is_showing() and ts.begin_button != null)
	ts.begin_button.pressed.emit()
	_check("Begin hides it and starts the world", not ts.is_showing() and not get_tree().paused)

func _ui_kit() -> void:
	print("-- The menus wear the commissioned UI kit --")
	var menus: Array = [_main.title_screen, _main.pause_menu, _main.run_summary,
		_main.keep_dialog, _main.lair_screen, _main.items_dialog]
	var themed: bool = true
	for m in menus:
		var root: Control = m.get_child(0) as Control
		themed = themed and root != null and root.theme == UiKit.menu_theme()
	_check("every menu's root carries the kit theme", themed)
	var t: Theme = UiKit.menu_theme()
	_check("its buttons are the kit's plates",
		t.get_stylebox("normal", "Button") is StyleBoxTexture
		and (t.get_stylebox("normal", "Button") as StyleBoxTexture).texture == UiKit.BUTTON)
	_check("a tick box draws no plate, only the kit's box",
		t.get_stylebox("normal", "CheckBox") is StyleBoxEmpty and t.get_icon("checked", "CheckBox") == UiKit.CHECK_ON)
	var ps: StyleBox = PauseMenu.panel_style()
	_check("the dialogs' panel is the popup frame",
		ps is StyleBoxTexture and (ps as StyleBoxTexture).texture == UiKit.PANEL)
	_check("the frame never covers the text (content inside the stone)",
		ps.get_margin(SIDE_LEFT) >= UiKit.PANEL_INSIDE and ps.get_margin(SIDE_TOP) >= UiKit.PANEL_INSIDE)
	var bar := UiKit.bar(200)
	UiKit.set_bar(bar, 0.5)
	var fill: Control = bar.get_node("Fill")
	_check("the kit bar fills to its fraction", absf(fill.size.x - (200 - UiKit.BAR_INSET_X * 2) * 0.5) < 1.0)
	bar.free()

func _release_builds() -> void:
	print("-- Dev tools stay out of release builds --")
	var src: String = FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check("Main frees the three MCP bridges when not a debug build",
		src.contains("func _strip_dev_bridges") and src.contains("MCPRuntimeBridge")
		and src.contains("if OS.is_debug_build():"))
	var hud: HudTopBar = _main.hud_top_bar
	_check("the game-speed button follows the build type",
		hud.time_scale_btn.visible == OS.is_debug_build())
	_check("F3 is still behind OS.is_debug_build()",
		src.contains('is_action_pressed("debug_overlay", false, false) and OS.is_debug_build()'))

# ---------------- Helpers ------------------------------------------------------

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)

func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
