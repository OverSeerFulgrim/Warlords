extends Node2D
## Wires up all the systems for the Undead Empire vertical-slice prototype.
##
## The settlement view (grid, buildings, follower tokens) is a real Node2D
## scene viewed through a pan/zoom Camera2D -- that part is the actual game
## view, not a placeholder. The stats/buttons/log are a HUD overlay built in
## code (no hand-authored .tscn UI layout, to keep the scene file itself
## trivial and low-risk -- see CLAUDE.md), kept deliberately thin now so the
## settlement underneath is what you're actually looking at.
##
## UI layout (rewritten from the original single top-strip debug UI): a thin
## resource bar along the very top, a clickable Necromancer badge + rolling
## alert stack, and a bottom command bar with Town/History/Research "folder"
## tabs attached above it. This shape was worked out in a separate design
## mockup pass with the user (bottom-bar layout inspired by Stronghold
## Crusader / Majesty / Age of Empires / Against the Storm / RimWorld) before
## being coded here -- see the conversation history / Necromancer_Reference.md
## for that design context. This pass is UI-only: it reorganizes and restyles
## every existing action/button into the new layout without changing what any
## of them actually do. Building click-info-popups, blocking movement through
## buildings, and population caps are explicitly NOT part of this pass.

var settlement: SettlementGrid
var bounty_board: BountyBoard
var threat_system: ThreatSystem
var event_system: EventSystem
var mission_system: MissionSystem
var worker_system: WorkerSystem
var resource_field: ResourceField
var day_night: DayNightCycle
var camera: GameCamera

var current_event: Dictionary = {}
var event_panel: PanelContainer

# ---------------- Top resource bar ----------------
var top_panel: PanelContainer  # kept so menus below can size themselves off its actual height
var lbl_resources_left: Label
var lbl_resources_right: Label
var time_scale_btn: Button
var necro_badge: Button

# ---------------- Alerts + history log (Town/History/Research tabs) ----------------
var alert_stack: VBoxContainer
var history_log_list: VBoxContainer
var history_filter_buttons: Dictionary = {}    # category String -> Button
var history_active_filters: Dictionary = {}    # category String -> bool

# ---------------- Bottom command bar: info panel, folder tabs, category tabs ----------------
var info_name_label: Label
var info_class_label: Label
var info_status_label: Label
var town_tab_btn: Button
var history_tab_btn: Button
var research_tab_btn: Button
var cmd_town: VBoxContainer
var cmd_history: VBoxContainer
var cmd_research: Control
var bar_panel: PanelContainer      # the command bar body -- hidden/shown by the collapse arrow
var collapse_tab_btn: Button       # sits left of the Town tab; toggles bar_panel.visible
var build_tab_btn: Button
var bounty_tab_btn: Button
var economy_tab_btn: Button
var build_row: HBoxContainer
var bounty_row: HBoxContainer
var economy_row: VBoxContainer
var workers_row: VBoxContainer     # holds the priority list + workforce summary
var workforce_label: Label
var map_stock_label: Label
var priority_status_labels: Dictionary = {}  # kind String -> Label

# ---------------- Build menu / click-to-place ----------------
var build_hint_label: Label
var _pending_building_id: String = ""  # "" = not in placement mode

# ---------------- Demolish mode (Town > Build row) ----------------
# Player-facing removal, distinct from any hidden dev/testing tooling. Reuses
# the placement-mode click-to-target UX, inverted: toggle the mode, then
# click an existing building on the map to remove it. No resource refund
# (confirmed with the user) -- SettlementGrid.remove_building() already
# refuses the main building; see _try_demolish().
var demolish_tab_btn: Button
var _demolish_mode: bool = false

# ---------------- Keep menu (click the main building) ----------------
var keep_menu_panel: PanelContainer

# ---------------- Barracks panel (click the Barracks) ----------------
var barracks_panel: PanelContainer

# ---------------- Follower tokens (on-screen presence, see FollowerToken.gd) ----------------
var followers_layer: Node2D
var follower_tokens: Dictionary = {}  # Follower -> FollowerToken
var followers_idle_zone: Rect2
var followers_gate_point: Vector2

# ---------------- Worker tokens (see WorkerToken.gd) ----------------
# The map's resource nodes live in ResourceField now, not in a Dictionary of
# fixed marker positions here -- see _build_systems().
var workers_layer: Node2D
var worker_tokens: Dictionary = {}  # Worker -> WorkerToken
var worker_keep_zone: Rect2         # deposit point + idle-wander area around the main building

## Maps a Follower.species string to its portrait. Followers are RefCounted
## data objects (see Follower.gd header for why); FollowerToken is the actual
## on-screen stand-in spawned per follower, and this roster row in the HUD is
## a second, smaller use of the same portraits.
##
## Sourced from the "Characters" asset pack (res://Characters/Character - 128
## x 128/) -- hand-picked matches by look rather than any naming convention
## in the pack itself, since it's a generic RPG-portrait set, not a
## monster-specific one. Picks:
##   character_020 -- hooded, red-eyed figure -> Wraith
##   character_023 -- green tusked figure -> Orc
##   character_022 -- green hooded, pointed-eared figure -> Goblin
##   character_024 -- pale figure, ribcage visible on outfit -> Skeleton
##   character_036 -- pale/green-tinged figure with a wound -> Ghoul
const SPECIES_SPRITES := {
	"Skeleton": "res://Characters/Character - 128 x 128/character_024.png",
	"Ghoul": "res://Characters/Character - 128 x 128/character_036.png",
	"Wraith": "res://Characters/Character - 128 x 128/character_020.png",
	"Orc": "res://Characters/Character - 128 x 128/character_023.png",
	"Goblin": "res://Characters/Character - 128 x 128/character_022.png",
}

## The player's own portrait -- character_029 (black hood, pale gaunt face,
## dark robe with blood-red trim) picked from the same "Characters" pack
## during a reference/design pass (see Necromancer_Reference.md) as the
## strongest "this is the villain" read of the pack's 40 portraits, with no
## overlap against the species portraits above.
const NECROMANCER_SPRITE := "res://Characters/Character - 128 x 128/character_029.png"

## Stand-in portrait for any race without a hand-picked entry in
## SPECIES_SPRITES above -- which since the race roster landed is most of them
## (Gray Dwarf, Gnome, Minotaur, Halfling...). Picking per-race portraits out
## of the 40-portrait pack is an art pass, not this one; what matters here is
## that an unrecognised species still shows up on the map.
const FALLBACK_SPECIES_SPRITE := "res://Characters/Character - 128 x 128/character_001.png"

const INFO_PANEL_WIDTH := 170.0
const MINIMAP_SIZE := 78.0
const MAX_ALERTS := 3            # oldest alert pin is dropped once a 4th arrives
const MAX_HISTORY_ENTRIES := 200 # oldest history-log row is dropped past this cap

func _ready() -> void:
	set_process_unhandled_input(true)  # needed for build-menu click-to-place / Esc-cancel / unit selection
	_build_systems()
	_build_camera()
	_seed_starting_state()
	_build_ui()
	_connect_signals()
	_sync_follower_tokens()
	_sync_worker_tokens()
	_log("Undead Empire prototype started. Frozen Wastes climate (placeholder).")

## Worker states change continuously now that gathering is a real trip loop,
## so the priority rows' Working/Satisfied labels and the workforce summary
## are polled here rather than driven by a signal that would fire every frame
## regardless. Everything genuinely event-shaped (deposits, depletion, dawn)
## still goes through EventBus -- see _connect_signals().
func _process(_delta: float) -> void:
	_refresh_priority_status()

# ---------------- Systems ----------------

