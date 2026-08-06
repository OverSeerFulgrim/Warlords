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

var current_event: Dictionary = {}
var event_panel: PanelContainer

# ---------------- Top resource bar ----------------
var top_panel: PanelContainer  # kept so menus below can size themselves off its actual height
var lbl_resources_left: Label
var lbl_resources_right: Label
var lbl_dark_essence: Label    # sits right of the Dark Essence icon
var time_scale_btn: Button
var necro_badge: Button
## Camera-follow readout, under the badge. See _refresh_follow_state_label().
var follow_state_label: Label
## Where am I / how deep am I / which way is home. See _refresh_orientation().
var orientation_label: Label
var minimap: Minimap
var minimap_hint: Label

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
var build_row: HBoxContainer
var bounty_row: HBoxContainer
var economy_row: VBoxContainer
var workers_row: VBoxContainer     # holds the priority list + workforce summary
var workforce_label: Label
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
## (_build_keep_actions / _build_barracks_actions); what's gone is three
## different ideas of what a header looks like.
var inspector: InspectionPanel

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
## **Legacy fallback only.** Token art is now data-driven: every race carries a
## `sprite` in races.json (see RaceCatalog.sprite), pointing at the
## commissioned art in "Official Sprites/". This Dictionary survives for the
## handful of *species* that were never races -- Ghoul and Wraith exist only in
## the superseded followers.json templates and have no races.json row, so a
## follower built through that path would otherwise have no art at all.
## Skeleton/Orc/Goblin are here for the same historical reason and are
## shadowed in practice by the races.json entries.
##
## Don't add to this. Add a `sprite` to races.json instead.
const SPECIES_SPRITES := {
	"Skeleton": "res://assets/placeholder/modular/character_024.png",
	"Ghoul": "res://assets/placeholder/modular/character_036.png",
	"Wraith": "res://assets/placeholder/modular/character_020.png",
	"Orc": "res://assets/placeholder/modular/character_023.png",
	"Goblin": "res://assets/placeholder/modular/character_022.png",
}

## The player's own portrait -- commissioned, used for both the HUD badge and
## the on-map avatar (NecromancerToken has its own copy of this path).
const NECROMANCER_SPRITE := "res://assets/official/characters/Necromancer_Portrait.png"

## Icon for Dark Essence in the top resource bar. Currently the *only* resource
## with an icon: the other four (Wood/Stone/Bones/Food) have no commissioned
## art yet, so the bar is deliberately one icon plus four text labels rather
## than a half-finished icon set. Revisit when the rest arrive.
const ICON_DARK_ESSENCE := "res://assets/official/icons/Icon_Dark_Essence.png"

## Last-resort portrait if a follower has neither a races.json sprite nor a
## SPECIES_SPRITES entry. Reaching this means a data gap, not a normal path.
const FALLBACK_SPECIES_SPRITE := "res://assets/placeholder/modular/character_001.png"

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

## Compact metrics for the priority rows. Godot's default Button/SpinBox
## minimum height is ~31px; four rows of that plus a header and two summary
## lines is 180px, which does not fit. These bring a row to ~24px.
const PRIORITY_ROW_HEIGHT := 24.0
const PRIORITY_FONT_SIZE := 10
const PRIORITY_ARROW_WIDTH := 22.0
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
	camera.ui_top_inset = top_panel.size.y if top_panel else 0.0
	camera.ui_bottom_inset = float(BOTTOM_BAR_HEIGHT)

func _frame_camera_on_throne() -> void:
	_sync_camera_insets()
	camera.center_on(_throne_world_centre())

## Control sizes aren't final on the frame they're created, so the first
## framing uses a top_panel height of 0 and is a few pixels out. Re-running it
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
	# Fog follows the villain. Called every frame but early-outs unless he has
	# crossed a cell boundary, so this is a Vector2i compare in the common case.
	if fog and villain:
		fog.update_for(villain.position)
	_refresh_orientation()
	_refresh_priority_status()
	_poll_timer += delta
	if _poll_timer >= INSPECTOR_REFRESH_INTERVAL:
		_poll_timer = 0.0
		if inspector and inspector.is_open():
			inspector.refresh()
		_refresh_open_offer()
		# Follow drops silently on a right-drag, so it's polled on the same slow
		# tick as everything else that changes without announcing itself.
		_refresh_follow_state_label()

