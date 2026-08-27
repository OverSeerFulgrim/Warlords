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
var morale_system: MoraleSystem
var combat_system: CombatSystem
var undead_command: UndeadCommand
## The villain, as data -- position, hp, Might, carry, escort. **This node holds
## a reference to one instance; it is not a singleton and nothing looks it up.**
## Anything that needs "the villain" is handed this (see combat_system.villain,
## villain_controller.villain) -- ROGUELITE_REWORK section 11, which is what
## keeps the Demonologist and multiplayer possible.
var villain: Necromancer
## Pure view over `villain`. Draws him; owns nothing.
var necromancer_token: NecromancerToken
## Reads WASD and drives him, and keeps the camera on him.
var villain_controller: VillainController
## The 144x144 region (rework R1). The settlement is a band inside it.
var world_map: WorldMap
var fog: FogOfWar
## The village, the sealed rival ground, the band-2 landmarks, and the patrols.
var world_sites: WorldSites
## Times journeys against WORLD_MAP_PLAN §3. R1's exit criterion, instrumented.
var travel_log: TravelLog
var camera: GameCamera

## The floating event / recruit-offer panel. See scripts/ui/EventPanelUI.gd.
var event_panel_ui: EventPanelUI

# ---------------- Top resource bar ----------------
## Resource strip, day/clock, debug speed button, necromancer badge, and the
## follow-state / orientation readouts. See scripts/ui/HudTopBar.gd.
var hud_top_bar: HudTopBar
var minimap: Minimap
var minimap_hint: Label

## Scratch buffer for _fog_sources(), reused every frame -- see there.
var _fog_source_buf: Array = []

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
var cmd_town_scroll: ScrollContainer   # wraps cmd_town so it can never overflow the band
var cmd_history: VBoxContainer
var cmd_research: Control
var bar_panel: PanelContainer      # the command bar body -- hidden/shown by the collapse arrow
var collapse_tab_btn: Button       # sits left of the Town tab; toggles bar_panel.visible
var build_tab_btn: Button
var bounty_tab_btn: Button
var economy_tab_btn: Button
var bounty_row: HBoxContainer
## Gathering-priority list, workforce summary and the tab's action buttons.
## See scripts/ui/EconomyTab.gd.
var economy_tab: EconomyTab

# ---------------- Build menu / click-to-place / demolish ----------------
## The buildable row, the Demolish toggle, and the two click-to-target modes
## they arm. This node keeps the *arbitration* between modes (see
## _unhandled_input); the module keeps their state and what a click does.
## Demolition is player-facing removal with no resource refund (confirmed with
## the user) -- SettlementGrid.remove_building() already refuses the main
## building. See scripts/ui/BuildMenu.gd.
var build_menu: BuildMenu

# ---------------- Command Undead (click-to-place a rally point) ----------------
# A third click-to-target mode, sharing the shape of the other two: arm it,
# click the map, done. All three are mutually exclusive and all three take
# priority over inspection -- see _unhandled_input().
var _rally_placement_mode: bool = false

# ---------------- Inspection panel (click anything on the map) ----------------
## One panel for everything clickable -- see InspectionPanel.gd. Replaces the
## three separate panels this file used to carry (keep_menu_panel,
## barracks_panel, necromancer_panel), each with its own toggle and populate
## function. The Keep's and Barracks' *menus* survive as action builders below
## (InspectorActions.keep_actions / barracks_actions); what's gone is three
## different ideas of what a header looks like.
var inspector: InspectionPanel

## The action buttons that panel shows for the Keep, Barracks, Necromancer and
## rally point. See scripts/ui/InspectorActions.gd.
var inspector_actions: InspectorActions

## Seconds between the HUD's slow poll -- refreshing whatever the inspector is
## showing, and re-checking whether an open recruit offer has become
## answerable. A
## worker's Activity row and a Barracks' resident count both change while you
## are looking at them, and polling a handful of Labels a couple of times a
## second is far cheaper than wiring a signal per field -- most of which
## (activity especially) would fire every frame anyway. Same reasoning as the
## priority rows being polled from _process rather than signalled.
const INSPECTOR_REFRESH_INTERVAL: float = 0.4
var _poll_timer: float = 0.0

# ---------------- Unit tokens (on-screen presence) ----------------
## The two y-sorted draw layers, the token-per-unit reconcile, and the
## proximity hit-test the inspect path picks with. See scripts/ui/TokenLayer.gd.
var token_layer: TokenLayer

# The map's resource nodes live in ResourceField now, not in a Dictionary of
# fixed marker positions here -- see _build_systems().
var worker_keep_zone: Rect2         # deposit point + idle-wander area around the main building

const INFO_PANEL_WIDTH := 170.0
## One pixel per world cell. Was 78 while this was a blank placeholder; at the
## world's own 144 the minimap is a 1:1 map of the region and needs no scaling
## arithmetic to read.
const MINIMAP_SIZE := 144.0

## Height of the whole bottom command bar (folder tabs + panel body).
##
## Was 190, which was not enough once the Economy tab grew a four-row priority
## list: the rows ran off the bottom of a 1400x760 window and Food/Bones were
## simply unreachable, because nothing scrolled. Raised to fit the tallest tab
## content at the default window size. The ScrollContainer around the Town tab
## (see _build_cmd_town) is the belt-and-braces for smaller windows -- this
## constant is what keeps scrolling from being *needed* at the default one.
const BOTTOM_BAR_HEIGHT := 250

const MAX_ALERTS := 3            # oldest alert pin is dropped once a 4th arrives
const MAX_HISTORY_ENTRIES := 200 # oldest history-log row is dropped past this cap

func _ready() -> void:
	set_process_unhandled_input(true)  # needed for build-menu click-to-place / Esc-cancel / unit selection
	_build_systems()
	_build_camera()
	_seed_starting_state()
	_build_ui()
	_connect_signals()
	token_layer.sync_follower_tokens()
	token_layer.sync_worker_tokens()
	_place_necromancer()
	_frame_camera_on_throne()          # best effort now...
	_settle_initial_camera_framing()   # ...and again once the HUD has laid out
	get_viewport().size_changed.connect(_on_viewport_resized)
	_log("Undead Empire prototype started. Frozen Wastes climate (placeholder).")

