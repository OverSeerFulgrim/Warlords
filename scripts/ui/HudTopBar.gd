class_name HudTopBar
extends Node

## The top HUD strip and the necromancer badge beneath it: resource readout,
## day/clock, the debug time-scale button, the clickable portrait, and the
## follow-state / orientation lines.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). This module owns nothing but
## its own Controls -- it reads GameState and the handful of systems handed to it
## by Main.gd at build time, and it never looks anything up. The two things it
## cannot decide for itself go out as signals: opening the Necromancer's entry in
## the shared inspection panel (inspect glue stays in Main.gd) and writing the
## debug-speed line to the history log.

## Opening the Necromancer's inspection entry is Main.gd's call -- the badge and
## the on-map token are two doors to one room, and only Main.gd knows the room.
signal badge_pressed

## Emitted after the debug speed button has already applied the new scale, so
## Main.gd only has to log it.
signal debug_speed_changed(scale: float)

const ICON_DARK_ESSENCE := "res://assets/official/icons/Icon_Dark_Essence.png"
const NECROMANCER_SPRITE := "res://assets/official/characters/Necromancer_Portrait.png"

## Compass directions for the way-home readout. Eight of them: four is not
## enough to steer by on a 144-cell map, sixteen is more precision than a text
## line can carry.
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

## How much daylight is left before the dusk warning starts. Two minutes of a
## thirty-minute day -- long enough to still get home from most of the map, and
## a tunable (SORTIE_SPEC §10: "how loud the dusk warning is, and at what hour").
const DUSK_WARNING_SECONDS: float = 120.0

# ---------------- Owned Controls ----------------
var top_panel: PanelContainer  # kept so menus below can size themselves off its actual height
var lbl_resources_left: Label
var lbl_resources_right: Label
var lbl_dark_essence: Label    # sits right of the Dark Essence icon
var time_scale_btn: Button
var necro_badge: Button
## His hit points, beside the badge. Red below 30%. See refresh_villain_hp().
var villain_hp_label: Label
## "The light is going" -- only while he is out with the sun low. See
## _refresh_dusk_warning().
var dusk_warning_label: Label
## Camera-follow readout, under the badge. See refresh_follow_state().
var follow_state_label: Label
## Where am I / how deep am I / which way is home. See refresh_orientation().
var orientation_label: Label

# ---------------- References handed in by Main.gd ----------------
var _settlement: SettlementGrid
var _day_night: DayNightCycle
var _world_map: WorldMap
var _villain: Necromancer
var _villain_controller: VillainController
var _travel_log: TravelLog
## The return leg, for the carry readout. Null-safe: no system, no readout.
var _sortie_system: SortieSystem
var _minimap: Minimap

## Builds the strip into `hud_root`. Call order inside here is load-bearing in
## the same way it was in Main.gd: sibling Controls are drawn -- and offered
## mouse input -- in child order, last on top.
func build(hud_root: Control, panel_style: StyleBoxFlat, settlement: SettlementGrid,
		day_night: DayNightCycle, world_map: WorldMap, villain: Necromancer,
		villain_controller: VillainController, travel_log: TravelLog) -> void:
	_settlement = settlement
	_day_night = day_night
	_world_map = world_map
	_villain = villain
	_villain_controller = villain_controller
	_travel_log = travel_log

	_build_top_bar(hud_root, panel_style)
	_build_necro_badge(hud_root)
	_connect_signals()

## The minimap is born in the bottom shell, which is built after this strip, so
## Main.gd hands it over once it exists. The orientation readout nudges it to
## redraw; until it arrives that nudge is simply skipped.
func set_minimap(m: Minimap) -> void:
	_minimap = m

## Same arrangement as the minimap: the return leg is built in `_build_systems`
## but this strip is built before it is handed over, so Main.gd passes it once
## it exists. Until then the carry readout is simply skipped.
func set_sortie_system(s: SortieSystem) -> void:
	_sortie_system = s