## Compass directions for the way-home readout. Eight of them: four is not
## enough to steer by on a 144-cell map, sixteen is more precision than a text
## line can carry.
const COMPASS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

## "Cell 42, 60  ·  Band 2 — Contested Wilderness  ·  Lair 24 cells W"
##
## Three questions the player has on the world map and cannot answer from the
## viewport: where am I, how deep am I, and which way is home. The band half is
## the only consumer of WORLD_MAP_PLAN §6's data today -- R2's encounter and
## loot tables are the ones it exists for.
func _refresh_orientation() -> void:
	if orientation_label == null or world_map == null or villain == null:
		return
	var cell: Vector2i = world_map.cell_at(villain.position)
	var band: Dictionary = world_map.band_at(villain.position)
	var lair: Vector2 = world_map.cell_centre_px(
		world_map.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2))
	var to_lair: Vector2 = lair - villain.position
	var cells_home: int = roundi(to_lair.length() / float(WorldMap.CELL_SIZE))
	var text := "Cell %d, %d   ·   Band %d — %s" % [cell.x, cell.y, band["band"], band["name"]]
	if cells_home <= 1:
		text += "   ·   At the lair"
	else:
		var octant: int = wrapi(roundi(to_lair.angle() / (TAU / 8.0)), 0, 8)
		text += "   ·   Lair %d cells %s" % [cells_home, COMPASS[octant]]
	if travel_log and travel_log.elapsed() >= 0.0:
		text += "   ·   Away %s" % TravelLog._fmt(travel_log.elapsed())
	orientation_label.text = text
	if minimap:
		minimap.queue_redraw()

## Follow on: bright. Follow off: dim, and it names the key that brings it back.
func _refresh_follow_state_label() -> void:
	if follow_state_label == null or villain_controller == null:
		return
	follow_state_label.text = villain_controller.follow_status_text()
	follow_state_label.modulate = (Color(0.75, 0.90, 0.75)
		if villain_controller.following else Color(1, 1, 1, 0.45))

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

	followers_layer = Node2D.new()
	followers_layer.name = "FollowersLayer"
	followers_layer.y_sort_enabled = true
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
	workers_layer.y_sort_enabled = true
	settlement.add_child(workers_layer)

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

## Token art for a follower, preferring the data-driven races.json sprite and
## degrading through the legacy species map to a generic portrait. Three tiers
## because followers can arrive by two different paths -- the race roster
## (everything current) and the superseded followers.json templates (Ghoul,
## Wraith), which have a species but no race_id.
func _token_sprite_for(follower) -> String:
	if follower.race_id != "":
		var from_data: String = RaceCatalog.sprite(follower.race_id)
		if from_data != "":
			return from_data
	return SPECIES_SPRITES.get(follower.species, FALLBACK_SPECIES_SPRITE)

