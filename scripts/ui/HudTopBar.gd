class_name HudTopBar
extends Node

## **The HUD's two top corners** (the HUD redo, 2026-09-26; mockups in the
## "Warlords HUD redo" canvas). Replaces the old full-width resource strip.
##
## - **Top left, his column:** the portrait card (name, level, hp bar, stance,
##   bag, escort), the worn-gear strip (once he owns gear), the "not home yet"
##   pouch line (once he carries resources), a small orientation line, the dusk
##   warning, and -- handed in by Main -- the roster of his dead.
## - **Top right:** the day and the threat, the debug speed button, **Map (M)**
##   and **History (L)** under it, and the chips that earn their place: the
##   guild's standing once he has met them, the Raven once she has news.
## - **Top centre, only at the lair:** the Treasury -- what is banked.
##
## The rule every piece follows: **it appears the first time the mechanic it
## controls does, and never before.** Run one opens with a portrait, a clock,
## the two buttons, and nothing else up here.
##
## This module owns nothing but its own Controls. It reads GameState and the
## systems handed to it, and everything it cannot decide goes out as a signal.

signal badge_pressed
signal debug_speed_changed(scale: float)
signal raven_chip_pressed
signal stance_pressed
signal items_pressed
signal map_pressed
signal history_pressed
signal guild_chip_pressed

const NECROMANCER_SPRITE := "res://assets/official/characters/Necromancer_Portrait.png"
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const DUSK_WARNING_SECONDS: float = 120.0
const COLUMN_WIDTH := 300.0

# ---------------- Owned Controls ----------------
## His column, top left. Main appends the roster of his dead to it.
var left_column: VBoxContainer
var right_column: VBoxContainer
var necro_badge: Button
var name_label: Label
var level_label: Label
var hp_bar: ColorRect
var villain_hp_label: Label
var stance_chip: Button
var bag_chip: Button
var escort_chip: Button
var gear_strip: HBoxContainer
var _gear_buttons: Dictionary = {}      # slot -> Button
var pouch_panel: PanelContainer
var pouch_label: Label
## **Prisoners** (L3): who is on his rope and how full the Cell is. Appears with
## the first man he binds.
var prisoner_panel: PanelContainer
var prisoner_label: Label
## `func() -> Array`: the prisoners held in his Cells.
var held_provider: Callable = Callable()
## `func() -> int`: how many his Cells can hold.
var cell_capacity_provider: Callable = Callable()
var orientation_label: Label
var follow_state_label: Label
var dusk_warning_label: Label
var day_label: Label
var phase_label: Label
var threat_label: Label
var time_scale_btn: Button
var map_btn: Button
var history_btn: Button
var guild_chip: Button
var raven_chip: Button
var treasury_panel: PanelContainer
var treasury_label: Label
## Kept for callers that still ask about the old strip.
var stance_label: Label

# ---------------- References handed in by Main.gd ----------------
var _settlement: SettlementGrid
var _day_night: DayNightCycle
var _world_map: WorldMap
var _villain: Necromancer
var _villain_controller: VillainController
var _travel_log: TravelLog
var _sortie_system: SortieSystem
var _minimap: Minimap
## `func() -> int`, his level (the profile's). Unset: the level line hides.
var level_provider: Callable = Callable()
## `func() -> bool`: is he home (by the Throne)? The Treasury shows only then.
var home_provider: Callable = Callable()

func build(hud_root: Control, _panel_style: StyleBoxFlat, settlement: SettlementGrid,
		day_night: DayNightCycle, world_map: WorldMap, villain: Necromancer,
		villain_controller: VillainController, travel_log: TravelLog) -> void:
	_settlement = settlement
	_day_night = day_night
	_world_map = world_map
	_villain = villain
	_villain_controller = villain_controller
	_travel_log = travel_log
	_build_left(hud_root)
	_build_right(hud_root)
	_build_treasury(hud_root)
	_connect_signals()
	refresh_villain_hp()
	set_stance("Hidden")

func set_minimap(m: Minimap) -> void:
	_minimap = m

func set_sortie_system(s: SortieSystem) -> void:
	_sortie_system = s