## The readouts that change on their own. Everything here is a HUD-only
## consumer, so it lives with the HUD rather than in Main.gd's wiring. Mixed
## call sites (a stats refresh alongside a build-row repopulate, say) stay in
## Main.gd and call refresh_stats() directly.
func _connect_signals() -> void:
	GameState.resources_changed.connect(func(): refresh_stats())
	GameState.reputation_changed.connect(func(_a): refresh_stats())
	GameState.threat_changed.connect(func(_a, _b): refresh_stats())
	GameState.power_changed.connect(func(_a): refresh_stats())
	# Fires on Dawn/Daylight/Dusk/Night word changes only, not per frame.
	EventBus.day_phase_changed.connect(func(_label: String): refresh_stats())
	EventBus.main_building_damaged.connect(func(_b): refresh_stats())
	# Every hp change on him, from any source -- a wolf's bite, a guardian's, the
	# out-of-combat regen. `damage_shown` is already the one signal the policy
	# layer fires for exactly this (COMBAT_FEEDBACK_SPEC §2), so the readout
	# rides it rather than being polled or needing a second announcement.
	EventBus.damage_shown.connect(func(unit, _amount: int, _kind: String):
		if unit == _villain:
			refresh_villain_hp()
	)

## Thin single-row resource strip along the very top: Dark Essence/Wood/
## Stone/Bones on the left, Threat/Power/Throne hp on the right, matching the
## design-mockup pass. No per-resource icons yet (the art pack has icons for
## some resources but not all -- see Necromancer_Reference.md -- so text-only
## for now to avoid a mismatched partial icon set; a follow-up art pass can
## add them once the layout itself is confirmed live in-editor).
func _build_top_bar(hud_root: Control, panel_style: StyleBoxFlat) -> void:
	top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.add_theme_stylebox_override("panel", panel_style)
	hud_root.add_child(top_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	top_panel.add_child(row)

	lbl_resources_left = Label.new()
	lbl_resources_left.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl_resources_left)

	# Dark Essence gets an icon; the other four are still text. The source art
	# is 1024px square, so it's scaled into a fixed 20x20 box by the
	# TextureRect rather than by a Sprite2D scale factor -- Controls size
	# themselves, and EXPAND_IGNORE_SIZE is what stops the raw 1024px asking
	# for a 1024px-tall top bar.
	var essence_icon := TextureRect.new()
	if ResourceLoader.exists(ICON_DARK_ESSENCE):
		essence_icon.texture = load(ICON_DARK_ESSENCE)
	else:
		push_warning("HudTopBar: Dark Essence icon not found at %s" % ICON_DARK_ESSENCE)
	essence_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	essence_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	essence_icon.custom_minimum_size = Vector2(20, 20)
	essence_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	essence_icon.tooltip_text = "Dark Essence"
	row.add_child(essence_icon)

	lbl_dark_essence = Label.new()
	lbl_dark_essence.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl_dark_essence)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	lbl_resources_right = Label.new()
	lbl_resources_right.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl_resources_right)

	# Debug speed control, far right of the top bar. Deliberately labelled as
	# debug -- it's a development affordance for watching a 50-minute cycle or
	# a gathering trip without waiting, not a player-facing game-speed feature.
	# See DayNightCycle.cycle_time_scale() for how the scaling actually reaches
	# every system.
	time_scale_btn = Button.new()
	time_scale_btn.tooltip_text = "Debug: cycle game speed (1x / 10x / 60x)"
	time_scale_btn.pressed.connect(_on_time_scale_pressed)
	row.add_child(time_scale_btn)