func _spawn_token(follower) -> void:
	var token := FollowerToken.new()
	followers_layer.add_child(token)
	var sprite_path: String = _token_sprite_for(follower)
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
	# Workers now have their own commissioned art rather than borrowing a
	# Follower portrait -- Skeleton_Worker.png, via the same races.json lookup
	# every other unit uses. They still read as interchangeable by design:
	# every worker is the same skeleton, which is the point.
	var sprite_path: String = RaceCatalog.sprite(Worker.RACE_ID)
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

	# ORDER MATTERS. Sibling Controls are drawn -- and offered mouse input -- in
	# child order, last on top. The bottom command bar used to be built last,
	# which put it over the two floating panels: the event panel's choice
	# buttons hang below the screen's centre line, landed underneath the command
	# bar, were tinted by its translucent background (they looked *disabled*),
	# and had their clicks swallowed by it. A recruit offer became genuinely
	# impossible to answer. The floating panels are built last now so they sit
	# above the bar, and _show_event_panel() also keeps the event panel inside
	# the visible band so it never covers the bar in the first place.
	_build_top_bar(hud_root)
	_build_necro_badge(hud_root)
	_build_alert_stack(hud_root)
	_build_placement_hint(hud_root)
	_build_bottom_shell(hud_root)
	_build_inspection_panel(hud_root)
	_build_event_panel(hud_root)

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

	# Dark Essence gets an icon; the other four are still text. The source art
	# is 1024px square, so it's scaled into a fixed 20x20 box by the
	# TextureRect rather than by a Sprite2D scale factor -- Controls size
	# themselves, and EXPAND_IGNORE_SIZE is what stops the raw 1024px asking
	# for a 1024px-tall top bar.
	var essence_icon := TextureRect.new()
	if ResourceLoader.exists(ICON_DARK_ESSENCE):
		essence_icon.texture = load(ICON_DARK_ESSENCE)
	else:
		push_warning("Main: Dark Essence icon not found at %s" % ICON_DARK_ESSENCE)
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
	necro_badge.pressed.connect(func(): _inspect(necromancer_token, _build_necromancer_actions))
	hud_root.add_child(necro_badge)

	# Follow state, small, immediately under the badge -- the one bit of camera
	# mode the player has to be able to read at a glance, since a right-drag
	# silently drops out of it.
	follow_state_label = Label.new()
	follow_state_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	follow_state_label.position = Vector2(54, 50)
	follow_state_label.add_theme_font_size_override("font_size", 10)
	hud_root.add_child(follow_state_label)
	_refresh_follow_state_label()

	# Orientation, always visible. The minimap answers this too, but it lives in
	# the command bar, which collapses -- and 9216px of world is exactly the
	# situation where the player must never be one keystroke away from lost.
	orientation_label = Label.new()
	orientation_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	orientation_label.position = Vector2(54, 64)
	orientation_label.add_theme_font_size_override("font_size", 10)
	orientation_label.modulate = Color(1, 1, 1, 0.72)
	hud_root.add_child(orientation_label)

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

## Deliberately TOP_LEFT-anchored and positioned by hand in _show_event_panel().
## PRESET_CENTER anchors the panel's *top-left corner* to the screen centre --
## it grows down and right from there rather than being centred on it -- which
## is how its choice buttons ended up under the bottom command bar.
func _build_event_panel(hud_root: Control) -> void:
	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	event_panel.custom_minimum_size = Vector2(280, 0)
	event_panel.add_theme_stylebox_override("panel", _panel_style())
	event_panel.visible = false
	hud_root.add_child(event_panel)

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
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.setup(world_map, fog, villain, camera)
	minimap_column.add_child(minimap)
	minimap_hint = Label.new()
	minimap_hint.add_theme_font_size_override("font_size", 9)
	minimap_hint.modulate = Color(1, 1, 1, 0.55)
	minimap_hint.text = "○ lair   ● you"
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
	header.text = "Gathering priorities — workers serve the top resource still under its threshold"
	_compact(header)
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
		_compact(up)
		up.custom_minimum_size = Vector2(PRIORITY_ARROW_WIDTH, PRIORITY_ROW_HEIGHT)
		up.pressed.connect(func(): worker_system.move_priority(kind, -1))
		row.add_child(up)

		var down := Button.new()
		down.text = "v"
		down.tooltip_text = "Lower %s priority" % kind
		down.disabled = i == worker_system.priorities.size() - 1
		_compact(down)
		down.custom_minimum_size = Vector2(PRIORITY_ARROW_WIDTH, PRIORITY_ROW_HEIGHT)
		down.pressed.connect(func(): worker_system.move_priority(kind, 1))
		row.add_child(down)

		var name_label := Label.new()
		name_label.text = "%d. %s" % [i + 1, kind.capitalize()]
		name_label.custom_minimum_size = Vector2(70, 0)
		_compact(name_label)
		row.add_child(name_label)

		var stop_label := Label.new()
		stop_label.text = "stop at"
		_compact(stop_label)
		stop_label.modulate = Color(1, 1, 1, 0.6)
		row.add_child(stop_label)

		# A real SpinBox rather than the codebase's usual +/- button pair:
		# thresholds are an arbitrary number the player types, not a small
		# fixed choice set, which is exactly the case the button-pair
		# convention doesn't cover.
		# The SpinBox is what actually set the old 31px row height -- its
		# default minimum is the tallest thing in the row. Capping it here is
		# most of the compaction; its internal LineEdit needs the font
		# override too or it forces the height back up.
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999
		spin.step = 5
		spin.value = entry["threshold"]
		spin.custom_minimum_size = Vector2(66, PRIORITY_ROW_HEIGHT)
		spin.add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
		spin.get_line_edit().add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
		spin.value_changed.connect(func(v: float): worker_system.set_threshold(kind, int(v)))
		row.add_child(spin)

		var status := Label.new()
		_compact(status)
		priority_status_labels[kind] = status
		row.add_child(status)

		workers_row.add_child(row)

	# Workforce census and map stock share one line. They used to be two
	# labels, which cost ~16px of a band that had none to spare, and they read
	# fine together -- "who is working" next to "what is left to work on".
	workforce_label = Label.new()
	_compact(workforce_label)
	workforce_label.modulate = Color(1, 1, 1, 0.75)
	workers_row.add_child(workforce_label)

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
		var stock: String = resource_field.stock_summary() if resource_field else ""
		workforce_label.text = "%s   —   %s" % [worker_system.workforce_summary(), stock]