func _connect_signals() -> void:
	GameState.resources_changed.connect(func(): refresh_stats())
	GameState.threat_changed.connect(func(_a, _b): refresh_stats())
	GameState.power_changed.connect(func(_a): refresh_stats())
	EventBus.day_phase_changed.connect(func(_label: String): refresh_stats())
	EventBus.main_building_damaged.connect(func(_b): refresh_stats())
	EventBus.damage_shown.connect(func(unit, _amount: int, _kind: String):
		if unit == _villain:
			refresh_villain_hp()
	)
	EventBus.gear_changed.connect(func(v):
		if v == _villain:
			refresh_items()
	)

# ---------------- Building ----------------

func _build_left(hud_root: Control) -> void:
	left_column = VBoxContainer.new()
	left_column.name = "HudLeftColumn"
	left_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_column.position = Vector2(14, 12)
	left_column.add_theme_constant_override("separation", 6)
	left_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(left_column)

	var card := HudStyle.panel()
	left_column.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	necro_badge = Button.new()
	necro_badge.custom_minimum_size = Vector2(56, 56)
	necro_badge.tooltip_text = "The Necromancer"
	HudStyle.style_button(necro_badge, true)
	if ResourceLoader.exists(NECROMANCER_SPRITE):
		var icon := TextureRect.new()
		icon.texture = load(NECROMANCER_SPRITE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		necro_badge.add_child(icon)
	necro_badge.pressed.connect(func(): badge_pressed.emit())
	row.add_child(necro_badge)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.custom_minimum_size = Vector2(210, 0)
	row.add_child(info)
	var name_row := HBoxContainer.new()
	info.add_child(name_row)
	name_label = HudStyle.label("The Necromancer", 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	level_label = HudStyle.label("", 12, HudStyle.ACCENT)
	name_row.add_child(level_label)
	hp_bar = HudStyle.bar(210.0, 8.0)
	info.add_child(hp_bar)
	villain_hp_label = HudStyle.label("", 12, HudStyle.MUTED)
	info.add_child(villain_hp_label)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	info.add_child(chips)
	stance_chip = Button.new()
	stance_chip.pressed.connect(func(): stance_pressed.emit())
	chips.add_child(stance_chip)
	bag_chip = Button.new()
	HudStyle.style_chip(bag_chip)
	bag_chip.tooltip_text = "His items (I)"
	bag_chip.pressed.connect(func(): items_pressed.emit())
	chips.add_child(bag_chip)
	escort_chip = Button.new()
	HudStyle.style_chip(escort_chip)
	escort_chip.visible = false
	escort_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(escort_chip)
	stance_label = HudStyle.label()   # compatibility only; never shown
	stance_label.visible = false

	# Worn gear: five slots, once he owns any gear at all.
	gear_strip = HBoxContainer.new()
	gear_strip.add_theme_constant_override("separation", 6)
	gear_strip.visible = false
	left_column.add_child(gear_strip)
	for slot in Necromancer.GEAR_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 44)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(func(): items_pressed.emit())
		gear_strip.add_child(b)
		_gear_buttons[slot] = b

	pouch_panel = PanelContainer.new()
	pouch_panel.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.AMBER_BORDER, 8, 8))
	pouch_panel.visible = false
	pouch_panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	left_column.add_child(pouch_panel)
	pouch_label = HudStyle.label("", 13, HudStyle.AMBER)
	pouch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pouch_label.custom_minimum_size = Vector2(COLUMN_WIDTH - 20.0, 0)
	pouch_panel.add_child(pouch_label)

	prisoner_panel = PanelContainer.new()
	prisoner_panel.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.BORDER_ACCENT, 8, 8))
	prisoner_panel.visible = false
	prisoner_panel.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	left_column.add_child(prisoner_panel)
	prisoner_label = HudStyle.label("", 13, Color("d9ccf2"))
	prisoner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prisoner_label.custom_minimum_size = Vector2(COLUMN_WIDTH - 20.0, 0)
	prisoner_panel.add_child(prisoner_label)

	var ori_panel := PanelContainer.new()
	ori_panel.add_theme_stylebox_override("panel", HudStyle.box(Color(0.09, 0.07, 0.11, 0.78), Color(0, 0, 0, 0), 6, 5))
	ori_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_column.add_child(ori_panel)
	var ori := HBoxContainer.new()
	ori.add_theme_constant_override("separation", 8)
	ori_panel.add_child(ori)
	orientation_label = HudStyle.label("", 11, HudStyle.MUTED)
	ori.add_child(orientation_label)
	follow_state_label = HudStyle.label("", 11, HudStyle.MUTED)
	ori.add_child(follow_state_label)

	dusk_warning_label = HudStyle.label("", 12, Color(1.0, 0.72, 0.35))
	dusk_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dusk_warning_label.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	dusk_warning_label.visible = false
	left_column.add_child(dusk_warning_label)
	refresh_items()