## Clickable player portrait, top-left under the resource bar. It and the on-map
## token are two doors to one room: both open his entry in the shared inspection
## panel, which now reads real state (hp, Might, carry, escort) off the
## `Necromancer` data object rather than the placeholder rows it used to carry.
func _build_necro_badge(hud_root: Control) -> void:
	necro_badge = Button.new()
	necro_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	necro_badge.position = Vector2(10, 40)
	necro_badge.custom_minimum_size = Vector2(40, 40)
	necro_badge.tooltip_text = "The Necromancer"
	if ResourceLoader.exists(NECROMANCER_SPRITE):
		var icon := TextureRect.new()
		icon.texture = load(NECROMANCER_SPRITE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		necro_badge.add_child(icon)
	# The HUD badge and the on-map avatar open the same panel -- two doors to
	# one room, same as the Keep menu having a top-bar and a click-the-building
	# entry point.
	necro_badge.pressed.connect(func(): badge_pressed.emit())
	hud_root.add_child(necro_badge)

	# Under the orientation line, and hidden until the sun is low.
	dusk_warning_label = Label.new()
	dusk_warning_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dusk_warning_label.position = Vector2(54, 78)
	dusk_warning_label.add_theme_font_size_override("font_size", 11)
	dusk_warning_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
	dusk_warning_label.visible = false
	hud_root.add_child(dusk_warning_label)

	# **His hit points, beside the badge.** He is the run (R4), and until now the
	# only place his health appeared was inside the inspection panel -- which is
	# closed exactly when it matters, because closing it is how you get back to
	# driving him. NECROMANCER_SPEC §6: the game's whole duty at 30% is that
	# nobody dies uninformed.
	villain_hp_label = Label.new()
	villain_hp_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	villain_hp_label.position = Vector2(54, 36)
	villain_hp_label.add_theme_font_size_override("font_size", 11)
	hud_root.add_child(villain_hp_label)
	refresh_villain_hp()

	# Follow state, small, immediately under the badge -- the one bit of camera
	# mode the player has to be able to read at a glance, since a right-drag
	# silently drops out of it.
	follow_state_label = Label.new()
	follow_state_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	follow_state_label.position = Vector2(54, 50)
	follow_state_label.add_theme_font_size_override("font_size", 10)
	hud_root.add_child(follow_state_label)
	refresh_follow_state()

	# Orientation, always visible. The minimap answers this too, but it lives in
	# the command bar, which collapses -- and 9216px of world is exactly the
	# situation where the player must never be one keystroke away from lost.
	orientation_label = Label.new()
	orientation_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	orientation_label.position = Vector2(54, 64)
	orientation_label.add_theme_font_size_override("font_size", 10)
	orientation_label.modulate = Color(1, 1, 1, 0.72)
	hud_root.add_child(orientation_label)

## "20 / 20 hp", and **red below 30%** -- the threshold `Combat.FLEE_HP_FRACTION`
## already defines for everyone else, read from there rather than restated so the
## HUD and the escort's cover-the-retreat rule can never disagree about when he
## is in trouble.
##
## He does not auto-flee at it. That is deliberate and load-bearing
## (NECROMANCER_SPEC §6): removing player control at low hp would break the one
## carve-out the control pillar makes. Panic is the player's job; this readout
## is the game making sure the player has the information to panic *with*.
func refresh_villain_hp() -> void:
	if villain_hp_label == null or _villain == null:
		return
	villain_hp_label.text = "%d / %d hp" % [_villain.hp, _villain.max_hp()]
	if not _villain.is_alive():
		villain_hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif _villain.hp_fraction() < Combat.FLEE_HP_FRACTION:
		villain_hp_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	elif _villain.hp < _villain.max_hp():
		villain_hp_label.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42))
	else:
		villain_hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))

## The strip's laid-out height, which the camera insets and the floating panels
## size themselves against.
func top_height() -> float:
	return top_panel.size.y if top_panel else 0.0

## "Cell 42, 60  ·  Band 2 — Contested Wilderness  ·  Lair 24 cells W"
##
## Three questions the player has on the world map and cannot answer from the
## viewport: where am I, how deep am I, and which way is home. The band half is
## the only consumer of WORLD_MAP_PLAN §6's data today -- R2's encounter and
## loot tables are the ones it exists for.
func refresh_orientation() -> void:
	if orientation_label == null or _world_map == null or _villain == null:
		return
	var cell: Vector2i = _world_map.cell_at(_villain.position)
	var band: Dictionary = _world_map.band_at(_villain.position)
	var lair: Vector2 = _world_map.cell_centre_px(
		_world_map.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2))
	var to_lair: Vector2 = lair - _villain.position
	var cells_home: int = roundi(to_lair.length() / float(WorldMap.CELL_SIZE))
	var text := "Cell %d, %d   ·   Band %d — %s" % [cell.x, cell.y, band["band"], band["name"]]
	if cells_home <= 1:
		text += "   ·   At the lair"
	else:
		var octant: int = wrapi(roundi(to_lair.angle() / (TAU / 8.0)), 0, 8)
		text += "   ·   Lair %d cells %s" % [cells_home, COMPASS[octant]]
	if _travel_log and _travel_log.elapsed() >= 0.0:
		text += "   ·   Away %s" % TravelLog._fmt(_travel_log.elapsed())
	# **Carry state beside the Away timer** (SORTIE_SPEC §7). The panel has it
	# too, but the panel is closed exactly when it matters -- closing it is how
	# you get back to driving him -- and "he was full" is the thing a player must
	# never learn from a site refusing to pay out.
	if _sortie_system:
		text += "   ·   Carrying %s" % _sortie_system.carry_label()
	orientation_label.text = text
	_refresh_dusk_warning()
	if _minimap:
		_minimap.queue_redraw()