## Shrinks a Control to the priority list's compact metrics. Godot's default
## theme gives Buttons and SpinBoxes a ~31px minimum height, which is fine for
## the main action buttons but far too tall for a four-row list crammed into
## the bottom band.
func _compact(c: Control) -> void:
	c.add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
	if c is Button:
		# Trim the vertical padding too -- the font override alone doesn't
		# shrink a Button, its StyleBox content margins set the floor.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxEmpty.new()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			c.add_theme_stylebox_override(state, sb)

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
		_toggle_demolish_mode()  # the three click-to-target modes are mutually exclusive
	_cancel_rally_placement()
	# The inspector would sit there describing something you're no longer
	# looking at, and its Close button would be a click that doesn't place a
	# building. Placement mode owns the screen.
	_close_inspector()
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
	_cancel_rally_placement()
	_demolish_mode = not _demolish_mode
	_restyle_demolish_button()
	if _demolish_mode:
		_close_inspector()  # same reasoning as _enter_placement_mode
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
	# _closest_token_hit() was fixed for.
	if villain and world_pos.distance_to(villain.position) <= necromancer_token.hit_radius():
		_inspect(necromancer_token, _build_necromancer_actions)
		return true

	var hit_follower: Follower = _closest_token_hit(follower_tokens, world_pos)
	if hit_follower:
		_inspect(hit_follower)
		return true

	var hit_worker: Worker = _closest_token_hit(worker_tokens, world_pos)
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
			_inspect(rp, _build_rally_actions)
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
		_inspect(building, _actions_for_building(building))
		return true

	# --- 4. Ground -----------------------------------------------------------
	_close_inspector()
	return true

## Which action-button builder (if any) a building contributes. The Keep and
## the Barracks are the only two with menus; everything else is pure
## information, which is why this is a two-line check rather than a registry.
func _actions_for_building(building: Building) -> Callable:
	if building.is_main_building:
		return _build_keep_actions
	if building.category == "housing_intake":
		return _build_barracks_actions
	return Callable()

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

## Shared proximity hit-test for both follower_tokens and worker_tokens --
## Laborers roam freely rather than sitting in grid cells, so this measures
## distance rather than resolving a cell. Returns the closest Worker/Follower
## within `radius`, or null.
##
## **Measures the Laborer's own `position`, not the token's.** They agree to
## within a frame in normal play, but the token is a pure view that copies it
## in `_process` -- so the token is always one frame stale, and a follower sent
## away on a bounty has a token that stopped mirroring entirely and glided off
## to the gate. Hit-testing the view would mean clicking a ghost at the gate
## and missing the real unit. The Dictionary keys *are* the simulation objects,
## so this costs nothing.
##
## Tokens that are hidden (away on a bounty/mission) are skipped: they're off
## the map, so there's nothing there to click.
##
## **The radius comes from the token, not from a number passed in here.** It
## used to be a hardcoded 20.0 for followers and 16.0 for workers, which was
## fine while they were drawn at 40 and 32 -- and became wrong the moment the
## art grew, leaving clicks landing beside a unit the player was aiming at.
## `hit_radius()` derives from the same target-size constant that scales the
## sprite, so the two can no longer drift apart.
func _closest_token_hit(tokens: Dictionary, world_pos: Vector2):
	var best = null
	var best_dist := INF
	for key in tokens.keys():
		var token: Node2D = tokens[key]
		if token == null or not token.visible:
			continue
		var d: float = key.position.distance_to(world_pos)
		if d <= token.hit_radius() and d < best_dist:
			best_dist = d
			best = key
	return best