# ---------------- Camera framing ----------------

## The Throne is at grid cell (0,0) -- a corner of the map, not its middle --
## so the old "centre on the grid's midpoint" left the player's own keep tucked
## up in the top-left. Centre on the Throne itself instead.
func _throne_world_centre() -> Vector2:
	var main_building: Building = settlement.get_main_building()
	var cell: Vector2i = main_building.cell if main_building else Vector2i.ZERO
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	return Vector2(cell.x * SettlementGrid.CELL_SIZE + half, cell.y * SettlementGrid.CELL_SIZE + half)

## Tells the camera how much of the window the HUD eats, so it can centre on
## the visible map band rather than the raw window. Measured from the real
## panels where possible: the bottom bar is a known constant, the top strip is
## whatever it laid out to.
func _sync_camera_insets() -> void:
	camera.ui_top_inset = hud_top_bar.top_height() if hud_top_bar else 0.0
	camera.ui_bottom_inset = float(BOTTOM_BAR_HEIGHT)

func _frame_camera_on_throne() -> void:
	_sync_camera_insets()
	camera.center_on(_throne_world_centre())

## Control sizes aren't final on the frame they're created, so the first
## framing uses a top-bar height of 0 and is a few pixels out. Re-running it
## after two frames -- once layout has settled -- gets it exact. Deliberately
## not awaited by _ready(): this runs to its first await, lets _ready finish,
## then resumes.
func _settle_initial_camera_framing() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_frame_camera_on_throne()

## Re-frame on resize, but only while the player hasn't taken the camera
## somewhere themselves -- yanking the view back to the Throne because someone
## dragged a window corner would be worse than a slightly-off centre.
## Insets are re-synced unconditionally: the follow camera (VillainController)
## calls center_on every frame regardless of whether the player has ever panned,
## so stale insets would mis-frame him for the rest of the session.
func _on_viewport_resized() -> void:
	if camera == null:
		return
	_sync_camera_insets()
	if not camera.player_has_moved_camera:
		_frame_camera_on_throne()

func _place_necromancer() -> void:
	villain.place_at(_throne_world_centre())
	necromancer_token.setup(villain, villain_controller)
	villain_controller.snap_to_villain()

## Worker states change continuously now that gathering is a real trip loop,
## so the priority rows' Working/Satisfied labels and the workforce summary
## are polled here rather than driven by a signal that would fire every frame
## regardless. Everything genuinely event-shaped (deposits, depletion, dawn)
## still goes through EventBus -- see _connect_signals().
func _process(delta: float) -> void:
	# Fog follows the villain *and* every friendly unit. Called every frame but
	# early-outs unless one of them has crossed a cell boundary, so the common
	# case is one PackedInt32Array compare.
	if fog and villain:
		fog.update_for(_fog_sources())
	hud_top_bar.refresh_orientation()
	economy_tab.refresh_status()
	_poll_timer += delta
	if _poll_timer >= INSPECTOR_REFRESH_INTERVAL:
		_poll_timer = 0.0
		if inspector and inspector.is_open():
			inspector.refresh()
		event_panel_ui.refresh_open_offer()
		# Follow drops silently on a right-drag, so it's polled on the same slow
		# tick as everything else that changes without announcing itself.
		hud_top_bar.refresh_follow_state()

## Every light source for the fog this frame: the villain at his full radius,
## then each living friendly unit at the smaller one.
##
## The Array is a **reused member** rather than a fresh one per frame. This runs
## 60 times a second with 30+ undead on the roster, and the fog's own early-out
## only saves the *relight* -- building the list happens regardless, so it is
## the one part of this path worth not allocating.
##
## `all_units()` rather than `laborers()`: a skeleton bound to a rally point is
## off the workforce but still standing in the world with its eyes open, and it
## is exactly the case the playtest raised (33 bound undead).
func _fog_sources() -> Array:
	_fog_source_buf.clear()
	_fog_source_buf.append([villain.position, FogOfWar.REVEAL_RADIUS_CELLS])
	if worker_system:
		for u in worker_system.all_units():
			if u.is_alive():
				_fog_source_buf.append([u.position, FogOfWar.UNIT_REVEAL_RADIUS_CELLS])
	return _fog_source_buf

# ---------------- Systems ----------------