func _build_systems() -> void:
	settlement = SettlementGrid.new()
	settlement.name = "SettlementGrid"
	add_child(settlement)
	_build_ground_background()

	followers_layer = Node2D.new()
	followers_layer.name = "FollowersLayer"
	settlement.add_child(followers_layer)

	var grid_w: float = SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE
	var grid_h: float = SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE
	# A "town green" strip along the bottom of the grid, clear of the seeded
	# buildings up top -- where idle followers wander while not busy.
	followers_idle_zone = Rect2(
		Vector2(SettlementGrid.CELL_SIZE, grid_h - 2.5 * SettlementGrid.CELL_SIZE),
		Vector2(grid_w - 2.0 * SettlementGrid.CELL_SIZE, 2.0 * SettlementGrid.CELL_SIZE)
	)
	# Just off the west edge of the grid -- where tokens glide to/from when
	# their follower leaves on a bounty or mission.
	followers_gate_point = Vector2(-SettlementGrid.CELL_SIZE * 0.6, grid_h * 0.5)

	workers_layer = Node2D.new()
	workers_layer.name = "WorkersLayer"
	settlement.add_child(workers_layer)

	# The map's harvestable resources. A child of `settlement` so it shares the
	# same coordinate space workers walk in -- ResourceNode positions are the
	# literal destinations WorkerSystem measures distance against.
	resource_field = ResourceField.new()
	resource_field.name = "ResourceField"
	settlement.add_child(resource_field)
	resource_field.build(grid_w, grid_h)
	# Small ring around the main building's cell (0,0) -- where workers idle
	# between trips and where every load gets deposited.
	worker_keep_zone = Rect2(Vector2(-16, -16), Vector2(SettlementGrid.CELL_SIZE + 32, SettlementGrid.CELL_SIZE + 32))

	bounty_board = BountyBoard.new()
	bounty_board.name = "BountyBoard"
	add_child(bounty_board)

	threat_system = ThreatSystem.new()
	threat_system.name = "ThreatSystem"
	add_child(threat_system)
	threat_system.settlement = settlement  # Crusade resolution targets the main building

	event_system = EventSystem.new()
	event_system.name = "EventSystem"
	add_child(event_system)
	event_system.settlement = settlement  # housing hard-gate needs to query the grid

	mission_system = MissionSystem.new()
	mission_system.name = "MissionSystem"
	add_child(mission_system)

	worker_system = WorkerSystem.new()
	worker_system.name = "WorkerSystem"
	# Wired before add_child() so the trip loop has a map and a home the very
	# first frame it processes -- same set-fields-then-attach convention as
	# threat_system.settlement / event_system.settlement above.
	worker_system.resource_field = resource_field
	worker_system.keep_zone = worker_keep_zone
	worker_system.home_position = worker_keep_zone.get_center()
	add_child(worker_system)

	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	add_child(day_night)

func _build_camera() -> void:
	camera = GameCamera.new()
	camera.name = "GameCamera"
	var grid_w: float = SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE
	var grid_h: float = SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE
	camera.position = Vector2(grid_w * 0.5, grid_h * 0.5)
	camera.zoom = Vector2(0.72, 0.72)
	add_child(camera)
	camera.make_current()

func _build_ground_background() -> void:
	# Simple tiled ground so the grid isn't a void behind the buildings.
	# Lives as a child of `settlement` so it inherits the same offset.
	const GROUND_PATH := "res://art/tile_ground_frozen.png"
	if not ResourceLoader.exists(GROUND_PATH):
		return
	var tex := load(GROUND_PATH)
	for y in range(SettlementGrid.GRID_HEIGHT):
		for x in range(SettlementGrid.GRID_WIDTH):
			var tile := Sprite2D.new()
			tile.texture = tex
			tile.centered = false
			tile.position = Vector2(x * SettlementGrid.CELL_SIZE, y * SettlementGrid.CELL_SIZE)
			tile.z_index = -1  # always behind buildings
			settlement.add_child(tile)

## Stage 0 (Arrival) per FOUNDATION_SPEC section 10: the Throne of Bones, one
## Skeleton Worker, and nothing else. The Bone Pile and Dark Altar used to be
## seeded here too, and three followers (Grix/Morra/Vash) came free -- all
## removed so the run actually starts at the bottom of the Stage 1-3 ladder
## the outline describes (labor before buildings, buildings before followers).
## The Bone Pile is now the player's first build, not a gift; the Dark Altar is
## locked outright (Stage 4). Starting resource values live in GameState, not
## here.
func _seed_starting_state() -> void:
	# Main building: the player's home, seeded at a fixed anchor cell,
	# undeletable (see SettlementGrid.remove_building), and the Crusade's
	# actual target -- see ThreatSystem._resolve_crusade().
	_place_from_catalog("throne_of_bones", Vector2i(0, 0))

	# One free Skeleton Worker to start, left idle -- the player chooses its
	# first assignment rather than it silently already gathering something,
	# since this is a brand-new mechanic worth surfacing deliberately.
	worker_system.add_worker(Worker.new("Skeleton Worker #1"))

## Places a catalog building directly (no cost check, no player-driven
## click-to-place) -- used only for game-start seeding. Player construction
## goes through the build menu / _try_place_pending() instead.
func _place_from_catalog(id: String, cell: Vector2i) -> void:
	var data: Dictionary = BuildingCatalog.get_building(id)
	if data.is_empty():
		push_warning("Main: unknown building_id '%s' in _seed_starting_state" % id)
		return
	settlement.place_building(Building.make_from_data(id, data), cell)

# ---------------- Follower tokens (on-screen presence) ----------------

## Reconciles follower_tokens against GameState.followers: spawns a token for
## any follower that doesn't have one yet, despawns any token whose follower
## is gone (removed, captured, etc). Called on follower_count_changed.
func _sync_follower_tokens() -> void:
	for f in GameState.followers:
		if not follower_tokens.has(f):
			_spawn_token(f)
	for f in follower_tokens.keys().duplicate():
		if not GameState.followers.has(f):
			_despawn_token(f)

func _spawn_token(follower) -> void:
	var token := FollowerToken.new()
	followers_layer.add_child(token)
	# SPECIES_SPRITES only covers the five original undead/monster species. The
	# race roster is 16 and growing, so anything without a hand-picked portrait
	# falls back to a generic one rather than spawning an invisible token --
	# which is what a missing texture would silently do.
	var sprite_path: String = SPECIES_SPRITES.get(follower.species, FALLBACK_SPECIES_SPRITE)
	var tex: Texture2D = null
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		tex = load(sprite_path)
	token.setup(follower, tex, followers_gate_point)
	follower_tokens[follower] = token

func _despawn_token(follower) -> void:
	var token: FollowerToken = follower_tokens.get(follower)
	if token:
		token.queue_free()
	follower_tokens.erase(follower)

func _send_token_away(follower) -> void:
	if follower_tokens.has(follower):
		follower_tokens[follower].send_away()

func _return_token_home(follower) -> void:
	if follower_tokens.has(follower):
		follower_tokens[follower].return_home()

# ---------------- Worker tokens (on-screen presence) ----------------

## Same reconcile pattern as _sync_follower_tokens() -- spawns a token for
## any Worker that doesn't have one yet, despawns any orphaned token.
func _sync_worker_tokens() -> void:
	for w in worker_system.workers:
		if not worker_tokens.has(w):
			_spawn_worker_token(w)
	for w in worker_tokens.keys().duplicate():
		if not worker_system.workers.has(w):
			_despawn_worker_token(w)