## **The player should never discover they were overloaded at nightfall by dying
## of it** (SORTIE_SPEC §7). One line, only while he is out in the world with
## the light going: inside the lair band he is home and the warning would be
## noise.
##
## Reads the day cycle's own clock rather than a second timer, so it inherits
## the debug time scale like everything else.
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
			warn = true   # already dark, and he is still out there
	dusk_warning_label.visible = warn
	if not warn:
		return
	if _day_night.is_day:
		dusk_warning_label.text = "The light is going — %s of it left, and you are %s from home." % [
			TravelLog._fmt(left), _cells_home_text()]
	else:
		dusk_warning_label.text = "It is dark, and you are %s from home." % _cells_home_text()

func _cells_home_text() -> String:
	if _world_map == null or _villain == null:
		return "a way"
	var lair: Vector2 = _world_map.cell_centre_px(
		_world_map.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2))
	return "%d cells" % roundi(lair.distance_to(_villain.position) / float(WorldMap.CELL_SIZE))
	if _minimap:
		_minimap.queue_redraw()

## Follow on: bright. Follow off: dim, and it names the key that brings it back.
func refresh_follow_state() -> void:
	if follow_state_label == null or _villain_controller == null:
		return
	follow_state_label.text = _villain_controller.follow_status_text()
	follow_state_label.modulate = (Color(0.75, 0.90, 0.75)
		if _villain_controller.following else Color(1, 1, 1, 0.45))

func refresh_stats() -> void:
	var home_hp_str := ""
	var main_building := _settlement.get_main_building() if _settlement else null
	if main_building:
		home_hp_str = "   Throne: %d/%d hp" % [main_building.hp, main_building.max_hp]
	# Mundane resources first, in the order the foundation loop cares about
	# them (Wood/Stone build, Bones raise workers, Food feeds living recruits).
	# Dark Essence trails behind its icon -- locked at 0 for the whole
	# foundation build, but visible as the roadmap promise that Stage 4
	# unlocks it.
	# Gold joined the strip with the lootable sites (LOOT_SITES_SPEC section 5).
	# It sits with the other mundane resources rather than beside Dark Essence,
	# because to the player it is one more number that goes up when he comes
	# home -- that both of them are field-only is a design rule, not a layout.
	var left: String = "Wood: %d   Stone: %d   Bones: %d   Food: %d   Gold: %d" % [
		GameState.wood, GameState.stone, GameState.bones, GameState.food, GameState.gold]
	# Arms only once he has some: it is a dead end until COMBAT_SPEC §9's gear v1
	# (LOOT_SITES ruling 2), and a permanently-zero counter earns no strip space.
	if GameState.arms > 0:
		left += "   Arms: %d" % GameState.arms
	lbl_resources_left.text = left
	if lbl_dark_essence:
		lbl_dark_essence.text = str(GameState.dark_essence)
	var clock_str := "%s   " % _day_night.phase_label() if _day_night else ""
	lbl_resources_right.text = "%sThreat: %d (tier %d)   Power: %d%s" % [
		clock_str, GameState.threat, GameState.threat_tier, GameState.power, home_hp_str
	]
	if time_scale_btn and _day_night:
		time_scale_btn.text = _day_night.time_scale_label()

func _on_time_scale_pressed() -> void:
	var scale: float = _day_night.cycle_time_scale()
	refresh_stats()
	debug_speed_changed.emit(scale)