func _build_systems() -> void:
	settlement = SettlementGrid.new()
	settlement.name = "SettlementGrid"
	# **Y-sorting, enabled where it doesn't fight an existing decision.**
	# Sprites are 1.5-2x larger since the visual-scale pass, so they overlap far
	# more than 32px ones did and a worker standing behind a tree needs to go
	# behind it. Godot sorts by z_index FIRST and only then by y, and it only
	# reaches into child containers that are themselves y-sorted -- hence the
	# same flag on every layer below.
	#
	# Two units deliberately opt out by keeping a higher z_index, and both are
	# recorded playtest fixes rather than oversights: the Necromancer (z 5) must
	# never be hidden behind the Throne he stands on, and the wolf (z 6) must
	# never be hidden by anything at all -- see CLAUDE.md's combat section on
	# the wolf nobody could find. Y-sorting them would re-open both bugs.
	settlement.y_sort_enabled = true
	add_child(settlement)
	# The world first: everything below is positioned inside it, and both the
	# villain and the roamers need to be able to ask it about terrain.
	_build_world_map()

	var grid_w: float = SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE
	var grid_h: float = SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE

	token_layer = TokenLayer.new()
	token_layer.name = "TokenLayer"
	add_child(token_layer)
	token_layer.build_layers(settlement, grid_w, grid_h)

	# The map's harvestable resources. A child of `settlement` so it shares the
	# same coordinate space workers walk in -- ResourceNode positions are the
	# literal destinations WorkerSystem measures distance against.
	resource_field = ResourceField.new()
	resource_field.name = "ResourceField"
	resource_field.y_sort_enabled = true
	resource_field.world = world_map   # set before build(): the deer read it at spawn
	settlement.add_child(resource_field)
	resource_field.build(grid_w, grid_h)
	# Small ring around the main building's cell (0,0) -- where workers idle
	# between trips and where every load gets deposited.
	worker_keep_zone = Rect2(Vector2(-16, -16), Vector2(SettlementGrid.CELL_SIZE + 32, SettlementGrid.CELL_SIZE + 32))

	# The player himself: a data object plus a view over it, the same split
	# Laborer/WorkerToken uses. The token is parented to `settlement` so he
	# shares the coordinate space of the grid and every other token; the villain
	# object is plain data and lives in this field.
	villain = Necromancer.new()
	villain.world = world_map
	# The fence is the world now, not a ring around the settlement. The map's
	# blocking rim already stops him; this is the backstop if terrain ever fails
	# to load.
	if world_map:
		villain.bounds = world_map.bounds_px()
	necromancer_token = NecromancerToken.new()
	necromancer_token.name = "NecromancerToken"
	settlement.add_child(necromancer_token)

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
	token_layer.set_worker_system(worker_system)   # layers were built above, before this existed

	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	add_child(day_night)

	# Meals hang off day_night's dawn/dusk signals, so it has to exist first.
	morale_system = MoraleSystem.new()
	morale_system.name = "MoraleSystem"
	morale_system.day_night = day_night
	add_child(morale_system)

	# Wolves spawn on dusk, so this also comes after day_night. It needs the
	# labor pool (prey), the resource field (deer), the grid (the Throne, for
	# skeleton repair) and the Necromancer (whom wolves avoid) -- all set before
	# add_child so its first _process has everything, same convention as above.
	combat_system = CombatSystem.new()
	combat_system.name = "CombatSystem"
	combat_system.settlement = settlement
	combat_system.worker_system = worker_system
	combat_system.resource_field = resource_field
	combat_system.villain = villain
	combat_system.world = world_map
	combat_system.day_night = day_night
	add_child(combat_system)

	# Command Undead. Needs combat_system to hand fights to, so it comes after.
	undead_command = UndeadCommand.new()
	undead_command.name = "UndeadCommand"
	undead_command.settlement = settlement
	undead_command.worker_system = worker_system
	undead_command.combat_system = combat_system
	add_child(undead_command)

func _build_camera() -> void:
	camera = GameCamera.new()
	camera.name = "GameCamera"
	var grid_w: float = SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE
	var grid_h: float = SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE
	camera.position = Vector2(grid_w * 0.5, grid_h * 0.5)
	camera.zoom = Vector2(0.72, 0.72)
	# Panning and zooming stop at the world's edge rather than sliding off into
	# the void. Set before make_current so the first frame is already clamped.
	if world_map:
		camera.world_bounds = world_map.bounds_px()
	add_child(camera)
	camera.make_current()

	# Built here rather than in _build_systems() because it needs the camera it
	# follows with, and the camera has to exist first. Both of its dependencies
	# are handed to it -- it looks nothing up.
	villain_controller = VillainController.new()
	villain_controller.name = "VillainController"
	villain_controller.villain = villain
	villain_controller.camera = camera
	# The camera owns the right-button tap/drag split (see GameCamera's header);
	# this node owns what a tap *means*, the same way it arbitrates left-clicks.
	camera.right_tapped.connect(_on_right_tap)
	add_child(villain_controller)

	travel_log = TravelLog.new()
	travel_log.name = "TravelLog"
	travel_log.world = world_map
	travel_log.villain = villain
	if world_sites:
		travel_log.landmarks = world_sites.landmarks
	add_child(travel_log)

## The world the settlement sits in. Replaces `_build_ground_background()`, which
## was a Sprite2D per cell -- fine for the 10x8 grid, fatal at 144x144 (20,736
## nodes). The terrain is one `TileMapLayer` now; see WorldMap.gd.
##
## A child of `settlement` so it shares the coordinate space workers walk in,
## positioned so that world cell `lair_origin` lands on the settlement's own
## (0,0). That is what keeps every existing position -- the forest, the graves,
## the wolf's entry point, every click hit-test -- exactly where it was.
func _build_world_map() -> void:
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	settlement.add_child(world_map)
	if not world_map.build():
		push_error("Main: world map failed to load; the settlement will float in the void.")
		return

	# Static world content. Before the fog, so it is under it in draw order --
	# a village you haven't found must be hidden like anything else.
	world_sites = WorldSites.new()
	world_sites.name = "WorldSites"
	world_sites.y_sort_enabled = true
	settlement.add_child(world_sites)
	world_sites.build(world_map)

	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	settlement.add_child(fog)
	fog.setup(world_map)
	# The lair band starts revealed and stays visible -- see FogOfWar for why
	# his own valley doesn't dim when he leaves it.
	fog.reveal_permanently(world_map.lair_band)

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
## goes through the build menu / BuildMenu.try_place() instead.
func _place_from_catalog(id: String, cell: Vector2i) -> void:
	var data: Dictionary = BuildingCatalog.get_building(id)
	if data.is_empty():
		push_warning("Main: unknown building_id '%s' in _seed_starting_state" % id)
		return
	settlement.place_building(Building.make_from_data(id, data), cell)

# ---------------- UI (built in code on purpose -- see file header) ----------------

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var hud_root := Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_root)

	# ORDER MATTERS. Sibling Controls are drawn -- and offered mouse input -- in
	# child order, last on top. The bottom command bar used to be built last,
	# which put it over the two floating panels: the event panel's choice
	# buttons hang below the screen's centre line, landed underneath the command
	# bar, were tinted by its translucent background (they looked *disabled*),
	# and had their clicks swallowed by it. A recruit offer became genuinely
	# impossible to answer. The floating panels are built last now so they sit
	# above the bar, and EventPanelUI also keeps the event panel inside
	# the visible band so it never covers the bar in the first place.
	hud_top_bar = HudTopBar.new()
	hud_top_bar.name = "HudTopBar"
	add_child(hud_top_bar)
	hud_top_bar.build(hud_root, _panel_style(), settlement, day_night, world_map,
		villain, villain_controller, travel_log)
	_build_alert_stack(hud_root)
	_build_placement_hint(hud_root)
	_build_bottom_shell(hud_root)
	hud_top_bar.set_minimap(minimap)   # born in the bottom shell, above
	_build_inspection_panel(hud_root)
	_build_event_panel(hud_root)

	hud_top_bar.refresh_stats()
	build_menu.populate()
	economy_tab.build_priority_rows()
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
	build_menu = BuildMenu.new()
	build_menu.name = "BuildMenu"
	add_child(build_menu)
	build_menu.build_hint(hud_root)