func _spawn_worker_token(worker) -> void:
	var token := WorkerToken.new()
	workers_layer.add_child(token)
	# Workers are the plain/generic labor unit -- reuse the Skeleton
	# Follower portrait as a stand-in "undead laborer" look rather than
	# commissioning a distinct sprite for a unit type that's deliberately
	# meant to read as interchangeable, not individual. (Confirmed again
	# during the UI design pass: kept deliberately as-is.)
	var sprite_path: String = SPECIES_SPRITES.get("Skeleton", "")
	var tex: Texture2D = null
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		tex = load(sprite_path)
	token.setup(worker, tex)
	worker_tokens[worker] = token

func _despawn_worker_token(worker) -> void:
	var token: WorkerToken = worker_tokens.get(worker)
	if token:
		token.queue_free()
	worker_tokens.erase(worker)

# ---------------- UI (built in code on purpose -- see file header) ----------------

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var hud_root := Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_root)

	_build_top_bar(hud_root)
	_build_necro_badge(hud_root)
	_build_alert_stack(hud_root)
	_build_placement_hint(hud_root)
	_build_event_panel(hud_root)
	_build_keep_menu(hud_root)
	_build_bottom_shell(hud_root)

	_update_stats_label()
	_populate_build_row()
	_build_priority_rows()
	_select_folder_tab("town")
	_select_category_tab("build")

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.78)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

## Thin single-row resource strip along the very top: Dark Essence/Wood/
## Stone/Bones on the left, Threat/Power/Throne hp on the right, matching the
## design-mockup pass. No per-resource icons yet (the art pack has icons for
## some resources but not all -- see Necromancer_Reference.md -- so text-only
## for now to avoid a mismatched partial icon set; a follow-up art pass can
## add them once the layout itself is confirmed live in-editor).
func _build_top_bar(hud_root: Control) -> void:
	top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.add_theme_stylebox_override("panel", _panel_style())
	hud_root.add_child(top_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	top_panel.add_child(row)

	lbl_resources_left = Label.new()
	lbl_resources_left.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl_resources_left)

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

## Clickable player portrait, top-left under the resource bar. There's no
## real player data model yet (no stats, no busy-state) -- clicking it always
## reports "Idle" for now; see Necromancer_Reference.md's open question about
## what this should eventually grow into (spells panel? on-map token?).
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
	necro_badge.pressed.connect(func(): _select_info("The Necromancer", "Necromancer", "Idle"))
	hud_root.add_child(necro_badge)

## Rolling stack of up to MAX_ALERTS recent notable events, top-right,
## opposite the necromancer badge. Each pin's full message is its
## tooltip_text (hover to read) rather than a click-to-reveal panel, since
## Godot buttons already do that natively. See _alert().
func _build_alert_stack(hud_root: Control) -> void:
	alert_stack = VBoxContainer.new()
	alert_stack.add_theme_constant_override("separation", 4)
	alert_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	alert_stack.position = Vector2(-40, 40)
	hud_root.add_child(alert_stack)

func _build_placement_hint(hud_root: Control) -> void:
	build_hint_label = Label.new()
	build_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	build_hint_label.position = Vector2(10, 88)
	build_hint_label.add_theme_font_size_override("font_size", 12)
	build_hint_label.visible = false
	hud_root.add_child(build_hint_label)

func _build_event_panel(hud_root: Control) -> void:
	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_CENTER)
	event_panel.custom_minimum_size = Vector2(280, 0)
	event_panel.add_theme_stylebox_override("panel", _panel_style())
	event_panel.visible = false
	hud_root.add_child(event_panel)

func _build_keep_menu(hud_root: Control) -> void:
	keep_menu_panel = PanelContainer.new()
	keep_menu_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	keep_menu_panel.position = Vector2(360, 96)
	keep_menu_panel.add_theme_stylebox_override("panel", _panel_style())
	keep_menu_panel.visible = false
	hud_root.add_child(keep_menu_panel)

	barracks_panel = PanelContainer.new()
	barracks_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	barracks_panel.position = Vector2(360, 96)
	barracks_panel.add_theme_stylebox_override("panel", _panel_style())
	barracks_panel.visible = false
	hud_root.add_child(barracks_panel)

## The bottom command bar itself, plus the Town/History/Research "folder"
## tabs attached directly above it -- positioned above the command column
## specifically (not the info panel, not the full screen width), per explicit
## back-and-forth with the user in the design-mockup pass.
func _build_bottom_shell(hud_root: Control) -> void:
	var bottom_shell := VBoxContainer.new()
	bottom_shell.add_theme_constant_override("separation", 0)
	bottom_shell.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# set_anchors_preset() alone pins both the top and bottom edges of this
	# container to the same line (the screen's bottom), giving it zero
	# height -- nothing inside it can render until an explicit offset claims
	# actual screen space. Same fix pattern the original code already used
	# for the old log_panel (a hardcoded negative position.y). 190px is
	# generous enough for the folder tabs row plus the tallest command-bar
	# content (Economy's two stacked action rows); a few px of slack if the
	# real content ends up shorter is harmless.
	bottom_shell.offset_top = -190
	bottom_shell.offset_bottom = 0
	bottom_shell.offset_left = 0
	bottom_shell.offset_right = 0
	hud_root.add_child(bottom_shell)

	var folder_tabs_row := HBoxContainer.new()
	folder_tabs_row.add_theme_constant_override("separation", 3)

	# Collapse arrow, left of the Town tab. Down-arrow while expanded (click
	# to collapse), flips to an up-arrow once collapsed (click to bring the
	# command bar back). Only bar_panel hides/shows -- the tabs themselves
	# (including this button) stay visible either way.
	collapse_tab_btn = Button.new()
	collapse_tab_btn.text = "▼"
	collapse_tab_btn.tooltip_text = "Collapse the command bar"
	collapse_tab_btn.pressed.connect(_toggle_bottom_bar_collapsed)
	folder_tabs_row.add_child(collapse_tab_btn)

	# Spacer pushes the Town/History/Research tabs to start above the command
	# area rather than the info panel -- width is an approximation of
	# info-panel-width + the separator/margins next to it; nudge if it looks
	# off once seen live.
	var tab_spacer := Control.new()
	tab_spacer.custom_minimum_size = Vector2(INFO_PANEL_WIDTH + 20, 0)
	folder_tabs_row.add_child(tab_spacer)

	town_tab_btn = Button.new()
	town_tab_btn.text = "Town"
	history_tab_btn = Button.new()
	history_tab_btn.text = "History"
	research_tab_btn = Button.new()
	research_tab_btn.text = "Research"
	town_tab_btn.pressed.connect(func(): _select_folder_tab("town"))
	history_tab_btn.pressed.connect(func(): _select_folder_tab("history"))
	research_tab_btn.pressed.connect(func(): _select_folder_tab("research"))
	folder_tabs_row.add_child(town_tab_btn)
	folder_tabs_row.add_child(history_tab_btn)
	folder_tabs_row.add_child(research_tab_btn)
	bottom_shell.add_child(folder_tabs_row)

	bar_panel = PanelContainer.new()
	bar_panel.custom_minimum_size = Vector2(0, 100)
	# Expand to fill whatever space is left in bottom_shell's fixed 190px
	# band after folder_tabs_row takes its own height, instead of stopping at
	# the 100px minimum and leaving a gap of bare background below it.
	bar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_panel.add_theme_stylebox_override("panel", _panel_style())
	bottom_shell.add_child(bar_panel)

	var bar_hbox := HBoxContainer.new()
	bar_panel.add_child(bar_hbox)

	# Info panel: shows whatever was last clicked -- a Follower, a Worker, the
	# Necromancer badge, or the Throne of Bones. See _select_info() and the
	# token-hit-testing added to _unhandled_input().
	var info_panel := VBoxContainer.new()
	info_panel.custom_minimum_size = Vector2(INFO_PANEL_WIDTH, 0)
	info_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	info_name_label = Label.new()
	info_name_label.text = "Nothing selected"
	info_name_label.add_theme_font_size_override("font_size", 15)
	info_panel.add_child(info_name_label)
	info_class_label = Label.new()
	info_class_label.text = "Click a unit or the Keep"
	info_class_label.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(info_class_label)
	info_status_label = Label.new()
	info_status_label.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(info_status_label)
	bar_hbox.add_child(info_panel)

	bar_hbox.add_child(VSeparator.new())

	var command_area := VBoxContainer.new()
	command_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_hbox.add_child(command_area)

	_build_cmd_town(command_area)
	_build_cmd_history(command_area)
	_build_cmd_research(command_area)

	bar_hbox.add_child(VSeparator.new())

	var minimap_box := ColorRect.new()
	minimap_box.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap_box.color = Color(0.09, 0.11, 0.15)
	# Purely a visual placeholder for now -- no actual minimap rendering.
	bar_hbox.add_child(minimap_box)