func _build_right(hud_root: Control) -> void:
	right_column = VBoxContainer.new()
	right_column.name = "HudRightColumn"
	right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_column.offset_right = -14
	right_column.offset_top = 12
	right_column.add_theme_constant_override("separation", 6)
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(right_column)

	var day := HudStyle.panel()
	right_column.add_child(day)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	day.add_child(row)
	day_label = HudStyle.label("Day 1", 15)
	row.add_child(day_label)
	phase_label = HudStyle.label("", 14, HudStyle.MUTED)
	row.add_child(phase_label)
	threat_label = HudStyle.label("", 13, Color("e0a050"))
	threat_label.visible = false
	row.add_child(threat_label)
	time_scale_btn = Button.new()
	time_scale_btn.tooltip_text = "Debug: cycle game speed (1x / 10x / 60x)"
	time_scale_btn.custom_minimum_size = Vector2(44, 30)
	HudStyle.style_button(time_scale_btn, false, 13)
	time_scale_btn.pressed.connect(_on_time_scale_pressed)
	time_scale_btn.visible = OS.is_debug_build()
	row.add_child(time_scale_btn)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	right_column.add_child(btns)
	map_btn = _key_button("Map", "map")
	map_btn.pressed.connect(func(): map_pressed.emit())
	btns.add_child(map_btn)
	history_btn = _key_button("History", "history")
	history_btn.pressed.connect(func(): history_pressed.emit())
	btns.add_child(history_btn)

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override("separation", 6)
	right_column.add_child(chips)
	guild_chip = Button.new()
	HudStyle.style_chip(guild_chip, HudStyle.BORDER, HudStyle.BG_RAISED, Color("d7cce8"))
	guild_chip.visible = false
	guild_chip.tooltip_text = "What the Adventurers' Guild thinks of him."
	guild_chip.pressed.connect(func(): guild_chip_pressed.emit())
	chips.add_child(guild_chip)
	raven_chip = Button.new()
	HudStyle.style_chip(raven_chip, HudStyle.BORDER_ACCENT, HudStyle.BG_ACCENT, Color("e2d6ff"))
	raven_chip.tooltip_text = "The Raven. Click to look where she has been."
	raven_chip.visible = false
	raven_chip.pressed.connect(func(): raven_chip_pressed.emit())
	chips.add_child(raven_chip)

func _key_button(text: String, action: String) -> Button:
	var b := Button.new()
	b.text = "%s  %s" % [text, Controls.label_for(action)]
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.style_button(b, false, 14)
	return b

func _build_treasury(hud_root: Control) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 12
	holder.offset_bottom = 56
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(holder)
	treasury_panel = PanelContainer.new()
	treasury_panel.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.AMBER_BORDER, 8, 10))
	treasury_panel.visible = false
	holder.add_child(treasury_panel)
	treasury_label = HudStyle.label("", 15)
	treasury_panel.add_child(treasury_label)

# ---------------- Readouts ----------------

func set_stance(stance_name: String) -> void:
	if stance_chip == null:
		return
	var hunting: bool = stance_name == "Hunting"
	stance_chip.text = "%s · %s" % ["Hunting" if hunting else "Hidden", Controls.label_for("stance")]
	if hunting:
		HudStyle.style_chip(stance_chip, HudStyle.DANGER, Color("4a2228"), Color("ffd8cf"))
	else:
		HudStyle.style_chip(stance_chip, Color("6c5a86"), HudStyle.BG_ACCENT, Color("d9ccf2"))
	stance_chip.tooltip_text = ("Hunting: anything living he walks up to is fair game." if hunting
		else "Hidden: he never starts a fight with the living.")

func set_raven_count(outstanding: int, unseen: int) -> void:
	if raven_chip == null:
		return
	raven_chip.visible = outstanding > 0
	raven_chip.text = "Raven" if outstanding <= 1 else "Raven × %d" % outstanding
	raven_chip.tooltip_text = ("The Raven has found something. Click to look." if unseen > 0
		else "The Raven's marks. Click to cycle through them.")
	if unseen > 0:
		var tw := raven_chip.create_tween()
		raven_chip.modulate = Color(1.6, 1.3, 2.0)
		tw.tween_property(raven_chip, "modulate", Color.WHITE, 0.9)