## The panel is TOP_LEFT-anchored and positioned by hand, because PRESET_CENTER
## anchors a panel's *top-left corner* to the screen centre -- it grows down and
## right from there rather than being centred on it -- which is how its choice
## buttons ended up under the bottom command bar.
##
## Where it may sit is this node's business, not the module's: the usable band
## depends on the top strip's laid-out height and the command bar's, so the band
## is handed in as a provider.
func _build_event_panel(hud_root: Control) -> void:
	event_panel_ui = EventPanelUI.new()
	event_panel_ui.name = "EventPanelUI"
	add_child(event_panel_ui)
	event_panel_ui.build(hud_root, _panel_style(), event_system, func() -> Vector2:
		return Vector2(
			hud_top_bar.top_height() + 8.0,
			get_viewport_rect().size.y - float(BOTTOM_BAR_HEIGHT) - 8.0
		)
	)

## One panel, reused by every inspectable thing. It positions itself under the
## top resource bar each time it opens (see _inspect), same as the three panels
## it replaced.
## Parked on the left, clear of the centred event panel. It used to open at
## x=360 (inherited from the old Keep menu), which at the default 1400px put it
## straight under a recruit offer -- and since the event panel is now drawn on
## top, that would have covered the Barracks panel's "Fund house" button: the
## exact control you need to reach to answer a full-Barracks offer.
## x=60 clears the Necromancer badge at (10, 40) and leaves the whole centre
## free.
const INSPECTOR_X: float = 60.0

func _build_inspection_panel(hud_root: Control) -> void:
	inspector = InspectionPanel.new()
	inspector.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inspector.position = Vector2(INSPECTOR_X, 96)
	hud_root.add_child(inspector)

	inspector_actions = InspectorActions.new()
	inspector_actions.name = "InspectorActions"
	add_child(inspector_actions)
	inspector_actions.setup(undead_command, inspector, villain_controller)

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
	bottom_shell.offset_top = -BOTTOM_BAR_HEIGHT
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

	# Info panel: a one-line echo of whatever the inspection panel is showing,
	# so the bottom bar still says what's selected once the panel is closed or
	# scrolled past. Fed from the same Dictionary -- see _inspect().
	var info_panel := VBoxContainer.new()
	info_panel.custom_minimum_size = Vector2(INFO_PANEL_WIDTH, 0)
	info_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	info_name_label = Label.new()
	info_name_label.text = "Nothing selected"
	info_name_label.add_theme_font_size_override("font_size", 15)
	info_panel.add_child(info_name_label)
	info_class_label = Label.new()
	info_class_label.text = "Click a unit, a building, or a resource"
	info_class_label.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(info_class_label)
	info_status_label = Label.new()
	info_status_label.add_theme_font_size_override("font_size", 11)
	info_panel.add_child(info_status_label)
	bar_hbox.add_child(info_panel)

	bar_hbox.add_child(VSeparator.new())

	var command_area := VBoxContainer.new()
	command_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Vertical fill too, or the History log inside it has no height to expand
	# into -- the container would shrink to its content and leave the dead band
	# playtest reported below the log.
	command_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_hbox.add_child(command_area)

	_build_cmd_town(command_area)
	_build_cmd_history(command_area)
	_build_cmd_research(command_area)

	bar_hbox.add_child(VSeparator.new())

	# The real minimap, replacing the ColorRect placeholder that stood here.
	# MINIMAP_SIZE is the world's cell count on purpose: one pixel per cell.
	var minimap_column := VBoxContainer.new()
	minimap_column.add_theme_constant_override("separation", 2)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	# mouse_filter is set to STOP inside setup() -- the minimap takes its own
	# clicks now, and must not let them fall through to the world behind it.
	minimap.setup(world_map, fog, villain, camera)
	minimap.units_source = func(): return worker_system.all_units() if worker_system else []
	minimap.camera_requested.connect(_on_minimap_camera_requested)
	minimap.move_requested.connect(_on_right_tap)
	minimap_column.add_child(minimap)
	minimap_hint = Label.new()
	minimap_hint.add_theme_font_size_override("font_size", 9)
	minimap_hint.modulate = Color(1, 1, 1, 0.55)
	minimap_hint.text = "○ lair   ● you   · yours"
	minimap_column.add_child(minimap_hint)
	bar_hbox.add_child(minimap_column)

## Town tab content: the Build/Bounty/Economy category tabs plus each one's
## row of actions. Originally folded in every action button the old top-strip
## debug UI had (Build, Recruit Worker, Forge Equipment, Train Followers, both
## bounty posts, Dispatch Mission, Lay Low). The foundation reset then pulled
## the four Stage-4 ones (both bounty posts, Forge Equipment, Train Followers)
## plus Dispatch Mission back out of the UI -- see the comments inline below
## and CLAUDE.md's "Foundation reset" section; the code behind them is intact.
func _build_cmd_town(command_area: VBoxContainer) -> void:
	# Scroll wrapper. Two jobs: (1) nothing in this tab can ever be rendered
	# below the window edge and be unreachable -- which is exactly what
	# happened to the Food and Bones priority rows -- and (2) it stops
	# cmd_town's content minimum height propagating up to bar_panel, which is
	# what let the panel grow taller than the band it lives in. A
	# ScrollContainer reports ~0 minimum on any axis it can scroll.
	#
	# Only the Town tab is wrapped: the History tab already owns an inner
	# ScrollContainer for its log, and nesting two would make the log fight
	# the outer scroll. Research is a one-line placeholder.
	cmd_town_scroll = ScrollContainer.new()
	cmd_town_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cmd_town_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cmd_town_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cmd_town_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_area.add_child(cmd_town_scroll)

	cmd_town = VBoxContainer.new()
	cmd_town.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_town_scroll.add_child(cmd_town)

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
	# BuildMenu.populate() whenever the settlement changes (a new Workshop
	# can unlock Blacksmith/Barracks appearing here).
	build_menu.build_row_into(cmd_town, settlement)

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

	economy_tab = EconomyTab.new()
	economy_tab.name = "EconomyTab"
	add_child(economy_tab)
	economy_tab.build(cmd_town, worker_system, resource_field)