## Town tab content: the Build/Bounty/Economy category tabs plus each one's
## row of actions. Originally folded in every action button the old top-strip
## debug UI had (Build, Recruit Worker, Forge Equipment, Train Followers, both
## bounty posts, Dispatch Mission, Lay Low). The foundation reset then pulled
## the four Stage-4 ones (both bounty posts, Forge Equipment, Train Followers)
## plus Dispatch Mission back out of the UI -- see the comments inline below
## and CLAUDE.md's "Foundation reset" section; the code behind them is intact.
func _build_cmd_town(command_area: VBoxContainer) -> void:
	cmd_town = VBoxContainer.new()
	command_area.add_child(cmd_town)

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 4)
	cmd_town.add_child(category_row)
	build_tab_btn = Button.new()
	build_tab_btn.text = "Build"
	bounty_tab_btn = Button.new()
	bounty_tab_btn.text = "Bounty"
	economy_tab_btn = Button.new()
	economy_tab_btn.text = "Economy"
	build_tab_btn.pressed.connect(func(): _select_category_tab("build"))
	bounty_tab_btn.pressed.connect(func(): _select_category_tab("bounty"))
	economy_tab_btn.pressed.connect(func(): _select_category_tab("economy"))
	category_row.add_child(build_tab_btn)
	category_row.add_child(bounty_tab_btn)
	category_row.add_child(economy_tab_btn)

	# Build: was a separate popup menu (build_menu_panel) toggled by a
	# "Build..." button; now an inline row of buildable entries, refreshed by
	# _populate_build_row() whenever the settlement changes (a new Workshop
	# can unlock Blacksmith/Barracks appearing here).
	build_row = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 6)
	cmd_town.add_child(build_row)

	# Bounty tab: the two Post Bounty buttons are hard-locked for the
	# foundation build (Stage 4 -- see GAME_OUTLINE). The tab itself stays,
	# showing a locked placeholder rather than vanishing, same "visible promise
	# of the roadmap" treatment FOUNDATION_SPEC section 9 asks for on the
	# Barracks Upgrade button and the Research tab already uses. BountyBoard /
	# Bounty are still constructed and wired -- nothing calls them from the UI.
	bounty_row = HBoxContainer.new()
	bounty_row.add_theme_constant_override("separation", 6)
	cmd_town.add_child(bounty_row)
	_add_locked_placeholder(bounty_row, "Bounty board -- unlocks in Stage 4")

	economy_row = VBoxContainer.new()
	cmd_town.add_child(economy_row)
	var economy_actions := HBoxContainer.new()
	economy_actions.add_theme_constant_override("separation", 6)
	economy_row.add_child(economy_actions)
	_add_button(economy_actions, "Recruit Worker (5 Bones)", _recruit_worker)
	# Forge Equipment, Train Followers and Dispatch Mission are hard-locked
	# alongside the bounty board -- all three are Stage 4. Their handlers
	# (_forge_equipment/_train_followers/_dispatch_random_mission) and
	# MissionSystem are deliberately left intact and unreferenced, so
	# re-surfacing them at Stage 4 is one _add_button() line each.
	_add_button(economy_actions, "Lay Low", func(): GameState.lay_low())

	# The global resource priority list -- replaces the per-worker "click to
	# cycle Idle/Wood/Stone/Bones" buttons that used to sit here. See
	# _build_priority_rows() for the layout and WorkerSystem's `priorities`
	# for what the numbers mean.
	workers_row = VBoxContainer.new()
	workers_row.add_theme_constant_override("separation", 2)
	economy_row.add_child(workers_row)

## History tab content: Events/Alerts/Characters filter chips above a
## scrollable log. Replaces the old always-visible bottom-left log panel --
## every _log() call still fires, it just lands here instead.
func _build_cmd_history(command_area: VBoxContainer) -> void:
	cmd_history = VBoxContainer.new()
	cmd_history.visible = false
	command_area.add_child(cmd_history)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	cmd_history.add_child(filter_row)
	for cat in ["events", "alerts", "characters"]:
		var c: String = cat  # explicit re-bind for the closure below, same pattern used elsewhere in this file
		var fb := Button.new()
		fb.text = c.capitalize()
		fb.toggle_mode = true
		fb.toggled.connect(func(pressed: bool): _on_history_filter_toggled(c, pressed))
		history_filter_buttons[c] = fb
		filter_row.add_child(fb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 56)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cmd_history.add_child(scroll)
	history_log_list = VBoxContainer.new()
	history_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(history_log_list)

## Research tab content: a placeholder, per the user's explicit "empty tab
## that says 'Future roadmap goal'" instruction during the mockup pass.
func _build_cmd_research(command_area: VBoxContainer) -> void:
	cmd_research = CenterContainer.new()
	cmd_research.visible = false
	command_area.add_child(cmd_research)
	var lbl := Label.new()
	lbl.text = "Future roadmap goal"
	lbl.modulate = Color(1, 1, 1, 0.5)
	cmd_research.add_child(lbl)

# ---------------- Folder tabs (Town/History/Research) ----------------

func _folder_tab_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Active tab's background matches the command bar panel below it so the
	# two visually fuse into one shape -- the classic "folder tab" look this
	# was explicitly asked for in the design-mockup pass.
	style.bg_color = Color(0.05, 0.05, 0.08, 0.78) if active else Color(0.03, 0.03, 0.05, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _restyle_folder_tab(btn: Button, active: bool) -> void:
	var style := _folder_tab_style(active)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75) if active else Color(0.55, 0.57, 0.63))

func _select_folder_tab(tab: String) -> void:
	cmd_town.visible = tab == "town"
	cmd_history.visible = tab == "history"
	cmd_research.visible = tab == "research"
	_restyle_folder_tab(town_tab_btn, tab == "town")
	_restyle_folder_tab(history_tab_btn, tab == "history")
	_restyle_folder_tab(research_tab_btn, tab == "research")

## Hides/shows the command bar body (info panel, Build/Bounty/Economy or
## History/Research content, minimap) while leaving the folder tabs row --
## and this button itself -- always visible and clickable, so collapsing
## never traps the player without a way back.
func _toggle_bottom_bar_collapsed() -> void:
	bar_panel.visible = not bar_panel.visible
	if bar_panel.visible:
		collapse_tab_btn.text = "▼"
		collapse_tab_btn.tooltip_text = "Collapse the command bar"
	else:
		collapse_tab_btn.text = "▲"
		collapse_tab_btn.tooltip_text = "Expand the command bar"

# ---------------- Category tabs (Build/Bounty/Economy) ----------------

func _restyle_category_tab(btn: Button, active: bool) -> void:
	btn.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3) if active else Color(0.8, 0.8, 0.8))

func _select_category_tab(tab: String) -> void:
	build_row.visible = tab == "build"
	bounty_row.visible = tab == "bounty"
	economy_row.visible = tab == "economy"
	_restyle_category_tab(build_tab_btn, tab == "build")
	_restyle_category_tab(bounty_tab_btn, tab == "bounty")
	_restyle_category_tab(economy_tab_btn, tab == "economy")