## Returns the y-coordinate just below the top resource bar's actual current
## height, with a small margin -- used to position the inspection panel each
## time it opens, rather than a hardcoded number.
func _menu_open_y() -> float:
	return top_panel.size.y + 12.0

# ---------------- Inspection panel action builders ----------------
#
# These are the *only* things about a clickable that don't come from its own
# get_inspect_data(): buttons, which call handlers that live on this node. Each
# is handed the panel's action VBox to fill. See InspectionPanel's header for
# why the split is drawn here.

## The old Keep menu, now the Throne's action block.
func _build_keep_actions(box: VBoxContainer) -> void:
	_add_button(box, "Recruit Worker (5 Bones)", _recruit_worker)

	# Not a real feature yet -- a visible placeholder so clicking the Keep
	# already shows where building upgrades will eventually live, per the
	# "possibly get upgrades down the road" design note, rather than that
	# needing a whole new menu discovered from scratch later.
	var upgrades_label := Label.new()
	upgrades_label.text = "Upgrades -- coming soon"
	upgrades_label.modulate = Color(1, 1, 1, 0.5)
	box.add_child(upgrades_label)

	box.add_child(HSeparator.new())
	var surrender := Button.new()
	surrender.text = "Surrender"
	surrender.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	surrender.tooltip_text = "Abandon this run and start over."
	surrender.pressed.connect(_surrender_and_restart)
	box.add_child(surrender)

func _surrender_and_restart() -> void:
	_close_inspector()
	GameState.reset()
	get_tree().reload_current_scene()

## His spellbook. Command Undead is the first real entry -- everything else is
## still the "visible promise" treatment (a real disabled Button, so the shape
## of the future feature is legible).
func _build_necromancer_actions(box: VBoxContainer) -> void:
	var cast := Button.new()
	cast.text = "Command Undead" if not undead_command.is_active() else "Command Undead — move rally point"
	cast.tooltip_text = "Plant a rally point. Every skeleton marches to it and stops gathering."
	cast.pressed.connect(_enter_rally_placement_mode)
	box.add_child(cast)

	if undead_command.is_active():
		var dismiss := Button.new()
		dismiss.text = "Dismiss the rally point"
		dismiss.tooltip_text = "Release the dead back to the gathering priorities."
		dismiss.pressed.connect(func():
			undead_command.dismiss()
			inspector.refresh()
		)
		box.add_child(dismiss)

	var more := Button.new()
	more.text = "Further spells — coming soon"
	more.disabled = true
	box.add_child(more)

	box.add_child(HSeparator.new())
	# The camera escape hatch, given a button as well as a key. The key (F) is
	# the fast path; this is the discoverable one, and it's how you find out the
	# key exists.
	var follow := Button.new()
	follow.text = "Stop following (F)" if villain_controller.following else "Follow him (F)"
	follow.tooltip_text = "Keep the camera centred on the Necromancer. Any right-drag or arrow-key pan drops out of it."
	follow.pressed.connect(func():
		villain_controller.toggle_follow()
		_refresh_follow_state_label()
		inspector.refresh()
	)
	box.add_child(follow)