## History tab content: Events/Alerts/Characters filter chips above a
## scrollable log. Replaces the old always-visible bottom-left log panel --
## every _log() call still fires, it just lands here instead.
func _build_cmd_history(command_area: VBoxContainer) -> void:
	cmd_history = VBoxContainer.new()
	cmd_history.visible = false
	# Claim the whole command area. Without this the tab shrinks to its content
	# minimum and the log is stuck in a 56px slot with a band of dead space
	# underneath it -- which is what made the History tab a "tiny scrollwheel"
	# in playtest.
	cmd_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cmd_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# EXPAND_FILL rather than a fixed 56px height: the log should use every
	# pixel the bottom band has left after the filter chips, and grow with the
	# window instead of staying a letterbox.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# Toggle the scroll wrapper, not cmd_town itself -- hiding the inner VBox
	# while leaving the ScrollContainer visible would leave an empty scrolling
	# hole where the tab used to be.
	cmd_town_scroll.visible = tab == "town"
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
	build_menu.set_tab_visible(tab == "build")
	bounty_row.visible = tab == "bounty"
	economy_tab.set_tab_visible(tab == "economy")
	_restyle_category_tab(build_tab_btn, tab == "build")
	_restyle_category_tab(bounty_tab_btn, tab == "bounty")
	_restyle_category_tab(economy_tab_btn, tab == "economy")

# ---------------- Unit/building selection info panel ----------------

func _select_info(unit_name: String, klass: String, status: String) -> void:
	info_name_label.text = unit_name
	info_class_label.text = klass
	info_status_label.text = status

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