# ---------------- Unit/building selection info panel ----------------

func _select_info(unit_name: String, klass: String, status: String) -> void:
	info_name_label.text = unit_name
	info_class_label.text = klass
	info_status_label.text = status

## The global resource priority list (GAME_OUTLINE Stage 1). One row per
## resource, ranked top-to-bottom, each with reorder arrows and a threshold
## spinner:
##
##     [^][v]  Wood    stop at [ 30 ]   Working
##     [^][v]  Stone   stop at [ 20 ]   Satisfied
##
## Workers serve the highest row whose stock is under its threshold; at or
## above it, that row is satisfied and they fall through to the next. This
## deliberately replaces per-worker assignment -- you set policy, the workforce
## sorts itself out, which is the "indirect control" design pillar applied to
## labor. Rebuilt wholesale on EventBus.priorities_changed rather than
## patched in place; four rows is far too little to bother diffing.
func _build_priority_rows() -> void:
	if not workers_row:
		return
	for child in workers_row.get_children():
		child.queue_free()
	priority_status_labels.clear()

	var header := Label.new()
	header.text = "Gathering priorities  (workers serve the top resource still under its threshold)"
	header.add_theme_font_size_override("font_size", 10)
	header.modulate = Color(1, 1, 1, 0.6)
	workers_row.add_child(header)

	for i in range(worker_system.priorities.size()):
		var entry: Dictionary = worker_system.priorities[i]
		var kind: String = entry["kind"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var up := Button.new()
		up.text = "^"
		up.tooltip_text = "Raise %s priority" % kind
		up.disabled = i == 0
		up.pressed.connect(func(): worker_system.move_priority(kind, -1))
		row.add_child(up)

		var down := Button.new()
		down.text = "v"
		down.tooltip_text = "Lower %s priority" % kind
		down.disabled = i == worker_system.priorities.size() - 1
		down.pressed.connect(func(): worker_system.move_priority(kind, 1))
		row.add_child(down)

		var name_label := Label.new()
		name_label.text = "%d. %s" % [i + 1, kind.capitalize()]
		name_label.custom_minimum_size = Vector2(78, 0)
		row.add_child(name_label)

		var stop_label := Label.new()
		stop_label.text = "stop at"
		stop_label.add_theme_font_size_override("font_size", 11)
		stop_label.modulate = Color(1, 1, 1, 0.6)
		row.add_child(stop_label)

		# A real SpinBox rather than the codebase's usual +/- button pair:
		# thresholds are an arbitrary number the player types, not a small
		# fixed choice set, which is exactly the case the button-pair
		# convention doesn't cover.
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999
		spin.step = 5
		spin.value = entry["threshold"]
		spin.custom_minimum_size = Vector2(72, 0)
		spin.value_changed.connect(func(v: float): worker_system.set_threshold(kind, int(v)))
		row.add_child(spin)

		var status := Label.new()
		status.add_theme_font_size_override("font_size", 11)
		priority_status_labels[kind] = status
		row.add_child(status)

		workers_row.add_child(row)

	workforce_label = Label.new()
	workforce_label.add_theme_font_size_override("font_size", 11)
	workers_row.add_child(workforce_label)

	map_stock_label = Label.new()
	map_stock_label.add_theme_font_size_override("font_size", 10)
	map_stock_label.modulate = Color(1, 1, 1, 0.55)
	workers_row.add_child(map_stock_label)

	_refresh_priority_status()

## Per-row Working/Satisfied/None-left text plus the workforce and map-stock
## summaries. Cheap enough to run every frame from _process -- the trip loop
## changes worker states continuously, so there's no useful signal to hang
## this on that wouldn't just fire constantly anyway.
func _refresh_priority_status() -> void:
	for kind in priority_status_labels.keys():
		var lbl: Label = priority_status_labels[kind]
		var status: String = worker_system.priority_status(kind)
		lbl.text = status
		match status:
			"Working":
				lbl.modulate = Color(0.6, 0.9, 0.6)
			"Satisfied":
				lbl.modulate = Color(0.7, 0.7, 0.7)
			"None left":
				lbl.modulate = Color(0.95, 0.6, 0.5)
			_:
				lbl.modulate = Color(1, 1, 1)
	if workforce_label:
		workforce_label.text = worker_system.workforce_summary()
	if map_stock_label and resource_field:
		map_stock_label.text = resource_field.stock_summary()

func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)

## A greyed, non-interactive stand-in for a roadmap-locked action -- a Label,
## not a disabled Button, so there's nothing to click and no implied "this
## would work if you met some hidden requirement". Matches the Research tab's
## "Future roadmap goal" placeholder and the Keep menu's "Upgrades -- coming
## soon" line.
func _add_locked_placeholder(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = Color(1, 1, 1, 0.5)
	parent.add_child(lbl)

## Refreshes the Build tab's inline row of buildable entries. Called once at
## startup and again whenever a building is placed (a new Workshop can unlock
## Blacksmith/Barracks appearing here, per BuildingCatalog's `requires` gate).
func _populate_build_row() -> void:
	if not build_row:
		return
	for child in build_row.get_children():
		child.queue_free()
	var ids: Array = BuildingCatalog.buildable_ids(settlement)
	if ids.is_empty():
		var lbl := Label.new()
		lbl.text = "(nothing available)"
		build_row.add_child(lbl)
	else:
		for id in ids:
			var bid: String = id  # explicit re-bind for the closure below, same pattern used elsewhere in this file
			var data: Dictionary = BuildingCatalog.get_building(bid)
			var cost_str := _format_cost(data.get("cost", {}))
			var b := Button.new()
			b.text = data.get("display_name", bid)
			b.tooltip_text = cost_str if cost_str != "" else "free"
			b.pressed.connect(func(): _enter_placement_mode(bid))
			build_row.add_child(b)

	# Demolish sits at the end of the row, separated from the buildable list,
	# so it doesn't read as just another thing to build. Toggle button, not a
	# one-shot action -- pressing it enters demolish mode; the actual removal
	# happens on the next map click (see _try_demolish()).
	build_row.add_child(VSeparator.new())
	demolish_tab_btn = Button.new()
	demolish_tab_btn.text = "Demolish"
	demolish_tab_btn.tooltip_text = "Click, then select a building on the map to remove it. No resource refund."
	demolish_tab_btn.pressed.connect(_toggle_demolish_mode)
	build_row.add_child(demolish_tab_btn)
	_restyle_demolish_button()

func _format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for kind in cost.keys():
		parts.append("%d %s" % [cost[kind], kind])
	return ", ".join(parts)

func _enter_placement_mode(building_id: String) -> void:
	if _demolish_mode:
		_toggle_demolish_mode()  # the two click-to-target modes are mutually exclusive
	_pending_building_id = building_id
	var data: Dictionary = BuildingCatalog.get_building(building_id)
	build_hint_label.text = "Placing %s -- click an empty tile (Esc to cancel)" % data.get("display_name", building_id)
	build_hint_label.visible = true

func _cancel_placement() -> void:
	_pending_building_id = ""
	build_hint_label.visible = false

## Toggles demolish mode on/off. Cancels any pending placement first (the two
## click-to-target modes can't both be active), and restyles the Demolish
## button so it's visually obvious the mode is armed.
func _toggle_demolish_mode() -> void:
	if _pending_building_id != "":
		_cancel_placement()
	_demolish_mode = not _demolish_mode
	_restyle_demolish_button()
	if _demolish_mode:
		build_hint_label.text = "Demolishing -- click a building to remove it (Esc to cancel)"
		build_hint_label.visible = true
	else:
		build_hint_label.visible = false

func _restyle_demolish_button() -> void:
	if not demolish_tab_btn:
		return
	demolish_tab_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if _demolish_mode else Color(0.85, 0.6, 0.6))