func flicker_raven_silent(outstanding: int) -> void:
	if raven_chip == null:
		return
	raven_chip.visible = true
	raven_chip.text = "Raven —"
	raven_chip.modulate = Color(1, 1, 1, 0.9)
	var tw := raven_chip.create_tween()
	tw.tween_property(raven_chip, "modulate", Color(1, 1, 1, 0.25), 2.5)
	tw.tween_callback(func(): set_raven_count(outstanding, 0))

## The guild chip earns its place the first time he meets the guild.
func set_guild_standing(tier_name: String) -> void:
	if guild_chip == null:
		return
	guild_chip.visible = true
	guild_chip.text = "Guild: %s" % tier_name
	var c: Color = {"Unknown": Color("d7cce8"), "Suspected": Color("f0c070"), "Known": Color("ff9a8a")}.get(tier_name, Color("d7cce8"))
	HudStyle.style_chip(guild_chip, HudStyle.BORDER, HudStyle.BG_RAISED, c)

## "20 / 20 hp", the bar, and **red below 30%** -- `Combat.FLEE_HP_FRACTION`,
## read from there so the HUD and the escort's retreat rule never disagree.
func refresh_villain_hp() -> void:
	if villain_hp_label == null or _villain == null:
		return
	var frac: float = _villain.hp_fraction()
	villain_hp_label.text = "%d / %d hp" % [_villain.hp, _villain.max_hp()]
	var col: Color = HudStyle.MUTED
	if not _villain.is_alive() or frac < Combat.FLEE_HP_FRACTION:
		col = Color(1.0, 0.4, 0.35)
	elif _villain.hp < _villain.max_hp():
		col = Color(0.95, 0.72, 0.42)
	villain_hp_label.add_theme_color_override("font_color", col)
	HudStyle.set_bar(hp_bar, frac, HudStyle.HP_FILL)

## Bag count, worn gear and the pouch -- polled with the orientation line.
func refresh_items() -> void:
	if _villain == null or bag_chip == null:
		return
	bag_chip.text = "Bag %d / %d" % [_villain.carried_total(), _villain.carry_capacity()]
	var owns_gear: bool = not _villain.equipped.is_empty()
	if not owns_gear:
		for id in _villain.relics_carried + _villain.relics_banked:
			if Necromancer.is_gear(String(id)):
				owns_gear = true
				break
	gear_strip.visible = owns_gear
	for slot in _gear_buttons.keys():
		var b: Button = _gear_buttons[slot]
		var id: String = String(_villain.equipped.get(slot, ""))
		b.text = Necromancer.GEAR_SLOT_NAMES[slot]
		if id != "":
			b.tooltip_text = "%s: %s" % [Necromancer.GEAR_SLOT_NAMES[slot], ItemsDialog.effect_text(id)]
			var s := HudStyle.box(Color("22301f"), HudStyle.GOOD, 6, 4)
			for k in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(k, s)
			b.add_theme_color_override("font_color", Color("e6f2df"))
		else:
			b.tooltip_text = "Nothing worn here."
			var s2 := HudStyle.box(HudStyle.BG, HudStyle.BORDER, 6, 4)
			for k in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(k, s2)
			b.add_theme_color_override("font_color", Color("7d738a"))
	pouch_panel.visible = not _villain.carried.is_empty()
	if pouch_panel.visible:
		pouch_label.text = "Not home yet: %s" % LootCatalog.describe(_villain.carried).to_lower()
	var n: int = _villain.escort.size()
	escort_chip.visible = n > 0
	escort_chip.text = "Escort %d" % n
	refresh_prisoners()

func refresh_prisoners() -> void:
	if prisoner_panel == null or _villain == null:
		return
	var held: Array = held_provider.call() if held_provider.is_valid() else []
	var cap: int = int(cell_capacity_provider.call()) if cell_capacity_provider.is_valid() else 0
	var tow: Array = _villain.prisoners
	prisoner_panel.visible = not tow.is_empty() or not held.is_empty()
	if not prisoner_panel.visible:
		return
	var lines: Array = []
	if not tow.is_empty():
		var names: Array = tow.map(func(p): return String(p.display_name))
		lines.append("On the rope: %s — walk them home" % ", ".join(names))
	if cap > 0 or not held.is_empty():
		lines.append("The Cell: %d / %d" % [held.size(), cap])
	elif not tow.is_empty():
		lines.append("No Cell to hold them yet")
	var hungry: int = 0
	for p in tow + held:
		if int(p.missed_meals) > 0:
			hungry += 1
	if hungry > 0:
		lines.append("%d hungry — they eat 1 food at dawn and dusk" % hungry)
	prisoner_label.text = "\n".join(lines)