func _unhandled_input(event: InputEvent) -> void:
	if build_menu.is_placing():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			build_menu.cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos: Vector2 = settlement.get_global_mouse_position()
			var cell: Vector2i = settlement.cell_from_world(world_pos)
			build_menu.try_place(cell)
			get_viewport().set_input_as_handled()
		return

	if build_menu.is_demolishing():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			build_menu.toggle_demolish_mode()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos: Vector2 = settlement.get_global_mouse_position()
			var cell: Vector2i = settlement.cell_from_world(world_pos)
			build_menu.try_demolish(cell)
			get_viewport().set_input_as_handled()
		return

	# Command Undead's rally point: the third click-to-target mode, same shape
	# as the two above. Unlike them it isn't cell-locked -- the dead rally on a
	# spot, not a tile -- so it takes the raw world position.
	if _rally_placement_mode:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_rally_placement()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_place_rally_point(settlement.get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return

	# Esc closes the inspector. Deliberately *below* the two placement blocks
	# above, which both return early: while you're placing or demolishing,
	# Esc cancels that mode, and the inspector is not what Esc is for.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if inspector.is_open():
			_close_inspector()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world_pos: Vector2 = settlement.get_global_mouse_position()
		if _inspect_at(world_pos):
			get_viewport().set_input_as_handled()

## Click pick order, highest priority first: **characters > resource nodes >
## buildings > ground**. A worker standing on a tree inspects as the worker,
## and the Necromancer pacing on top of the Throne inspects as the Necromancer.
## Returns true if the click was consumed (it always is -- clicking bare ground
## still counts, because closing the panel is a deliberate action).
##
## Click handling stays centralized here rather than each Building/ResourceNode
## growing its own Area2D, because it has to coexist with build placement and
## demolish mode, and those two need first refusal on every click. Placement
## and demolish already returned before this is reached.
func _inspect_at(world_pos: Vector2) -> bool:
	# --- 0. Fog --------------------------------------------------------------
	# The interaction half of "remembered ground shows no live contents": you
	# cannot click what you cannot currently see. Terrain you have explored
	# stays on screen as a memory; the wolf standing on it does not answer.
	# Clicking into fog closes the panel, exactly like clicking bare ground --
	# it is still a deliberate "show me nothing".
	if fog and not fog.is_visible_at(world_pos):
		_close_inspector()
		return true

	# --- 1. Characters -------------------------------------------------------
	# Free-roaming tokens aren't cell-locked, so these are proximity tests
	# against the unit's current position, not a grid lookup.
	# Measured against the villain's own position, not the token's -- the token
	# is a pure view and therefore always a frame stale. Same correctness
	# TokenLayer.closest_token_hit() was fixed for.
	if villain and world_pos.distance_to(villain.position) <= necromancer_token.hit_radius():
		_inspect(necromancer_token, inspector_actions.necromancer_actions)
		return true

	var hit_follower: Follower = token_layer.follower_at(world_pos)
	if hit_follower:
		_inspect(hit_follower)
		return true

	var hit_worker: Worker = token_layer.worker_at(world_pos)
	if hit_worker:
		_inspect(hit_worker)
		return true

	# Wolves are characters too, for picking purposes -- and the player will
	# want to click one the moment it appears, to find out how much trouble it
	# is. Checked after your own units so a defended worker stays selectable
	# during the fight they're standing in the middle of.
	if combat_system:
		for wolf in combat_system.wolves:
			if world_pos.distance_to(wolf.position) <= wolf.hit_radius():
				_inspect(wolf)
				return true

	# --- 1b. The rally point -------------------------------------------------
	# Sits with the characters rather than with the buildings: it's a small
	# marker the player needs to be able to re-order quickly, and it has no
	# footprint of its own to compete with anything.
	if undead_command and undead_command.is_active():
		var rp: RallyPoint = undead_command.rally_point
		if world_pos.distance_to(rp.position) <= rp.hit_radius():
			_inspect(rp, inspector_actions.rally_actions)
			return true

	# --- 1c. Patrols and world sites -----------------------------------------
	# Patrols sit with the characters (WorldSites.pick_at checks them first);
	# the village buildings and landmarks rank below resource nodes for the same
	# reason settlement buildings do -- a deer standing in front of a house is
	# the thing on top.
	if world_sites:
		var hit_patrol = world_sites.pick_at(world_pos)
		if hit_patrol is Patrol:
			_inspect(hit_patrol)
			return true

	# --- 2. Resource nodes ---------------------------------------------------
	# Above buildings because nodes sit mostly off-grid (the forest, the
	# deposit, the graves) and a deer can wander across the settlement, so a
	# node overlapping a building means the node is the thing on top.
	var hit_node: ResourceNode = resource_field.node_at(world_pos) if resource_field else null
	if hit_node:
		_inspect(hit_node)
		return true

	# --- 2b. World sites (village, sealed ground, landmarks) -----------------
	if world_sites:
		var hit_site = world_sites.pick_at(world_pos)
		if hit_site:
			_inspect(hit_site)
			return true

	# --- 3. Buildings --------------------------------------------------------
	# Every building, not just the Throne and the Barracks -- those two simply
	# also contribute action buttons.
	var cell: Vector2i = settlement.cell_from_world(world_pos)
	var building: Building = settlement.cells.get(cell)
	if building:
		_inspect(building, inspector_actions.actions_for_building(building))
		return true

	# --- 4. Ground -----------------------------------------------------------
	_close_inspector()
	return true

## Opens the inspector on `source` and mirrors its header into the bottom-bar
## info strip, so the two never disagree about what's selected.
func _inspect(source: Object, extra: Callable = Callable()) -> void:
	inspector.position.y = _menu_open_y()
	# Cap the body to the visible band so a long roster scrolls inside the panel
	# instead of running off the bottom of the window and under the command bar.
	inspector.max_body_height = maxf(
		140.0, get_viewport_rect().size.y - float(BOTTOM_BAR_HEIGHT) - _menu_open_y() - 8.0)
	_poll_timer = 0.0
	var data: Dictionary = inspector.inspect(source, extra)
	if data.is_empty():
		return
	# The first details row is the most-changing one for every type (Activity
	# for characters, Condition/Produces for buildings, Remaining for nodes),
	# which makes it the right thing to echo into the one-line status slot.
	var details: Array = data.get("details", [])
	var status: String = details[0].get("value", "") if not details.is_empty() else ""
	_select_info(data.get("title", ""), data.get("subtitle", ""), status)

func _close_inspector() -> void:
	inspector.close()
	_select_info("Nothing selected", "Click a unit, a building, or a resource", "")

## Returns the y-coordinate just below the top resource bar's actual current
## height, with a small margin -- used to position the inspection panel each
## time it opens, rather than a hardcoded number.
func _menu_open_y() -> float:
	return hud_top_bar.top_height() + 12.0

# ---------------- Inspector action handlers ----------------
#
# The buttons themselves are built by scripts/ui/InspectorActions.gd. What
# stays here is what a press implies that only this node can do: reloading the
# run, arbitrating the rally placement mode against the build and demolish
# modes, and paying for a house (which writes to the history log).

func _surrender_and_restart() -> void:
	_close_inspector()
	GameState.reset()
	get_tree().reload_current_scene()

func _enter_rally_placement_mode() -> void:
	if build_menu.is_placing():
		build_menu.cancel_placement()
	if build_menu.is_demolishing():
		build_menu.toggle_demolish_mode()
	_close_inspector()
	_rally_placement_mode = true
	build_menu.show_hint("Command Undead — click where the dead should rally (Esc to cancel)")

# ---------------- Right-click: walk there ------------------------------------

## A right-click tap on the world or on the minimap.
##
## **An armed click-to-target mode gets first refusal and simply cancels**,
## which is how those modes already treat a click they did not want: while you
## are placing a building, the next click is about placing (or not placing) it,
## and walking off mid-placement would be a second thing happening on one click.
## The player right-clicks again to actually move.
##
## Note there is no fog or walkability check on the destination. Straight-line
## movement already refuses blocking terrain by sliding, and refusing to walk
## toward unexplored ground would make the fog a fence -- which is the opposite
## of what it is for.
func _on_right_tap(world_pos: Vector2) -> void:
	if build_menu.is_placing():
		build_menu.cancel_placement()
		return
	if build_menu.is_demolishing():
		build_menu.toggle_demolish_mode()
		return
	if _rally_placement_mode:
		_cancel_rally_placement()
		return
	villain_controller.order_move_to(world_pos)

## A left-click on the minimap. Jumps the camera without touching follow --
## unless follow is on, in which case looking somewhere else by hand means the
## same thing here as a right-drag does, and follow drops.
func _on_minimap_camera_requested(world_pos: Vector2) -> void:
	if villain_controller.following:
		villain_controller.stop_following()
	camera.center_on(world_pos)
	camera.player_has_moved_camera = true

func _cancel_rally_placement() -> void:
	_rally_placement_mode = false
	build_menu.hide_hint()

func _place_rally_point(world_pos: Vector2) -> void:
	# Keeps whatever order is already in force when the point is moved, so
	# re-siting a patrol doesn't silently demote it to defend.
	var order: int = undead_command.rally_point.order if undead_command.is_active() else RallyPoint.Order.DEFEND
	undead_command.cast(world_pos, order)
	_cancel_rally_placement()
	_inspect(undead_command.rally_point, inspector_actions.rally_actions)

## Pays for a recruit's house. Where it lands is the recruit's call, not the
## player's -- see HousePlanner.
func _fund_house(follower) -> void:
	var cell: Vector2i = settlement.fund_house(follower, resource_field)
	if cell == Vector2i(-1, -1):
		_log("[color=orange]Can't fund a house for %s right now.[/color]" % follower.follower_name, "alerts")
		return
	var style: String = RaceCatalog.get_race(follower.race_id).get("housing_style", "communal")
	_log("[color=lightgreen]%s built a house at %s (%s).[/color] Barracks now %d/%d." % [
		follower.follower_name, cell, style,
		settlement.barracks_residents(), settlement.barracks_capacity()], "characters events")
	# Immediate rather than waiting on the poll: the player just pressed the
	# button that emptied this slot, so the panel has to agree straight away.
	inspector.refresh()

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
	# TokenLayer.sync_worker_tokens(). The priority rows don't care how many workers
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
	# Modules that own a self-contained concern connect their own signals: the
	# HUD strip's read-only refreshes, the token layer's count-changed reconcile.
	# What stays here is what they can't decide for themselves -- opening the
	# inspection panel is the inspect path's business, and the history log is
	# Main's, so bounty/mission token moves are delegated from here rather than
	# wired inside TokenLayer.
	token_layer.connect_signals()
	# Raising a worker costs Bones and writes a history line, so the Economy
	# tab's button reports the press and Main.gd does the work -- the same
	# handler the Keep menu's identical button uses.
	economy_tab.recruit_worker_pressed.connect(_recruit_worker)
	# The inspector's buttons report; this node decides. Rally placement in
	# particular has to cancel any build or demolish mode first, which is why it
	# can't live in the module -- see _enter_rally_placement_mode().
	inspector_actions.recruit_worker_pressed.connect(_recruit_worker)
	inspector_actions.surrender_requested.connect(_surrender_and_restart)
	inspector_actions.rally_placement_requested.connect(_enter_rally_placement_mode)
	inspector_actions.fund_house_requested.connect(_fund_house)
	inspector_actions.close_requested.connect(_close_inspector)
	inspector_actions.follow_toggle_requested.connect(func():
		villain_controller.toggle_follow()
		hud_top_bar.refresh_follow_state()
		inspector.refresh()
	)
	# The build menu owns its two modes' state; this node stays the only thing
	# that can see all three click-to-target modes at once, so dropping rally
	# placement when a build or demolish is armed is arbitrated here.
	build_menu.rally_cancel_requested.connect(_cancel_rally_placement)
	build_menu.inspector_close_requested.connect(_close_inspector)
	build_menu.placed.connect(func(display_name: String, cell: Vector2i):
		_log("Placed %s at %s." % [display_name, cell], "events")
	)
	build_menu.demolished.connect(func(display_name: String, cell: Vector2i):
		_log("Demolished %s at %s." % [display_name, cell], "events")
	)
	build_menu.demolish_refused.connect(func(display_name: String):
		_log("[color=orange]The %s can't be demolished.[/color]" % display_name, "alerts")
		_alert("The %s can't be demolished." % display_name, "warn")
	)

	# The event panel draws itself; the history log is still written here.
	event_panel_ui.event_opened.connect(func(event: Dictionary):
		_log("[b]EVENT: %s[/b] -- %s" % [event.get("title", "?"), event.get("description", "")], "events")
	)
	event_panel_ui.choice_resolved.connect(func(label: String):
		_log("Chose: %s" % label, "events")
	)
	event_panel_ui.offer_room_found.connect(func(title: String):
		_log("[color=lightgreen]A Barracks slot opened — %s can be taken in after all.[/color]"
			% title, "events characters")
		_alert("Room found for %s." % title, "good")
	)
	hud_top_bar.badge_pressed.connect(func(): _inspect(necromancer_token, inspector_actions.necromancer_actions))
	hud_top_bar.debug_speed_changed.connect(func(scale: float):
		_log("Debug: game speed set to %dx." % int(scale), "events")
	)
	GameState.game_won.connect(func():
		_log("[color=gold]*** VICTORY: your settlement has become a true power. ***[/color]", "events")
		_alert("Victory! Your settlement has become a true power.", "good")
	)
	GameState.game_lost.connect(func(reason):
		_log("[color=red]*** DEFEAT: %s ***[/color]" % reason, "events alerts")
		_alert("Defeat: %s" % reason, "bad")
	)

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
		hud_top_bar.refresh_stats()  # the top bar carries the Day/Night readout
	)
	EventBus.dusk_started.connect(func(day: int):
		_log("[color=#8899cc]Dusk falls on day %d.[/color]" % day, "events")
		hud_top_bar.refresh_stats()
	)

	# ---- Meals / morale (MoraleSystem) ----
	EventBus.meal_served.connect(func(phase: String, fed: int, shorted: int):
		if shorted > 0:
			_log("[color=orange]%s meal: %d fed, %d went hungry.[/color]" % [phase, fed, shorted], "events alerts")
			_alert("%d went hungry at %s." % [shorted, phase.to_lower()], "warn")
		elif fed > 0:
			_log("%s meal: %d fed." % [phase, fed], "events")
		inspector.refresh()
	)
	EventBus.recruit_misbehaved.connect(func(_f, text: String, _kind: String, _amount: int):
		_log("[color=orange]%s[/color]" % text, "characters alerts")
		_alert(text, "bad")
	)
	EventBus.recruit_departure_warning.connect(func(f):
		_log("[color=red]%s is at breaking point and will leave if they miss another meal.[/color]"
			% f.follower_name, "characters alerts events")
		_alert("%s is about to desert." % f.follower_name, "bad")
		inspector.refresh()
	)
	EventBus.recruit_departed.connect(func(f, reason: String):
		_log("[color=red]%s the %s has left your service (%s).[/color]" % [f.follower_name, f.species, reason],
			"characters alerts events")
		_alert("%s has deserted." % f.follower_name, "bad")
		# A Follower is a RefCounted, so is_instance_valid() stays true after
		# they leave the roster -- the panel can't detect this one itself.
		if inspector.current_source() == f:
			_close_inspector()
		else:
			inspector.refresh()
	)
	# ---- Combat / wildlife (CombatSystem) ----
	# All log + alert pin, no modal popups. A wolf is something you notice and
	# react to, not something that stops the game to ask you a question -- the
	# whole point of the emergent-defence rule is that the settlement responds
	# without the player being prompted.
	EventBus.wolf_spawned.connect(func(_w):
		_log("[color=#cc8866]Wolves prowl the treeline.[/color]", "events alerts")
		_alert("Wolves prowl the treeline.", "warn")
	)
	EventBus.wolf_departed.connect(func(_w, reason: String):
		_log("[color=#99aabb]The wolf is gone — %s.[/color]" % reason, "events")
	)
	EventBus.wolf_killed.connect(func(_at: Vector2, bones: int):
		_log("[color=lightgreen]The wolf is dead. Its carcass is worth %d bones — send someone to fetch it.[/color]"
			% bones, "events alerts")
		_alert("Wolf killed — %d bones on the ground." % bones, "good")
	)
	# The villain going down. **Nothing ends here yet** -- run start/end is
	# rework stage R4, and building half a run lifecycle now would mean unpicking
	# it then. What this does is make the moment impossible to miss while R1-R3
	# are being built, which is exactly what it's for.
	EventBus.villain_died.connect(func(v, cause: String):
		_log("[color=red][b]THE NECROMANCER HAS FALLEN — the run would end here.[/b][/color] (%s)"
			% cause, "events alerts characters")
		_alert("THE NECROMANCER HAS FALLEN.", "bad")
		push_warning("Villain down (%s, class '%s') — the run lifecycle is R4, so play continues."
			% [v.combat_name(), v.class_id])
	)
	# Journey milestones. Logged rather than alerted: pacing information is
	# something you read afterwards, not something that should interrupt a walk.
	EventBus.travel_noted.connect(func(text: String, seconds: float):
		var stamp: String = "" if seconds <= 0.0 else " [%s]" % TravelLog._fmt(seconds)
		_log("[color=#9fb6c8]%s%s[/color]" % [text, stamp], "events")
	)
	EventBus.combat_started.connect(func(attacker: String, defender: String):
		_log("[color=orange]A %s sets on %s![/color]" % [attacker, defender], "events alerts characters")
		_alert("A %s is attacking %s." % [attacker, defender], "warn")
	)
	EventBus.combat_joined.connect(func(f, attacker: String):
		_log("[color=lightgreen]%s wades in against the %s.[/color]" % [f.follower_name, attacker],
			"characters events")
		_alert("%s joins the fight." % f.follower_name, "good")
	)
	EventBus.worker_destroyed.connect(func(w, cause: String):
		_log("[color=red]A %s tore apart %s.[/color]" % [cause, w.worker_name], "events alerts characters")
		_alert("%s was destroyed." % w.worker_name, "bad")
		# A Worker is RefCounted, so the panel's is_instance_valid() guard can't
		# see this -- same case as a deserting Follower.
		if inspector.current_source() == w:
			_close_inspector()
	)
	EventBus.recruit_injured.connect(func(f, cause: String):
		_log("[color=orange]%s broke off from the %s and fled home, badly hurt. They cannot work until they recover.[/color]"
			% [f.follower_name, cause], "events alerts characters")
		_alert("%s is injured." % f.follower_name, "bad")
	)
	EventBus.recruit_recovered.connect(func(f):
		_log("[color=lightgreen]%s has recovered and is fit to work again.[/color]" % f.follower_name,
			"characters events")
	)
	EventBus.deer_taken_by_predator.connect(func(_n, predator: String):
		_log("[color=orange]A %s brought down one of the deer. That food is gone.[/color]" % predator,
			"events alerts")
		_alert("A %s took a deer." % predator, "warn")
	)
	EventBus.undead_commanded.connect(func(_at: Vector2, order_name: String, bound: int):
		_log("[color=#b8a0e0]Command Undead — %d of the dead answer. Order: %s.[/color] They will not gather while bound."
			% [bound, order_name], "events characters")
		_alert("%d undead rallied (%s)." % [bound, order_name], "info")
	)
	EventBus.undead_dismissed.connect(func():
		_log("[color=#b8a0e0]The rally point fades. The dead return to their work.[/color]", "events characters")
	)
	EventBus.necromancer_feared.connect(func(predator: String):
		_log("[color=#a99cc8]The %s catches the Necromancer's scent and slinks away from the Throne.[/color]"
			% predator, "events")
	)

	EventBus.follower_recruited.connect(func(f):
		var star := " [color=gold](exceptional)[/color]" if f.is_exceptional else ""
		_log("[color=lightgreen]%s the %s (%s %s) has joined you.[/color]%s" % [
			f.follower_name, f.species, f.rarity, f.category, star], "characters events")
		_alert("%s the %s has joined you." % [f.follower_name, f.species], "good")
		inspector.refresh()
	)
	EventBus.recruit_turned_away.connect(func(f, reason):
		_log("[color=orange]%s the %s left — %s.[/color]" % [f.follower_name, f.species, reason], "characters events")
	)
	EventBus.bounty_posted.connect(func(b): _log("Bounty posted: %s (reward %d, risk %d)." % [b.bounty_name, b.reward, b.risk], "events"))
	EventBus.bounty_accepted.connect(func(b, f): _log("%s took the bounty '%s'." % [f.follower_name, b.bounty_name], "characters"))
	EventBus.bounty_completed.connect(_on_bounty_completed)
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
	EventBus.build_failed.connect(func(reason): _log("[color=orange]%s[/color]" % reason, "alerts"))
	EventBus.building_placed.connect(func(_b, _c): hud_top_bar.refresh_stats(); build_menu.populate())
	EventBus.building_removed.connect(func(b, _c):
		hud_top_bar.refresh_stats()
		build_menu.populate()
		# Demolishing what you're looking at. queue_free() is deferred, so the
		# panel's own is_instance_valid() guard wouldn't notice until next frame.
		if inspector.current_source() == b:
			_close_inspector()
	)

func _on_bounty_completed(b: Bounty, f: Follower, success: bool) -> void:
	if success:
		_log("[color=lightgreen]%s completed '%s' successfully.[/color]" % [f.follower_name, b.bounty_name], "characters")
	else:
		_log("[color=orange]%s failed '%s'.[/color]" % [f.follower_name, b.bounty_name], "characters alerts")
		_alert("%s failed '%s'." % [f.follower_name, b.bounty_name], "bad")

func _on_mission_resolved(m: Dictionary, _party: Array, outcome: String) -> void:
	_log("Mission '%s' resolved: %s." % [m.get("title", "?"), outcome], "characters events")

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