## Removes whatever's on `cell`, if anything. Mirrors _try_place_pending()'s
## shape: empty tile clicked -> silently stay in demolish mode (no message
## needed, same as clicking an occupied tile during placement); building
## found -> remove it via SettlementGrid.remove_building(), which already
## refuses the main building (Throne of Bones) -- surfaced here as a log +
## alert rather than a silent no-op. No resource refund, per explicit user
## confirmation. Exits demolish mode after a successful removal, same as
## placement mode exiting after a successful build.
func _try_demolish(cell: Vector2i) -> void:
	if not settlement.cells.has(cell):
		return
	var building: Building = settlement.cells[cell]
	if building.is_main_building:
		_log("[color=orange]The %s can't be demolished.[/color]" % building.display_name, "alerts")
		_alert("The %s can't be demolished." % building.display_name, "warn")
		return
	var demolished_name := building.display_name
	if settlement.remove_building(cell):
		_log("Demolished %s at %s." % [demolished_name, cell], "events")
	_toggle_demolish_mode()

func _unhandled_input(event: InputEvent) -> void:
	if _pending_building_id != "":
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos: Vector2 = settlement.get_global_mouse_position()
			var cell: Vector2i = settlement.cell_from_world(world_pos)
			_try_place_pending(cell)
			get_viewport().set_input_as_handled()
		return

	if _demolish_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_toggle_demolish_mode()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos: Vector2 = settlement.get_global_mouse_position()
			var cell: Vector2i = settlement.cell_from_world(world_pos)
			_try_demolish(cell)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world_pos: Vector2 = settlement.get_global_mouse_position()

		# Free-roaming tokens (Followers/Workers) aren't cell-locked, so check
		# proximity to their current on-screen position rather than a grid
		# cell -- see _closest_token_hit(). Checked before the main-building
		# cell check below since a token can wander over any part of the grid.
		var hit_follower: Follower = _closest_token_hit(follower_tokens, world_pos, 20.0)
		if hit_follower:
			_select_info(hit_follower.label(), "%s — %s" % [hit_follower.species, hit_follower.category],
				"Busy" if hit_follower.is_busy else hit_follower.status_label())
			get_viewport().set_input_as_handled()
			return
		var hit_worker: Worker = _closest_token_hit(worker_tokens, world_pos, 16.0)
		if hit_worker:
			_select_info(hit_worker.worker_name, "Skeleton Worker", hit_worker.status_label())
			get_viewport().set_input_as_handled()
			return

		# Not in placement mode, no token hit: a left-click landing on the main
		# building's cell selects it and opens the Keep menu instead. Checked
		# here (rather than giving Building its own click detection/Area2D) to
		# keep click-handling centralized in one place alongside the
		# build-placement clicks it has to coexist with.
		var cell: Vector2i = settlement.cell_from_world(world_pos)
		var main_building := settlement.get_main_building()
		if main_building and cell == main_building.cell:
			_select_info(main_building.display_name, "Main building", "%d/%d hp" % [main_building.hp, main_building.max_hp])
			_toggle_keep_menu()
			get_viewport().set_input_as_handled()
			return

		# Clicking the Barracks opens its resident roster -- same
		# click-the-building-on-the-map pattern as the Keep menu above.
		var barracks := settlement.get_barracks()
		if barracks and cell == barracks.cell:
			_select_info(barracks.display_name, "Recruit intake",
				"%d/%d residents" % [settlement.barracks_residents(), settlement.barracks_capacity()])
			_toggle_barracks_panel()
			get_viewport().set_input_as_handled()

## Shared proximity hit-test for both follower_tokens and worker_tokens --
## Followers/Workers wander freely (Tween-driven, not grid-locked), so this
## checks distance to each token's current position rather than a grid cell.
## Returns the Follower/Worker key whose token is closest and within radius,
## or null if nothing qualified.
func _closest_token_hit(tokens: Dictionary, world_pos: Vector2, radius: float):
	var best = null
	var best_dist := radius
	for key in tokens.keys():
		var token: Node2D = tokens[key]
		var d: float = token.position.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best = key
	return best

func _toggle_keep_menu() -> void:
	keep_menu_panel.visible = not keep_menu_panel.visible
	if keep_menu_panel.visible:
		keep_menu_panel.position.y = _menu_open_y()
		_populate_keep_menu()

## Returns the y-coordinate just below the top resource bar's actual current
## height, with a small margin -- used to position keep_menu_panel each time
## it opens, rather than a hardcoded number.
func _menu_open_y() -> float:
	return top_panel.size.y + 12.0

func _populate_keep_menu() -> void:
	for child in keep_menu_panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	keep_menu_panel.add_child(box)

	var title := Label.new()
	title.text = "The Keep"
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)

	_add_button(box, "Recruit Worker (5 Bones)", _recruit_worker)

	# Not a real feature yet -- a visible placeholder so clicking the Keep
	# already shows where building upgrades will eventually live, per the
	# "possibly get upgrades down the road" design note, rather than that
	# needing a whole new menu discovered from scratch later.
	var upgrades_label := Label.new()
	upgrades_label.text = "Upgrades -- coming soon"
	upgrades_label.modulate = Color(1, 1, 1, 0.5)
	box.add_child(upgrades_label)

	_add_button(box, "Close", func(): keep_menu_panel.visible = false)

# ---------------- Barracks panel (click the Barracks) ----------------

func _toggle_barracks_panel() -> void:
	barracks_panel.visible = not barracks_panel.visible
	if barracks_panel.visible:
		barracks_panel.position.y = _menu_open_y()
		_populate_barracks_panel()

## Lists who is living in the Barracks, with their race, category and the
## labor skills that decide what they're actually good for -- the player needs
## those side by side to answer "is this dwarf worth a house?".
func _populate_barracks_panel() -> void:
	for child in barracks_panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	barracks_panel.add_child(box)

	var title := Label.new()
	title.text = "Barracks — %d/%d" % [settlement.barracks_residents(), settlement.barracks_capacity()]
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)

	if GameState.followers.is_empty():
		var empty := Label.new()
		empty.text = "No residents yet. Recruits will arrive."
		empty.modulate = Color(1, 1, 1, 0.6)
		box.add_child(empty)
	for f in GameState.followers:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 11)
		row.text = "%s — %s (%s)   M%d G%d I%d L%d   W%d M%d F%d   [%s]" % [
			f.label(), f.species, f.category,
			f.might, f.guile, f.influence, f.loyalty,
			f.woodcutting, f.mining, f.foraging,
			f.status_label(),
		]
		if f.is_exceptional:
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		box.add_child(row)

	# FOUNDATION_SPEC section 9: "Upgrade button: present, hard-locked --
	# greyed 'Locked' state, no tooltip cost. Unlock is a roadmap milestone,
	# not a hidden requirement." So this is a real, visible, disabled Button
	# with no handler attached -- not a Label dressed up as one, because the
	# promise being made is specifically "there will be a button here".
	box.add_child(HSeparator.new())
	var upgrade := Button.new()
	upgrade.text = "Upgrade — Locked"
	upgrade.disabled = true
	box.add_child(upgrade)

	_add_button(box, "Close", func(): barracks_panel.visible = false)