## Order buttons for the rally point itself. Lives here rather than on
## RallyPoint for the usual reason -- these call into UndeadCommand, and the
## inspectable object is deliberately data-only. See InspectionPanel's header.
func _build_rally_actions(box: VBoxContainer) -> void:
	var current: int = undead_command.rally_point.order if undead_command.is_active() else -1
	for order in [RallyPoint.Order.DEFEND, RallyPoint.Order.PATROL, RallyPoint.Order.ATTACK]:
		var o: int = order  # explicit re-bind for the closure
		var b := Button.new()
		b.text = RallyPoint.order_name(o)
		b.tooltip_text = RallyPoint.ORDER_BLURB.get(o, "")
		b.disabled = o == current
		b.pressed.connect(func():
			undead_command.set_order(o)
			inspector.refresh()
		)
		box.add_child(b)

	box.add_child(HSeparator.new())
	var move := Button.new()
	move.text = "Move the rally point"
	move.pressed.connect(_enter_rally_placement_mode)
	box.add_child(move)

	var dismiss := Button.new()
	dismiss.text = "Dismiss — back to work"
	dismiss.add_theme_color_override("font_color", Color(0.95, 0.75, 0.5))
	dismiss.pressed.connect(func():
		undead_command.dismiss()
		_close_inspector()
	)
	box.add_child(dismiss)

func _enter_rally_placement_mode() -> void:
	if _pending_building_id != "":
		_cancel_placement()
	if _demolish_mode:
		_toggle_demolish_mode()
	_close_inspector()
	_rally_placement_mode = true
	build_hint_label.text = "Command Undead — click where the dead should rally (Esc to cancel)"
	build_hint_label.visible = true

func _cancel_rally_placement() -> void:
	_rally_placement_mode = false
	build_hint_label.visible = false

func _place_rally_point(world_pos: Vector2) -> void:
	# Keeps whatever order is already in force when the point is moved, so
	# re-siting a patrol doesn't silently demote it to defend.
	var order: int = undead_command.rally_point.order if undead_command.is_active() else RallyPoint.Order.DEFEND
	undead_command.cast(world_pos, order)
	_cancel_rally_placement()
	_inspect(undead_command.rally_point, _build_rally_actions)

## The old Barracks panel, now the Barracks' action block. Lists who is living
## there with the labor skills that decide what they're actually good for --
## the player needs those side by side to answer "is this dwarf worth a house?".
## The occupancy count itself is a details row now (Building.get_inspect_data),
## not repeated here.
func _build_barracks_actions(box: VBoxContainer) -> void:
	if GameState.followers.is_empty():
		var empty := Label.new()
		empty.text = "No residents yet. Recruits will arrive."
		empty.add_theme_font_size_override("font_size", 11)
		empty.modulate = Color(1, 1, 1, 0.6)
		box.add_child(empty)

	# Two sections: people still occupying a slot, and people who've moved out.
	# The settled list stays visible because morale keeps mattering after
	# they're housed -- a housed recruit still eats and can still desert.
	_add_roster_section(box, "In the Barracks", false, true)
	_add_roster_section(box, "Settled in town", true, false)

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

## One roster block. `housed` selects which half of the roster to list;
## `with_fund_button` adds the fund-a-house action, which only makes sense for
## people who haven't got one yet.
func _add_roster_section(box: VBoxContainer, heading: String, housed: bool, with_fund_button: bool) -> void:
	var members: Array = GameState.followers.filter(func(f): return f.is_housed == housed)
	if members.is_empty():
		return
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 11)
	head.modulate = Color(1, 1, 1, 0.55)
	box.add_child(head)

	for f in members:
		# Stacked rather than one wide row: the inspection panel is ~330px, and
		# the old single-line layout assumed a panel that sized itself to
		# whatever it held. The full stat block survives -- it just wraps.
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 1)

		var info := Label.new()
		info.add_theme_font_size_override("font_size", 11)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
		info.text = "%s — %s (%s)  M%d G%d I%d L%d  W%d M%d F%d  morale %d/10  [%s]" % [
			f.label(), f.species, f.category,
			f.might, f.guile, f.influence, f.loyalty,
			f.woodcutting, f.mining, f.foraging,
			f.morale, f.status_label(),
		]
		# Morale colour beats the exceptional gold when someone is in trouble --
		# a starving star recruit is news, and the star is still in their name.
		if f.morale <= MoraleSystem.DEPARTURE_MORALE:
			info.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		elif f.morale <= MoraleSystem.MISCHIEF_MORALE:
			info.add_theme_color_override("font_color", Color(0.95, 0.70, 0.40))
		elif f.is_exceptional:
			info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		entry.add_child(info)

		if with_fund_button:
			var target: Follower = f  # explicit re-bind for the closure
			var fund := Button.new()
			var cost := SettlementGrid.HOUSE_COST
			fund.text = "Fund house (%d wood, %d stone)" % [cost["wood"], cost["stone"]]
			fund.tooltip_text = "They pick the spot themselves, by race. Frees a Barracks slot."
			fund.disabled = not GameState.can_afford_cost(cost)
			fund.pressed.connect(func(): _fund_house(target))
			entry.add_child(fund)

		box.add_child(entry)

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

	EventBus.recruit_housed.connect(func(_f, _cell): _populate_build_row())
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
	EventBus.building_removed.connect(func(b, _c):
		_update_stats_label()
		_populate_build_row()
		# Demolishing what you're looking at. queue_free() is deferred, so the
		# panel's own is_instance_valid() guard wouldn't notice until next frame.
		if inspector.current_source() == b:
			_close_inspector()
	)
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
	_render_event_panel(event)
	_show_event_panel()