func top_height() -> float:
	# No full-width strip any more: the world runs to the top of the window.
	return 0.0

## "Band 2 · Lair 24 cells W · Away 3:10". Also refreshes the item readouts,
## the Treasury (shown only inside the lair band) and the dusk warning.
func refresh_orientation() -> void:
	if orientation_label == null or _world_map == null or _villain == null:
		return
	var band: Dictionary = _world_map.band_at(_villain.position)
	var lair: Vector2 = _lair_centre()
	var to_lair: Vector2 = lair - _villain.position
	var cells_home: int = roundi(to_lair.length() / float(WorldMap.CELL_SIZE))
	var text := "Band %d" % int(band["band"])
	if cells_home <= 1:
		text += " · at the lair"
	else:
		var octant: int = wrapi(roundi(to_lair.angle() / (TAU / 8.0)), 0, 8)
		text += " · lair %d cells %s" % [cells_home, COMPASS[octant]]
	if _travel_log and _travel_log.elapsed() >= 0.0:
		text += " · away %s" % TravelLog._fmt(_travel_log.elapsed())
	orientation_label.text = text
	refresh_items()
	var home: bool = bool(home_provider.call()) if home_provider.is_valid() else _villain.is_in_lair_band()
	if treasury_panel.visible != home:
		treasury_panel.visible = home
		if home:
			refresh_stats()
	_refresh_dusk_warning()
	if _minimap:
		_minimap.queue_redraw()

func _lair_centre() -> Vector2:
	return _world_map.cell_centre_px(
		_world_map.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2))

func _refresh_dusk_warning() -> void:
	if dusk_warning_label == null:
		return
	var warn: bool = false
	var left: float = 0.0
	if _day_night and _villain and not _villain.is_in_lair_band():
		if _day_night.is_day:
			left = DayNightCycle.DAY_SECONDS - _day_night.elapsed_in_phase
			warn = left <= DUSK_WARNING_SECONDS
		else:
			warn = true
	dusk_warning_label.visible = warn
	if not warn:
		return
	var cells: String = "%d cells" % roundi(_lair_centre().distance_to(_villain.position) / float(WorldMap.CELL_SIZE))
	if _day_night.is_day:
		dusk_warning_label.text = "The light is going — %s of it left, and you are %s from home." % [
			TravelLog._fmt(left), cells]
	else:
		dusk_warning_label.text = "It is dark, and you are %s from home." % cells

func refresh_follow_state() -> void:
	if follow_state_label == null or _villain_controller == null:
		return
	follow_state_label.text = "· camera follows (%s)" % Controls.label_for("follow") if _villain_controller.following \
		else "· camera free (%s)" % Controls.label_for("follow")
	follow_state_label.modulate = Color(1, 1, 1, 0.9) if _villain_controller.following else Color(1, 1, 1, 0.55)

func refresh_stats() -> void:
	if day_label == null:
		return
	if level_label and level_provider.is_valid():
		level_label.text = "Lv %d" % int(level_provider.call())
	if _day_night:
		day_label.text = "Day %d" % _day_night.day_number
		phase_label.text = _day_night.phase_name()
		time_scale_btn.text = _day_night.time_scale_label()
	threat_label.visible = GameState.threat > 0
	threat_label.text = "Threat %d" % GameState.threat
	var parts: Array = ["Wood %d" % GameState.wood, "Stone %d" % GameState.stone, "Bones %d" % GameState.bones,
		"Food %d" % GameState.food, "Gold %d" % GameState.gold, "Essence %d" % GameState.dark_essence]
	if GameState.arms > 0:
		parts.append("Arms %d" % GameState.arms)
	var main_building := _settlement.get_main_building() if _settlement else null
	if main_building:
		parts.append("Throne %d / %d" % [main_building.hp, main_building.max_hp])
	treasury_label.text = "Treasury    " + "    ".join(parts)

func _on_time_scale_pressed() -> void:
	var scale: float = _day_night.cycle_time_scale()
	refresh_stats()
	debug_speed_changed.emit(scale)