func _try_place_pending(cell: Vector2i) -> void:
	var id := _pending_building_id
	var data: Dictionary = BuildingCatalog.get_building(id)
	if data.is_empty():
		_cancel_placement()
		return
	if not settlement.can_place(cell):
		EventBus.build_failed.emit("That tile is occupied.")
		return
	var cost: Dictionary = data.get("cost", {})
	if not GameState.can_afford_cost(cost):
		EventBus.build_failed.emit("Not enough resources for %s (%s)." % [data.get("display_name", id), _format_cost(cost)])
		return
	# can_afford_cost() already guards this, so spend_resource() "should"
	# always succeed here -- but checking its return value anyway means a
	# future change that lets the two drift out of sync (e.g. a resource
	# type that can go negative, or a cost check that doesn't match spend
	# semantics 1:1) fails loud instead of silently handing out a free building.
	for kind in cost.keys():
		if not GameState.spend_resource(kind, cost[kind]):
			push_warning("Main: spend_resource('%s', %d) failed after can_afford_cost passed -- aborting placement." % [kind, cost[kind]])
			return
	var building := Building.make_from_data(id, data)
	settlement.place_building(building, cell)
	_log("Placed %s at %s." % [building.display_name, cell], "events")
	_cancel_placement()

# ---------------- Worker recruitment ----------------

func _recruit_worker() -> void:
	var n := worker_system.workers.size() + 1
	var w := worker_system.recruit_worker("Skeleton Worker #%d" % n)
	if w == null:
		_log("[color=orange]Not enough Bones to recruit a worker (need %d).[/color]" % WorkerSystem.RECRUIT_COST.get("bones", 0), "alerts")
		return
	_log("[color=lightgreen]%s has risen to serve.[/color]" % w.worker_name, "characters")
	# No explicit token sync here -- WorkerSystem.add_worker() already emitted
	# worker_count_changed, which _connect_signals() wires to
	# _sync_worker_tokens(). The priority rows don't care how many workers
	# there are, so they don't need rebuilding either.

# ---------------- Blacksmith / Barracks actions ----------------

func _forge_equipment() -> void:
	if not settlement.has_building("blacksmith"):
		_log("[color=orange]Build a Blacksmith first.[/color]", "alerts")
		return
	var idle: Array = GameState.followers.filter(func(f): return not f.is_busy)
	if idle.is_empty():
		_log("[color=orange]No idle followers to equip.[/color]", "alerts")
		return
	var cost := {"dark_essence": 5}
	if not GameState.can_afford_cost(cost):
		_log("[color=orange]Not enough Dark Essence to forge equipment (need 5).[/color]", "alerts")
		return
	for kind in cost.keys():
		GameState.spend_resource(kind, cost[kind])
	var f = idle[randi() % idle.size()]
	var stats := ["might", "guile", "influence"]
	var stat: String = stats[randi() % stats.size()]
	match stat:
		"might": f.might += 1
		"guile": f.guile += 1
		"influence": f.influence += 1
	_log("[color=lightgreen]The Blacksmith forges gear for %s (+1 %s).[/color]" % [f.follower_name, stat], "characters")

func _train_followers() -> void:
	if not settlement.has_building("barracks"):
		_log("[color=orange]Build a Barracks first.[/color]", "alerts")
		return
	var idle: Array = GameState.followers.filter(func(f): return not f.is_busy)
	if idle.is_empty():
		_log("[color=orange]No idle followers to train.[/color]", "alerts")
		return
	var cost := {"bones": 5}
	if not GameState.can_afford_cost(cost):
		_log("[color=orange]Not enough Bones to train followers (need 5).[/color]", "alerts")
		return
	for kind in cost.keys():
		GameState.spend_resource(kind, cost[kind])
	for f in idle:
		f.might += 1
	_log("[color=lightgreen]The Barracks trains %d idle follower(s) (+1 Might each).[/color]" % idle.size(), "characters")

func _dispatch_random_mission() -> void:
	var missions := mission_system.get_missions()
	if missions.is_empty():
		_log("[color=orange]No missions loaded.[/color]", "alerts")
		return
	var idle: Array = []
	for f in GameState.followers:
		if not f.is_busy:
			idle.append(f)
	if idle.is_empty():
		_log("[color=orange]No idle followers to send.[/color]", "alerts")
		return
	var mission: Dictionary = missions[randi() % missions.size()]
	var party := [idle[0]]
	_log("Dispatching %s on '%s'..." % [idle[0].follower_name, mission.get("title", "?")], "characters")
	mission_system.dispatch(mission, party)

# ---------------- Signals / log ----------------

func _connect_signals() -> void:
	GameState.resources_changed.connect(func(): _update_stats_label())
	GameState.reputation_changed.connect(func(_a): _update_stats_label())
	GameState.threat_changed.connect(func(_a, _b): _update_stats_label())
	GameState.power_changed.connect(func(_a): _update_stats_label())
	GameState.game_won.connect(func():
		_log("[color=gold]*** VICTORY: your settlement has become a true power. ***[/color]", "events")
		_alert("Victory! Your settlement has become a true power.", "good")
	)
	GameState.game_lost.connect(func(reason):
		_log("[color=red]*** DEFEAT: %s ***[/color]" % reason, "events alerts")
		_alert("Defeat: %s" % reason, "bad")
	)

	EventBus.follower_count_changed.connect(func(_c): _sync_follower_tokens())
	EventBus.worker_count_changed.connect(func(_c): _sync_worker_tokens())
	EventBus.priorities_changed.connect(_build_priority_rows)
	EventBus.worker_deposited.connect(func(w, kind, amount):
		# display_name() rather than worker_name -- the labor pool is Workers
		# *and* recruited Followers now (see Laborer.gd).
		_log("%s delivered %d %s." % [w.display_name(), amount, kind], "characters")
	)
	EventBus.resource_node_depleted.connect(func(n):
		# Only worth surfacing for the finite one-offs -- a single tree of
		# twenty running out is noise, a grave or the last deer is news.
		if n.node_type in ["grave", "carcass", "deer", "stone_deposit"]:
			_log("A %s has been exhausted." % n.display_name(), "events")
	)
	EventBus.dawn_started.connect(func(day: int):
		_log("[color=lightblue]Dawn of day %d -- berries regrow, game wanders in.[/color]" % day, "events")
		_update_stats_label()  # the top bar carries the Day/Night readout
	)
	EventBus.dusk_started.connect(func(day: int):
		_log("[color=#8899cc]Dusk falls on day %d.[/color]" % day, "events")
		_update_stats_label()
	)
	# Fires on Dawn/Daylight/Dusk/Night word changes only, not per frame.
	EventBus.day_phase_changed.connect(func(_label: String): _update_stats_label())
	EventBus.follower_recruited.connect(func(f):
		var star := " [color=gold](exceptional)[/color]" if f.is_exceptional else ""
		_log("[color=lightgreen]%s the %s (%s %s) has joined you.[/color]%s" % [
			f.follower_name, f.species, f.rarity, f.category, star], "characters events")
		_alert("%s the %s has joined you." % [f.follower_name, f.species], "good")
		if barracks_panel and barracks_panel.visible:
			_populate_barracks_panel()
	)
	EventBus.recruit_turned_away.connect(func(f, reason):
		_log("[color=orange]%s the %s left — %s.[/color]" % [f.follower_name, f.species, reason], "characters events")
	)
	EventBus.bounty_posted.connect(func(b): _log("Bounty posted: %s (reward %d, risk %d)." % [b.bounty_name, b.reward, b.risk], "events"))
	EventBus.bounty_accepted.connect(func(b, f): _log("%s took the bounty '%s'." % [f.follower_name, b.bounty_name], "characters"); _send_token_away(f))
	EventBus.bounty_completed.connect(_on_bounty_completed)
	EventBus.mission_dispatched.connect(_on_mission_dispatched)
	EventBus.mission_resolved.connect(_on_mission_resolved)
	EventBus.threat_tier_escalated.connect(func(tier):
		_log("[color=orange]Threat tier escalated (%d).[/color]" % tier, "alerts events")
		_alert("Threat tier escalated (%d)." % tier, "warn")
	)
	EventBus.crusade_incoming.connect(func():
		_log("[color=red]CRUSADE INCOMING.[/color]", "alerts events")
		_alert("CRUSADE INCOMING.", "warn")
	)
	EventBus.crusade_survived.connect(func(): _log("[color=gold]Crusade survived![/color]", "events"))
	EventBus.event_triggered.connect(_on_event_triggered)
	EventBus.build_failed.connect(func(reason): _log("[color=orange]%s[/color]" % reason, "alerts"))
	EventBus.building_placed.connect(func(_b, _c): _update_stats_label(); _populate_build_row())
	EventBus.building_removed.connect(func(_b, _c): _update_stats_label(); _populate_build_row())
	EventBus.main_building_damaged.connect(func(_b): _update_stats_label())