## Split out from _on_event_triggered so an *open* offer can be re-rendered in
## place when the world changes underneath it -- see _refresh_open_offer().
func _render_event_panel(event: Dictionary) -> void:
	for child in event_panel.get_children():
		event_panel.remove_child(child)
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

func _show_event_panel() -> void:
	event_panel.visible = true
	# Above every other HUD element, including the bottom bar. Belt and braces
	# with the build order in _build_ui -- a decision the player has to answer
	# must never be the thing that ends up underneath something else.
	event_panel.move_to_front()
	_position_event_panel()

## Centres the panel in the **visible map band** -- between the top resource
## strip and the bottom command bar -- rather than in the raw window, and
## clamps it so a tall offer never spills over the command bar. Same band logic
## the camera framing uses.
##
## Runs over two frames because a Control's size isn't final until layout has
## settled; the first pass uses the minimum size so it is never wildly wrong in
## the meantime.
func _position_event_panel() -> void:
	_place_event_panel_using(event_panel.get_combined_minimum_size())
	await get_tree().process_frame
	if event_panel.visible:
		_place_event_panel_using(event_panel.size)

func _place_event_panel_using(panel_size: Vector2) -> void:
	var view: Vector2 = get_viewport_rect().size
	var band_top: float = (top_panel.size.y if top_panel else 0.0) + 8.0
	var band_bottom: float = view.y - float(BOTTOM_BAR_HEIGHT) - 8.0
	var y: float = band_top + maxf(0.0, (band_bottom - band_top - panel_size.y) * 0.5)
	event_panel.position = Vector2(
		maxf(8.0, (view.x - panel_size.x) * 0.5),
		clampf(y, band_top, maxf(band_top, band_bottom - panel_size.y))
	)

## A recruit offer is a live decision, not a snapshot. It used to freeze its
## choices at the moment it fired, so a player who funded a house to make room
## while the offer was on screen was still stuck with the two turn-away
## variants -- the freed slot did nothing until the offer expired. Polled
## rather than wired to a signal because occupancy moves for several unrelated
## reasons (housing, desertion, another recruit, demolishing the Barracks) and
## EventSystem.refresh_recruit_offer() is a no-op unless the answer actually
## changed.
func _refresh_open_offer() -> void:
	if not event_panel.visible or current_event.is_empty():
		return
	if not event_system.refresh_recruit_offer(current_event):
		return
	_render_event_panel(current_event)
	_position_event_panel()
	if current_event.get("has_room", false):
		_log("[color=lightgreen]A Barracks slot opened — %s can be taken in after all.[/color]"
			% current_event.get("title", "the recruit"), "events characters")
		_alert("Room found for %s." % current_event.get("title", "a recruit"), "good")

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
	# them (Wood/Stone build, Bones raise workers, Food feeds living recruits).
	# Dark Essence trails behind its icon -- locked at 0 for the whole
	# foundation build, but visible as the roadmap promise that Stage 4
	# unlocks it.
	lbl_resources_left.text = "Wood: %d   Stone: %d   Bones: %d   Food: %d" % [
		GameState.wood, GameState.stone, GameState.bones, GameState.food
	]
	if lbl_dark_essence:
		lbl_dark_essence.text = str(GameState.dark_essence)
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
