extends CanvasLayer
class_name RunSummary
## The run-end screen (ruled 2026-09-26): how the run ended, what he did, the XP
## it earned, and where that leaves his level. One button: begin a new run.
##
## A pure view over `RunLifecycle.summary`, which arrives whole on
## `EventBus.run_ended` -- this holds no references to the run and reads nothing
## else. It stays interactive while the tree is paused (PROCESS_MODE_ALWAYS),
## because the run has ended underneath it.

signal new_run_requested

const PANEL_WIDTH := 560.0

var _dim: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var new_run_button: Button

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # the world underneath is over
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.96)
	style.border_color = Color(0.55, 0.42, 0.75, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_panel.add_child(_body)
	visible = false

func is_showing() -> bool:
	return visible

func show_summary(s: Dictionary) -> void:
	for c in _body.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = String(s.get("title", "The run is over")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color",
		Color(1.0, 0.82, 0.35) if String(s.get("ending", "")) == "victory" else Color(0.95, 0.38, 0.38))
	_body.add_child(title)

	_body.add_child(_wrapped(String(s.get("epitaph", "")), 13, Color(0.86, 0.82, 0.92)))
	_body.add_child(HSeparator.new())

	# ---- The run ----
	_body.add_child(_heading("This run"))
	var st: Dictionary = s.get("stats", {})
	var deeds: Dictionary = st.get("deeds", {})
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	_body.add_child(grid)
	var rows: Array = [
		["Days", str(int(s.get("day", 1)))],
		["Time", _clock(float(s.get("run_seconds", 0.0)))],
		["Dead raised", str(int(st.get("skeletons_raised", 0)))],
		["...from graves", str(int(st.get("raised_at_graves", 0)))],
		["Sites looted", str(int(st.get("sites_looted", 0)))],
		["Graves robbed", str(int(deeds.get("rob_the_dead", 0)))],
		["Dens cleared", str(int(deeds.get("cleared_a_den", 0)))],
		["Wolves killed", str(int(st.get("wolves_killed", 0)))],
		["Loot banked", str(int(st.get("banked_units", 0)))],
		["Relics banked", str(int(st.get("relics_banked", 0)))],
		["Largest escort", str(int(st.get("max_escort", 0)))],
		["Buildings", str(int(st.get("buildings_placed", 0)))],
	]
	for r in rows:
		grid.add_child(_cell(r[0], true))
		grid.add_child(_cell(r[1], false))
	if int(st.get("wakes_used", 0)) > 0:
		_body.add_child(_wrapped("Second Wake used %d× this run." % int(st.get("wakes_used", 0)), 11, Color(0.75, 0.7, 0.85)))

	_body.add_child(HSeparator.new())

	# ---- The legend ----
	_body.add_child(_heading("The Necromancer"))
	var lvl: int = int(s.get("level", 1))
	var prog: Array = s.get("progress", [0, 0])
	var into: int = int(prog[0])
	var span: int = int(prog[1])
	var xp_line := HBoxContainer.new()
	xp_line.add_theme_constant_override("separation", 10)
	_body.add_child(xp_line)
	var lvl_label := Label.new()
	lvl_label.text = "Level %d" % lvl
	lvl_label.add_theme_font_size_override("font_size", 16)
	xp_line.add_child(lvl_label)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.45, 0.92)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.13, 0.22)
	track.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", track)
	bar.max_value = maxi(1, span)
	bar.value = into if span > 0 else 1
	xp_line.add_child(bar)
	var xp_num := Label.new()
	xp_num.text = ("%d / %d XP" % [into, span]) if span > 0 else "max level"
	xp_num.add_theme_font_size_override("font_size", 12)
	xp_line.add_child(xp_num)
	_body.add_child(_wrapped("+%d XP this run  ·  %d XP in all" % [int(s.get("xp_run", 0)), int(s.get("xp_total", 0))],
		12, Color(0.8, 0.9, 0.75)))

	var next: Dictionary = s.get("next_unlock", {})
	if not next.is_empty():
		_body.add_child(_wrapped("Next: %s at level %d — %s" % [String(next.get("name", "")), int(next.get("level", 0)),
			String(next.get("description", ""))], 11, Color(0.8, 0.76, 0.9)))
	for u in s.get("unlocked", []):
		_body.add_child(_wrapped("Unlocked: %s — %s" % [String(u.get("name", "")), String(u.get("description", ""))],
			11, Color(0.7, 0.95, 0.75)))
	if not bool(s.get("persistent", true)):
		_body.add_child(_wrapped("(Test run — this profile is not saved to disk.)", 10, Color(1, 1, 1, 0.45)))

	# ---- The chronicle ----
	var chron: Array = s.get("chronicle", [])
	if chron.size() > 1:
		_body.add_child(HSeparator.new())
		_body.add_child(_heading("The chronicle"))
		var shown: Array = chron.duplicate()
		shown.reverse()
		for c in shown.slice(0, 5):
			_body.add_child(_wrapped(String(c.get("epitaph", "")), 11, Color(1, 1, 1, 0.7)))

	_body.add_child(HSeparator.new())
	new_run_button = Button.new()
	new_run_button.text = "Begin a new run"
	new_run_button.custom_minimum_size = Vector2(0, 34)
	new_run_button.pressed.connect(func(): new_run_requested.emit())
	_body.add_child(new_run_button)
	var quit := Button.new()
	quit.text = "Quit the game"
	quit.pressed.connect(func(): get_tree().quit())
	_body.add_child(quit)

	visible = true
	new_run_button.grab_focus.call_deferred()

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.78, 0.66, 0.98))
	return l

func _cell(text: String, is_key: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	if is_key:
		l.modulate = Color(1, 1, 1, 0.6)
	return l

func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 44.0, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func _clock(seconds: float) -> String:
	var s: int = int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [floori(s / 3600.0), floori((s % 3600) / 60.0)]
	return "%dm %02ds" % [floori(s / 60.0), s % 60]