func _on_bounty_completed(b: Bounty, f: Follower, success: bool) -> void:
	if success:
		_log("[color=lightgreen]%s completed '%s' successfully.[/color]" % [f.follower_name, b.bounty_name], "characters")
	else:
		_log("[color=orange]%s failed '%s'.[/color]" % [f.follower_name, b.bounty_name], "characters alerts")
		_alert("%s failed '%s'." % [f.follower_name, b.bounty_name], "bad")
	_return_token_home(f)

func _on_mission_dispatched(_mission: Dictionary, party: Array) -> void:
	for f in party:
		_send_token_away(f)

func _on_mission_resolved(m: Dictionary, party: Array, outcome: String) -> void:
	_log("Mission '%s' resolved: %s." % [m.get("title", "?"), outcome], "characters events")
	for f in party:
		_return_token_home(f)

func _on_event_triggered(event: Dictionary) -> void:
	current_event = event
	_log("[b]EVENT: %s[/b] -- %s" % [event.get("title", "?"), event.get("description", "")], "events")
	for child in event_panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	event_panel.add_child(box)

	# Title and description used to be log-only, which was survivable when
	# events were flat flavor text. A recruit offer's stat block is the whole
	# decision, so it has to be on the panel you're deciding from.
	var title := Label.new()
	title.text = event.get("title", "?")
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)

	var desc := Label.new()
	desc.text = event.get("description", "")
	desc.add_theme_font_size_override("font_size", 11)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(260, 0)
	box.add_child(desc)
	box.add_child(HSeparator.new())

	var choices: Array = event.get("choices", [])
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var idx := i
		_add_button(box, choice.get("label", "..."), func(): _resolve_event_choice(idx))
	event_panel.visible = true

func _resolve_event_choice(idx: int) -> void:
	event_system.resolve_event(current_event, idx)
	_log("Chose: %s" % current_event.get("choices", [])[idx].get("label", "?"), "events")
	event_panel.visible = false
	current_event = {}

func _update_stats_label() -> void:
	var home_hp_str := ""
	var main_building := settlement.get_main_building() if settlement else null
	if main_building:
		home_hp_str = "   Throne: %d/%d hp" % [main_building.hp, main_building.max_hp]
	# Mundane resources first, in the order the foundation loop cares about
	# them (Wood/Stone build, Bones raise workers, Food feeds living recruits),
	# with Dark Essence last -- it's locked at 0 for the whole foundation build
	# but stays visible as the roadmap promise that Stage 4 unlocks it.
	lbl_resources_left.text = "Wood: %d   Stone: %d   Bones: %d   Food: %d   Dark Essence: %d" % [
		GameState.wood, GameState.stone, GameState.bones, GameState.food, GameState.dark_essence
	]
	var clock_str := "%s   " % day_night.phase_label() if day_night else ""
	lbl_resources_right.text = "%sThreat: %d (tier %d)   Power: %d%s" % [
		clock_str, GameState.threat, GameState.threat_tier, GameState.power, home_hp_str
	]
	if time_scale_btn and day_night:
		time_scale_btn.text = day_night.time_scale_label()

func _on_time_scale_pressed() -> void:
	var scale: float = day_night.cycle_time_scale()
	_update_stats_label()
	_log("Debug: game speed set to %dx." % int(scale), "events")

## Every existing _log() call site now tags a category ("events", "alerts",
## "characters", or a space-separated combination) so the History tab's
## filter chips can narrow the list down -- see _entry_matches_filters().
## Defaults to "events" for call sites that don't specify one.
func _log(msg: String, category: String = "events") -> void:
	print(msg)
	if not history_log_list:
		return
	var entry := RichTextLabel.new()
	entry.bbcode_enabled = true
	entry.fit_content = true
	entry.scroll_active = false
	entry.add_theme_font_size_override("normal_font_size", 12)
	entry.text = msg
	entry.set_meta("log_cat", category)
	history_log_list.add_child(entry)
	entry.visible = _entry_matches_filters(entry)
	# Trim the oldest entry once the log grows past the cap, so a long session
	# can't grow this list unbounded.
	#
	# MUST be remove_child() before queue_free(). queue_free() is DEFERRED to
	# the end of the frame -- the node stays a child until then, so a
	# `while get_child_count() > CAP: get_child(0).queue_free()` loop never
	# sees the count drop and spins forever, hard-freezing the game. That bug
	# shipped here and in _alert() below; see the header note in _alert().
	while history_log_list.get_child_count() > MAX_HISTORY_ENTRIES:
		var oldest := history_log_list.get_child(0)
		history_log_list.remove_child(oldest)
		oldest.queue_free()

## A small rolling stack of up to MAX_ALERTS notable-event pins, top-right --
## only called from the handful of _connect_signals() handlers for events
## worth surfacing prominently (recruits, threat escalation, crusade
## warnings, victory/defeat, bounty failures), not from every _log() call.
func _alert(msg: String, kind: String = "info") -> void:
	if not alert_stack:
		return
	var b := Button.new()
	b.custom_minimum_size = Vector2(26, 26)
	b.tooltip_text = msg
	match kind:
		"good":
			b.text = "+"
			b.modulate = Color(0.6, 0.9, 0.6)
		"warn":
			b.text = "!"
			b.modulate = Color(0.95, 0.75, 0.4)
		"bad":
			b.text = "x"
			b.modulate = Color(0.9, 0.6, 0.6)
		_:
			b.text = "?"
	alert_stack.add_child(b)
	alert_stack.move_child(b, 0)  # newest on top
	# Same deferred-free trap as _log() -- see the comment there. This one was
	# the one that actually bit: MAX_ALERTS is 3 and every accepted recruit
	# raises an alert, so the *fourth* recruit you took in a session locked the
	# game up solid. remove_child() is immediate, which is what lets the loop
	# terminate; queue_free() then disposes of it safely at end of frame.
	while alert_stack.get_child_count() > MAX_ALERTS:
		var oldest := alert_stack.get_child(alert_stack.get_child_count() - 1)
		alert_stack.remove_child(oldest)
		oldest.queue_free()

# ---------------- History log filtering ----------------

func _on_history_filter_toggled(cat: String, pressed: bool) -> void:
	history_active_filters[cat] = pressed
	_apply_history_filters()

func _apply_history_filters() -> void:
	for child in history_log_list.get_children():
		child.visible = _entry_matches_filters(child)

## OR logic across whatever filter chips are active -- an entry shows if it
## matches any active filter, or if no filter is active at all (unfiltered
## view). Entries can carry more than one space-separated category (e.g. a
## follower's failed bounty is both "characters" and "alerts").
func _entry_matches_filters(entry: Control) -> bool:
	var cats: Array = String(entry.get_meta("log_cat", "events")).split(" ")
	var any_active := false
	for cat in history_active_filters.keys():
		if history_active_filters[cat]:
			any_active = true
			if cats.has(cat):
				return true
	return not any_active
