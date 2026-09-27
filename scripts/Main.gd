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
## The villain, as data -- position, hp, attributes, carry, escort. **This node holds
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
## The minimap and its legend together, so **M** hides both. The P2 human check
## could not run "Throne to village by ground alone" strictly because there was
## no way to turn the map off (`docs/history/2026-08-27-r1-playtest-notes.md`),
## and the R2 exit check needs the same thing. Default on.
var minimap_column: VBoxContainer

## Dev-only labelled markers over every active site, toggled with F3. Never
## reachable in an exported build -- see `_toggle_site_overlay()`.
## The return leg: party capacity, the deposit at the Throne, dropping, and what
## death does to an unbanked haul. See scripts/villain/SortieSystem.gd.
var sortie_system: SortieSystem

## The run as a thing that ends (2026-09-26 ruling): death ends it unless a
## Second Wake is left, XP banks as it is earned, and the run-end screen shows
## the result. See scripts/run/RunLifecycle.gd.
var run_lifecycle: RunLifecycle
var run_summary: RunSummary
## Space/P/Esc pause menu and the once-per-session title (review 2026-09-26:
## no title, no pause). See scripts/ui/PauseMenu.gd and TitleScreen.gd.
var pause_menu: PauseMenu
var title_screen: TitleScreen
## Flee the region: pick what to carry out (ROGUELITE_REWORK 17.7).
var keep_dialog: KeepItemsDialog
## The Items window: the ground, the bag, the worn (2026-09-26).
var items_dialog: ItemsDialog
## Opens by itself when a site drops items at his feet -- only in the real game.
## A harness looting a hundred sites must not be paused by a window it never
## closes, so harnesses open it by hand.
var auto_open_items: bool = false
## The Lair (section 10, 17.6): the stash, the hall, and what to risk next run.
var lair_screen: LairScreen
## Set the first time the title is shown this session, so "Begin a new run"
## from the run-end screen goes straight back in. Static: it outlives the scene
## reload a new run does.
static var _title_seen: bool = false

## The Raven (R2e): honest dawn pings, never a fog reveal. See Raven.gd.
var raven: Raven

## The living village (LIVING_WORLD L0/L1): a settlement owned by the lordship,
## with its own stockpile, jobs and people.
var village: Village
## The Adventurers' Guild and the people who run to it (LIVING_WORLD L2).
var guild: Guild
var witnesses: Witnesses
## "Follow this road to the Adventurers' Guild." -- the first run's only hint
## (LIVING_WORLD section 3, a placeholder for a tutorial).
var opening_popup: PanelContainer

## **Where he wakes** (LIVING_WORLD section 3, ruled 2026-09-26): on the worn
## track at the east edge of the lair band, the road running on toward the
## guild. The lair is a marked site a few cells off it; the Throne is there.
## `verify_guild` checks it is road and inside the lair band -- move it only
## with the map.
const ROADSIDE_SPAWN_CELL := Vector2i(37, 60)
const OPENING_POPUP_TEXT := "Follow this road to the Adventurers' Guild."
## Which way, from where he stands -- the track forks four ways at the lair's
## edge, and the first playtest took the wrong one.
func opening_popup_text() -> String:
	if guild == null or villain == null:
		return OPENING_POPUP_TEXT
	return "%s  The hall is just ahead, to the %s." % [OPENING_POPUP_TEXT, Guild.compass(guild.position - villain.position)]
## Site discovery is checked on this clock rather than every frame -- it is a
## distance test over fifteen sites, and a quarter-second late is invisible.
var _discovery_timer: float = 0.0
const DISCOVERY_INTERVAL: float = 0.25

var debug_site_overlay: DebugSiteOverlay

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

## The floating damage numbers. Pure view -- see scripts/ui/CombatFeedback.gd.
var combat_feedback: CombatFeedback

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
## What the HUD keeps clear at the bottom (the action bar). The old command bar
## was 250 px across the whole width; the redo floats everything.
const BOTTOM_BAR_HEIGHT := 96

const MAX_ALERTS := 3            # oldest alert pin is dropped once a 4th arrives
const MAX_HISTORY_ENTRIES := 200 # oldest history-log row is dropped past this cap

func _ready() -> void:
	Controls.ensure()
	_strip_dev_bridges()
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
	# The opening, in one line. He wakes on the road with no dead and too few
	# bones to raise one (rulings 2026-09-26), so the first thing the player
	# needs to know is where the dead are: down the south track past the guild
	# (fresh_grave_scree, the roadside grave) and in the hollow north-west of
	# the Throne (fresh_grave_hollow).
	_log("[color=#b8a0e0]He wakes on the road at the edge of his lair with no dead, and three bones will not raise one. The Adventurers' Guild stands just up the road; past it, beside the track south, is a fresh grave — and there is another in the hollow north-west of the Throne.[/color]", "events")
	_show_title_once()

## The title, over a paused world, the first time the game runs this session --
## and only when Main *is* the game (a harness instantiating Main never sees it).
func _show_title_once() -> void:
	if _title_seen or not (is_inside_tree() and get_tree().current_scene == self):
		return
	_title_seen = true
	var p: MetaProfile = run_lifecycle.profile
	var recent: Array = p.recent(villain.class_id, 1)
	title_screen.show_title({
		"level": p.level(villain.class_id),
		"xp": p.xp(villain.class_id),
		"runs": p.runs(villain.class_id),
		"last_epitaph": String(recent[0].get("epitaph", "")) if not recent.is_empty() else "",
	})
	get_tree().paused = true

## **Release builds carry no dev bridges.** The three godot_mcp autoloads poll
## user:// every frame and one of them evaluates Expressions from a file
## (review 2026-09-26, 2.11). They are editor tooling; in an exported build they
## are freed on the first frame. Debug runs keep them -- the MCP workflow needs
## them there.
func _strip_dev_bridges() -> void:
	if OS.is_debug_build():
		return
	for n in ["MCPRuntimeBridge", "MCPInputBridge", "MCPScreenshotBridge"]:
		var node: Node = get_tree().root.get_node_or_null(n)
		if node:
			node.queue_free()

func _open_pause_menu() -> void:
	if pause_menu == null or pause_menu.is_open():
		return
	if (run_summary and run_summary.is_showing()) or (title_screen and title_screen.is_showing()):
		return
	pause_menu.open()

# ---------------- Camera framing ----------------

## Where every run begins (see ROADSIDE_SPAWN_CELL). Falls back to the Throne
## when there is no world map to stand on.
func roadside_spawn() -> Vector2:
	return world_map.cell_centre_px(ROADSIDE_SPAWN_CELL) if world_map else _throne_world_centre()

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
	# The HUD floats over the world now; nothing spans the width to inset for.
	camera.ui_bottom_inset = 0.0

## Frames the opening: on *him*, because he wakes on the road, not at the
## Throne (the name is older than the roadside spawn).
func _frame_camera_on_throne() -> void:
	_sync_camera_insets()
	camera.center_on(villain.position if villain else _throne_world_centre())

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
	villain.place_at(roadside_spawn())
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
	# Who has found what, from the same discs that light the fog -- read-only
	# over the fog itself (RAVEN_SPEC: the bird must never write it).
	_discovery_timer += delta
	if _discovery_timer >= DISCOVERY_INTERVAL and world_sites and villain:
		_discovery_timer = 0.0
		world_sites.update_discovery(_fog_sources())
	hud_top_bar.refresh_orientation()
	economy_tab.refresh_status()
	_poll_timer += delta
	if _poll_timer >= INSPECTOR_REFRESH_INTERVAL:
		_poll_timer = 0.0
		if inspector and inspector.is_open():
			inspector.refresh()
		event_panel_ui.refresh_open_offer()
		_refresh_hud_state()
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
	# The Barrow Lantern widens his own disc once it is banked -- a relic effect
	# expressed as data, read here rather than anywhere near FogOfWar, which
	# still knows nothing about relics.
	_fog_source_buf.append([villain.position,
		FogOfWar.REVEAL_RADIUS_CELLS + villain.fog_reveal_bonus()])
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

	# Floating damage numbers. A sibling of the token layers in the settlement's
	# coordinate space; it subscribes to EventBus.damage_shown itself and is
	# handed nothing, because a view of an event needs no references.
	combat_feedback = CombatFeedback.new()
	combat_feedback.name = "CombatFeedback"
	settlement.add_child(combat_feedback)

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

	# **Built before every other listener**, because SORTIE_SPEC §6 requires the
	# unbanked haul cleared "before anything else reads them" and Godot calls
	# handlers in connection order. Everything it needs already exists: the world
	# map and its sites are built at the top of this function, the settlement
	# before that. One instance per villain, holding him as a field.
	sortie_system = SortieSystem.new()
	sortie_system.name = "SortieSystem"
	sortie_system.villain = villain
	sortie_system.settlement = settlement
	sortie_system.world = world_map
	sortie_system.world_sites = world_sites
	add_child(sortie_system)
	# Loot fills the villain first and his escort second (§2's filling order).
	# Set on the container, so sites created later -- a dropped cache -- inherit
	# it; the sites ask through this rather than reaching for the villain's hands.
	if world_sites:
		world_sites.party_filler = func(who, kind: String, amount: int):
			return sortie_system.take_into_party(who, kind, amount)
		for site in world_sites.sites:
			site.party_filler = world_sites.party_filler

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
	event_system.settlement = settlement  # Barracks gate + free-slot checks query the grid

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
	# **The dusk gate** (LOOT_SITES_SPEC section 3b) and the site guardians. The
	# world map is built before this, so the dens already exist -- which they
	# have to, because the first dusk asks whether any of them still stands.
	combat_system.world_sites = world_sites
	add_child(combat_system)
	# Who he is fighting, asked rather than stored. His engagement membership
	# lives in CombatSystem (NECROMANCER_SPEC §9) precisely so that nothing on
	# him can root him; the panel gets a read-only question instead of a field.
	villain.foe_provider = func(): return combat_system.villain_foe_name()

	# Command Undead. Needs combat_system to hand fights to, so it comes after.
	undead_command = UndeadCommand.new()
	undead_command.name = "UndeadCommand"
	undead_command.settlement = settlement
	undead_command.worker_system = worker_system
	undead_command.combat_system = combat_system
	undead_command.world = world_map
	undead_command.villain = villain
	add_child(undead_command)

	# A corpse raised from a grave becomes a real skeleton, for free (ruling C,
	# 2026-09-26). Set on the container so a cache spawned later inherits it,
	# same as the party filler.
	if world_sites:
		world_sites.raise_handler = func(at: Vector2, _who, _site):
			return worker_system.raise_skeleton_at(at, worker_system.next_skeleton_name())

	# The Raven. Per villain, fields not lookups (RAVEN_SPEC section 8); markers
	# live in the settlement's coordinate space, above the fog by z-index.
	raven = Raven.new()
	raven.name = "Raven"
	raven.villain = villain
	raven.world_sites = world_sites
	raven.fog = fog
	raven.marker_parent = settlement
	add_child(raven)

	_build_village()
	_build_guild()

	_build_run_lifecycle()

## **The living village** (LIVING_WORLD L0/L1). A child of `settlement` so it
## shares the coordinate space everyone walks in; drawn under the fog by
## z-index like the sites. Everything it needs is handed to it.
func _build_village() -> void:
	village = Village.new()
	village.name = "Village"
	village.y_sort_enabled = true
	village.world_sites = world_sites
	village.combat_system = combat_system
	village.villain = villain
	village.day_provider = func(): return day_night.day_number if day_night else 1
	settlement.add_child(village)
	if not village.build(world_map):
		village.queue_free()
		village = null
		return
	combat_system.village = village

## **The Adventurers' Guild** (LIVING_WORLD L2) and **the witnesses** who run to
## it. Built after the village, whose stores its delivery jobs read and whose
## people are the runners.
func _build_guild() -> void:
	guild = Guild.new()
	guild.world_sites = world_sites
	guild.village = village
	guild.day_provider = func(): return day_night.day_number if day_night else 1
	guild.party_filler = sortie_system.take_into_party
	if not guild.build(world_map):
		guild.free()
		guild = null
		return
	settlement.add_child(guild)
	# A public hall: its ground is known from the first frame, so he can see it
	# from where he wakes (first playtest, 2026-09-26).
	if fog:
		fog.reveal_permanently(guild.known_ground())
	witnesses = Witnesses.new()
	witnesses.name = "Witnesses"
	witnesses.villain = villain
	witnesses.village = village
	witnesses.guild = guild
	witnesses.day_night = day_night
	add_child(witnesses)
	if village:
		village.witnesses = witnesses

## The first run's one hint (LIVING_WORLD section 3). Shown when the title's
## Begin is pressed and this class has never finished a run; never again.
func _show_opening_popup() -> void:
	if opening_popup == null:
		var layer := CanvasLayer.new()
		layer.layer = 58
		add_child(layer)
		var holder := CenterContainer.new()
		# Low, just above the command bar: the hall it points at stands up and
		# to the right of him, where a top banner would cover its roof.
		holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		holder.offset_top = -float(BOTTOM_BAR_HEIGHT) - 190.0
		holder.offset_bottom = -float(BOTTOM_BAR_HEIGHT) - 116.0
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(holder)
		opening_popup = PanelContainer.new()
		opening_popup.add_theme_stylebox_override("panel", PauseMenu.panel_style())
		holder.add_child(opening_popup)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		opening_popup.add_child(row)
		var lbl := Label.new()
		lbl.text = opening_popup_text()
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.82, 1.0))
		row.add_child(lbl)
		var ok := Button.new()
		ok.text = "Go"
		ok.custom_minimum_size = Vector2(64, 40)
		HudStyle.style_button(ok, true, 15)
		ok.pressed.connect(func(): opening_popup.visible = false)
		row.add_child(ok)
	opening_popup.visible = true

## **Last**, so its `villain_died` handler runs after SortieSystem's (the haul)
## and CombatSystem's (out of every fight) -- it only decides what happens next.
##
## The profile is only written to disk when this scene is the one the game is
## running. The harnesses instantiate Main as a child of their own scene and
## kill the villain on purpose; that must never touch the player's XP.
func _build_run_lifecycle() -> void:
	var persistent: bool = is_inside_tree() and get_tree().current_scene == self
	run_lifecycle = RunLifecycle.new()
	run_lifecycle.name = "RunLifecycle"
	run_lifecycle.villain = villain
	run_lifecycle.sortie_system = sortie_system
	run_lifecycle.day_night = day_night
	run_lifecycle.profile = MetaProfile.open(MetaProfile.DEFAULT_PATH if persistent else "")
	add_child(run_lifecycle)
	# Blueprints are the profile's (LIVING_WORLD section 9.1): the build menu
	# only offers a gated building once this profile has learned it.
	BuildingCatalog.blueprint_provider = run_lifecycle.profile.knows_blueprint

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
	# Deeds are stamped in game-days (LOOT_SITES_SPEC section 6), and the site
	# layer gets the clock as a Callable rather than a DayNightCycle reference --
	# it is a container, and it should stay one.
	world_sites.day_provider = func(): return day_night.day_number if day_night else 1
	world_sites.build(world_map)

	# **Dev-only site overlay (F3).** A child of `settlement` so it shares the
	# coordinate space the sites stand in, added after them and drawing above the
	# fog by z-index. Hidden until asked for, read-only over `world_sites`, and
	# unreachable in an exported build -- the key is behind `OS.is_debug_build()`.
	debug_site_overlay = DebugSiteOverlay.new()
	debug_site_overlay.name = "DebugSiteOverlay"
	settlement.add_child(debug_site_overlay)
	debug_site_overlay.setup(world_sites, world_map)

	fog = FogOfWar.new()
	fog.name = "FogOfWar"
	settlement.add_child(fog)
	fog.setup(world_map)
	# The lair band starts revealed and stays visible -- see FogOfWar for why
	# his own valley doesn't dim when he leaves it.
	fog.reveal_permanently(world_map.lair_band)

## Stage 0 (Arrival) per FOUNDATION_SPEC section 10: the Throne of Bones and
## nothing else -- the one starting Skeleton Worker was removed 2026-09-26
## (LIVING_WORLD ruling 9; the first dead come from a grave). The Bone Pile and Dark Altar used to be
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

	# **No starting skeleton** (LIVING_WORLD ruling 9, 2026-09-26). The dead
	# come from graves -- free -- or from Raise Dead paid in bones. The starting
	# bones (3, GameState) are below Raise Dead's 5, so the first dead always
	# come from a grave.

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
	_build_hud(hud_root)
	hud_top_bar.set_minimap(minimap)   # born in the bottom shell, above
	hud_top_bar.set_sortie_system(sortie_system)
	_build_inspection_panel(hud_root)
	_build_event_panel(hud_root)

	# The run-end screen. Its own CanvasLayer above everything, and alive while
	# the tree is paused -- the run has ended underneath it.
	run_summary = RunSummary.new()
	run_summary.name = "RunSummary"
	add_child(run_summary)
	run_summary.new_run_requested.connect(_begin_new_run)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.abandon_confirmed.connect(func():
		if run_lifecycle and not run_lifecycle.ended:
			run_lifecycle.abandon())

	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	add_child(title_screen)
	title_screen.begin_requested.connect(func():
		get_tree().paused = false
		if run_lifecycle and run_lifecycle.profile.runs(villain.class_id) == 0:
			_show_opening_popup())
	title_screen.lair_requested.connect(_open_lair)
	run_summary.lair_requested.connect(_open_lair)

	items_dialog = ItemsDialog.new()
	items_dialog.name = "ItemsDialog"
	items_dialog.villain = villain
	items_dialog.sortie_system = sortie_system
	add_child(items_dialog)
	items_dialog.closed.connect(func():
		hud_top_bar.refresh_stats()
		if inspector.is_open():
			inspector.refresh())
	auto_open_items = is_inside_tree() and get_tree().current_scene == self
	inspector_actions.items_requested.connect(_open_items)

	keep_dialog = KeepItemsDialog.new()
	keep_dialog.name = "KeepItemsDialog"
	add_child(keep_dialog)
	keep_dialog.chosen.connect(func(ids: Array):
		if run_lifecycle and not run_lifecycle.flee(ids):
			_log("[color=orange]He can only flee the region from the lair.[/color]", "events"))
	pause_menu.flee_available = func(): return run_lifecycle != null and run_lifecycle.can_flee()
	pause_menu.flee_requested.connect(_request_flee)
	inspector_actions.flee_available = pause_menu.flee_available
	inspector_actions.flee_requested.connect(_request_flee)

	lair_screen = LairScreen.new()
	lair_screen.name = "LairScreen"
	add_child(lair_screen)
	# What he carries is settled when the run begins; changed in the Lair before
	# the first step, it is re-applied.
	lair_screen.closed.connect(func():
		if run_lifecycle:
			run_lifecycle.reapply_carry_in())

	hud_top_bar.refresh_stats()
	build_menu.populate()
	economy_tab.build_priority_rows()

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
	alert_stack.position = Vector2(-44, 150)
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
	inspector_actions.setup(undead_command, inspector, villain_controller, villain,
		sortie_system, world_sites)
	inspector_actions.progress_line_provider = _progress_line

## **The HUD** (the HUD redo, 2026-09-26; mockups: the "Warlords HUD redo"
## canvas). Replaces the old bottom command bar (Town / History / Research,
## Build / Bounty / Economy) with pieces that each appear when their mechanic
## first does: his dead (the roster), the action bar, a fading log ticker, the
## minimap in its corner, the History window (L), the big map (M), the Build
## tray (B), the Workforce window and Flee at home, and the new-blueprint
## banner. HudTopBar owns the two top corners.
var dead_roster: DeadRoster
var action_bar: ActionBar
var log_ticker: LogTicker
var history_window: HudWindow
var workforce_window: HudWindow
var build_tray: PanelContainer
var _build_tray_note: Label
var home_buttons: VBoxContainer
var _workforce_btn: Button
var _flee_btn: Button
var map_screen: MapScreen
var _unlock_banner: PanelContainer
var _unlock_title: Label
var _unlock_text: Label

func _build_hud(hud_root: Control) -> void:
	# His dead, under his portrait column.
	dead_roster = DeadRoster.new()
	dead_roster.name = "DeadRoster"
	dead_roster.worker_system = worker_system
	dead_roster.villain = villain
	hud_top_bar.left_column.add_child(dead_roster)
	dead_roster.unit_pressed.connect(func(u):
		_inspect(u)
		if camera:
			camera.center_on_manual(u.position))

	# The action bar, bottom centre.
	var bar_holder := CenterContainer.new()
	bar_holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar_holder.offset_top = -80
	bar_holder.offset_bottom = -14
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bar_holder)
	action_bar = ActionBar.new()
	action_bar.name = "ActionBar"
	action_bar.villain = villain
	action_bar.worker_system = worker_system
	action_bar.undead_command = undead_command
	action_bar.knows_blueprints = func() -> bool:
		return run_lifecycle != null and not run_lifecycle.profile.blueprints.is_empty()
	bar_holder.add_child(action_bar)
	action_bar.raise_pressed.connect(_recruit_worker)
	action_bar.items_pressed.connect(_open_items)
	action_bar.escort_pressed.connect(_toggle_escort)
	action_bar.rally_pressed.connect(_enter_rally_placement_mode)
	action_bar.build_pressed.connect(_toggle_build_tray)

	# The last few lines of the log, above the bar, left of centre.
	log_ticker = LogTicker.new()
	log_ticker.name = "LogTicker"
	log_ticker.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_ticker.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_ticker.offset_left = 340
	log_ticker.offset_bottom = -92
	log_ticker.offset_top = -92
	hud_root.add_child(log_ticker)

	# The minimap, bottom right, with its legend.
	minimap_column = VBoxContainer.new()
	minimap_column.name = "MinimapCorner"
	minimap_column.add_theme_constant_override("separation", 4)
	minimap_column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	minimap_column.offset_right = -14
	minimap_column.offset_bottom = -12
	hud_root.add_child(minimap_column)
	var mm_frame := PanelContainer.new()
	mm_frame.add_theme_stylebox_override("panel", HudStyle.box(Color("0d0b10"), HudStyle.BORDER, 8, 4))
	minimap_column.add_child(mm_frame)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.setup(world_map, fog, villain, camera)
	minimap.units_source = func(): return worker_system.all_units() if worker_system else []
	minimap.debug_markers_source = func():
		return debug_site_overlay.minimap_points() if debug_site_overlay else []
	minimap.raven_markers_source = func():
		return raven.minimap_points() if raven else []
	minimap.landmarks_source = func():
		return [guild.position] if guild else []
	minimap.camera_requested.connect(_on_minimap_camera_requested)
	minimap.move_requested.connect(_on_right_tap)
	mm_frame.add_child(minimap)
	minimap_hint = HudStyle.label("○ lair  ⌂ guild  ◆ raven  ● you  ·  %s: full map" % Controls.label_for("map"), 11, HudStyle.MUTED)
	minimap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	minimap_column.add_child(minimap_hint)

	# At home: Workforce (once a building works) and Flee the region.
	home_buttons = VBoxContainer.new()
	home_buttons.add_theme_constant_override("separation", 6)
	home_buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	home_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	home_buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	home_buttons.offset_right = -14
	home_buttons.offset_bottom = -(MINIMAP_SIZE + 52)
	home_buttons.custom_minimum_size = Vector2(190, 0)
	hud_root.add_child(home_buttons)
	_workforce_btn = Button.new()
	_workforce_btn.text = "Workforce"
	_workforce_btn.custom_minimum_size = Vector2(190, 42)
	HudStyle.style_button(_workforce_btn)
	_workforce_btn.pressed.connect(func(): workforce_window.toggle())
	home_buttons.add_child(_workforce_btn)
	_flee_btn = Button.new()
	_flee_btn.text = "Flee the region…"
	_flee_btn.custom_minimum_size = Vector2(190, 42)
	HudStyle.style_button(_flee_btn)
	_flee_btn.pressed.connect(_request_flee)
	home_buttons.add_child(_flee_btn)
	home_buttons.visible = false

	# The Build tray, above the action bar, opened by B.
	var tray_holder := CenterContainer.new()
	tray_holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray_holder.offset_top = -210
	tray_holder.offset_bottom = -90
	tray_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tray_holder)
	build_tray = PanelContainer.new()
	build_tray.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.BORDER_ACCENT, 10, 12))
	build_tray.visible = false
	tray_holder.add_child(build_tray)
	var tray := VBoxContainer.new()
	tray.add_theme_constant_override("separation", 8)
	build_tray.add_child(tray)
	var tray_head := HBoxContainer.new()
	tray.add_child(tray_head)
	var tray_title := HudStyle.label("Build  %s" % Controls.label_for("build"), 16)
	tray_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray_head.add_child(tray_title)
	_build_tray_note = HudStyle.label("", 12, HudStyle.MUTED)
	tray_head.add_child(_build_tray_note)
	build_menu.build_row_into(tray, settlement)
	build_menu.set_tab_visible(true)

	# Windows: History (L), Workforce.
	history_window = HudWindow.new().setup("History", 720, 520)
	history_window.name = "HistoryWindow"
	hud_root.add_child(history_window)
	_build_cmd_history(history_window.body)
	cmd_history.visible = true
	workforce_window = HudWindow.new().setup("Workforce", 620, 440)
	workforce_window.name = "WorkforceWindow"
	hud_root.add_child(workforce_window)
	economy_tab = EconomyTab.new()
	economy_tab.name = "EconomyTab"
	add_child(economy_tab)
	economy_tab.build(workforce_window.body, worker_system, resource_field)
	economy_tab.set_tab_visible(true)

	# The new-blueprint banner, top centre, for a few seconds.
	var banner_holder := CenterContainer.new()
	banner_holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_holder.offset_top = 90
	banner_holder.offset_bottom = 200
	banner_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(banner_holder)
	_unlock_banner = PanelContainer.new()
	_unlock_banner.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.ACCENT, 10, 16))
	_unlock_banner.visible = false
	_unlock_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_holder.add_child(_unlock_banner)
	var ub := VBoxContainer.new()
	ub.add_theme_constant_override("separation", 4)
	_unlock_banner.add_child(ub)
	ub.add_child(HudStyle.label("NEW BLUEPRINT", 12, HudStyle.ACCENT))
	_unlock_title = HudStyle.label("", 24)
	ub.add_child(_unlock_title)
	_unlock_text = HudStyle.label("", 14, Color("d7cce8"))
	ub.add_child(_unlock_text)

	# The big map (M), over everything else in the HUD.
	var map_layer := CanvasLayer.new()
	map_layer.layer = 50
	add_child(map_layer)
	map_screen = MapScreen.new()
	map_screen.name = "MapScreen"
	map_screen.world = world_map
	map_screen.fog = fog
	map_screen.villain = villain
	map_screen.camera = camera
	map_screen.world_sites = world_sites
	map_screen.guild = guild
	map_screen.village = village
	map_screen.raven = raven
	map_screen.worker_system = worker_system
	map_layer.add_child(map_screen)
	map_screen.build()
	map_screen.place_chosen.connect(_on_minimap_camera_requested)
	map_screen.walk_requested.connect(_on_right_tap)

	# The top corners' buttons.
	hud_top_bar.home_provider = _near_throne
	hud_top_bar.level_provider = func() -> int:
		return run_lifecycle.profile.level(villain.class_id) if run_lifecycle else 1
	hud_top_bar.stance_pressed.connect(_toggle_stance)
	hud_top_bar.items_pressed.connect(_open_items)
	hud_top_bar.map_pressed.connect(_toggle_map)
	hud_top_bar.history_pressed.connect(func(): history_window.toggle())
	hud_top_bar.guild_chip_pressed.connect(func():
		if guild:
			_on_minimap_camera_requested(guild.position))

## "Home" for the HUD: within a few cells of the Throne -- the Treasury, the
## Workforce and Flee only show there, so the roadside spawn (inside the lair
## band) opens clean.
const HOME_RADIUS_CELLS := 6.0
func _near_throne() -> bool:
	return villain != null and villain.position.distance_to(_throne_world_centre()) <= HOME_RADIUS_CELLS * float(SettlementGrid.CELL_SIZE)

## B: the Build tray. It lists what he knows and counts what he does not.
func _toggle_build_tray() -> void:
	if build_tray == null:
		return
	build_tray.visible = not build_tray.visible
	if build_tray.visible:
		build_menu.populate()
		var gated: int = 0
		for id in BuildingCatalog.all_ids():
			if BuildingCatalog.get_building(id).get("blueprint", false):
				gated += 1
		var known: int = run_lifecycle.profile.blueprints.size() if run_lifecycle else 0
		_build_tray_note.text = "%d of %d blueprints known · the rest are out in the world" % [mini(known, gated), gated]
	elif build_menu.is_placing():
		build_menu.cancel_placement()

## M: the big map.
func _toggle_map() -> void:
	if map_screen:
		map_screen.toggle()

## The home buttons, the guild chip and the blueprint banner's timer: polled
## with the inspector, a few times a second.
func _refresh_hud_state() -> void:
	if home_buttons == null or villain == null:
		return
	var home: bool = _near_throne()
	var any_building: bool = false
	for b in settlement.cells.values():
		if b != null and not b.is_main_building:
			any_building = true
			break
	_workforce_btn.visible = home and any_building
	_flee_btn.visible = home and run_lifecycle != null and run_lifecycle.can_flee()
	home_buttons.visible = _workforce_btn.visible or _flee_btn.visible
	if guild and not hud_top_bar.guild_chip.visible and guild.in_reach(villain):
		hud_top_bar.set_guild_standing(Necromancer.standing_name(villain.standing_with(Guild.FACTION)))

func _show_unlock_banner(building_name: String, how: String) -> void:
	if _unlock_banner == null:
		return
	_unlock_title.text = building_name
	_unlock_text.text = "Learned by %s. Known for every run from now on." % how
	_unlock_banner.visible = true
	_unlock_banner.modulate = Color.WHITE
	var tw := _unlock_banner.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(_unlock_banner, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func(): _unlock_banner.visible = false)

## History window content: Events/Alerts/Characters filter chips above a
## scrollable log. Every _log() call lands here (and the last few also in the
## ticker above the action bar).
func _build_cmd_history(container: VBoxContainer) -> void:
	cmd_history = VBoxContainer.new()
	cmd_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cmd_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(cmd_history)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	cmd_history.add_child(filter_row)
	for cat in ["events", "alerts", "characters"]:
		var c: String = cat
		var fb := Button.new()
		fb.text = c.capitalize()
		fb.toggle_mode = true
		HudStyle.style_button(fb, false, 13)
		fb.toggled.connect(func(pressed: bool): _on_history_filter_toggled(c, pressed))
		history_filter_buttons[c] = fb
		filter_row.add_child(fb)
	history_log_list = VBoxContainer.new()
	history_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_history.add_child(history_log_list)

# ---------------- Unit/building selection info panel ----------------

## The old bottom bar's one-line selection readout is gone with the bar (the
## HUD redo); the inspection panel says it all. Kept as a no-op for callers.
func _select_info(_unit_name: String, _klass: String, _status: String) -> void:
	pass

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
		if event.is_action_pressed("cancel"):
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
		if event.is_action_pressed("cancel"):
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
		if event.is_action_pressed("cancel"):
			_cancel_rally_placement()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_place_rally_point(settlement.get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return

	# F3 toggles the dev site overlay. **`OS.is_debug_build()` is the whole
	# safety**: in an exported build this branch is dead, the overlay stays
	# hidden forever, and the key does nothing.
	if event.is_action_pressed("debug_overlay", false, false) and OS.is_debug_build():
		_toggle_site_overlay()
		get_viewport().set_input_as_handled()
		return

	# The HUD's keys (the HUD redo, 2026-09-26): M the big map, L History, B the
	# Build tray, E the escort, C the rally point. `echo`-guarded like the rest.
	if event.is_action_pressed("map", false, false):
		_toggle_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("history", false, false):
		history_window.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build", false, false):
		if action_bar.build_btn.visible:
			_toggle_build_tray()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("escort", false, false):
		if action_bar.escort_btn.visible:
			_toggle_escort()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rally", false, false):
		if action_bar.rally_btn.visible:
			_enter_rally_placement_mode()
		get_viewport().set_input_as_handled()
		return

	# R casts Raise Dead at his feet (paid in bones). Same handler as the
	# buttons; a text field with focus never sees it because this is the
	# *unhandled* pass.
	if event.is_action_pressed("raise_dead", false, false):
		_recruit_worker()
		get_viewport().set_input_as_handled()
		return

	# I opens his items (2026-09-26).
	if event.is_action_pressed("items", false, false):
		_open_items()
		get_viewport().set_input_as_handled()
		return

	# H flips Hidden / Hunting (LIVING_WORLD ruling 15).
	if event.is_action_pressed("stance", false, false):
		_toggle_stance()
		get_viewport().set_input_as_handled()
		return

	# Space (or P) pauses. The pause menu takes its own input while open, so this
	# only ever opens it.
	if event.is_action_pressed("pause", false, false):
		_open_pause_menu()
		get_viewport().set_input_as_handled()
		return

	# Esc closes the inspector. Deliberately *below* the two placement blocks
	# above, which both return early: while you're placing or demolishing,
	# Esc cancels that mode, and the inspector is not what Esc is for. With
	# nothing left to close, Esc pauses -- the convention every PC player
	# reaches for first.
	if event.is_action_pressed("cancel"):
		if inspector.is_open():
			_close_inspector()
		else:
			_open_pause_menu()
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
	# The Raven's marks sit above the fog and answer through it: they are the
	# one thing on the map you were told about rather than shown.
	if raven:
		var mark: Node2D = raven.pick_at(world_pos)
		if mark:
			_inspect(mark)
			return true

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

	# The village's people, then its buildings and fields. After his own units
	# and the wolf, before the rally point: a villager is a character.
	if village:
		var hit_v = village.pick_at(world_pos)
		if hit_v != null:
			_inspect(hit_v)
			return true
	# The guild hall: its board is the inspector's action block.
	if guild and guild.pick_at(world_pos):
		_inspect(guild, inspector_actions.guild_actions.bind(guild))
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

	# --- 1c. Patrols and site guardians --------------------------------------
	# Both sit with the characters (WorldSites.pick_at checks them first); the
	# village buildings and landmarks rank below resource nodes for the same
	# reason settlement buildings do -- a deer standing in front of a house is
	# the thing on top. A guardian standing over its den outranks the den for
	# the same reason a wolf outranks the ground it is standing on: it is the
	# thing you meant to click, and it is the thing about to bite you.
	if world_sites:
		var hit_character = world_sites.pick_at(world_pos)
		if hit_character is Patrol or hit_character is SiteGuardian:
			_inspect(hit_character)
			return true

	# --- 2. Resource nodes ---------------------------------------------------
	# Above buildings because nodes sit mostly off-grid (the forest, the
	# deposit, the graves) and a deer can wander across the settlement, so a
	# node overlapping a building means the node is the thing on top.
	var hit_node: ResourceNode = resource_field.node_at(world_pos) if resource_field else null
	if hit_node:
		_inspect(hit_node)
		return true

	# --- 2b. World sites (village, sealed ground, landmarks, loot) -----------
	# A lootable site contributes action buttons; an inert one is pure
	# information, exactly as it was. `bind()` appends the site, so the builder
	# stays stateless -- see InspectorActions.site_actions.
	if world_sites:
		var hit_site = world_sites.pick_at(world_pos)
		if hit_site is WorldSite:
			if hit_site.lootable:
				_inspect(hit_site, inspector_actions.site_actions.bind(hit_site))
			else:
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
	# **On the right** (the HUD redo): his column owns the top left, so the
	# panel opens under the day and the map buttons, left of the alert pins,
	# and stops above the minimap corner.
	var vp: Vector2 = get_viewport_rect().size
	inspector.position = Vector2(vp.x - InspectionPanel.PANEL_WIDTH - 56.0, _menu_open_y())
	inspector.max_body_height = maxf(140.0, vp.y - _menu_open_y() - float(MINIMAP_SIZE) - 90.0)
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
	# Under the top-right column (day, Map/History, chips), whatever height it
	# laid out to.
	if hud_top_bar and hud_top_bar.right_column:
		return 12.0 + hud_top_bar.right_column.get_combined_minimum_size().y + 12.0
	return 150.0

# ---------------- Inspector action handlers ----------------
#
# The buttons themselves are built by scripts/ui/InspectorActions.gd. What
# stays here is what a press implies that only this node can do: reloading the
# run, arbitrating the rally placement mode against the build and demolish
# modes, and paying for a house (which writes to the history log).

## Surrender ends the run through the lifecycle -- XP already earned is kept,
## the chronicle gets its line, and the run-end screen offers the new run.
func _surrender_and_restart() -> void:
	_close_inspector()
	if run_lifecycle and not run_lifecycle.ended:
		# Behind a confirm: one misclick used to end the run (review 2.11 list).
		pause_menu.open_confirm_abandon()
		return
	_begin_new_run()

## The run-end screen's one button. **Resets the clock as well as the state**:
## `Engine.time_scale` is engine-global and survives a scene reload, so a run
## ended at the debug 60x used to start the next one at 60x under a HUD that
## said 1x (review 2026-09-26).
func _begin_new_run() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
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

## A site action the inspection panel asked for. Main.gd does this rather than
## `InspectorActions` for the usual reason: the site starts a channel, and the
## panel has to be told to redraw so the progress row appears immediately rather
## than on the next 0.4s poll.
func _begin_site_action(site: WorldSite, action_id: String) -> void:
	if site == null or villain == null:
		return
	var ok: bool = site.begin_action(villain, action_id)
	# Asked for by hand: the Items window opens in any build (the automatic
	# opening after a pull is the real game's only).
	if ok and action_id == "pick_up":
		items_dialog.open(site)
	# **Refresh either way.** A refused action still has something to say -- the
	# collect row comes back greyed with its reason under it -- and a press that
	# changes nothing on screen is the bug this whole pass is about.
	inspector.refresh()
	if ok:
		return
	_alert("He cannot do that from here.", "warn")

## Opens a site's four-way sheet through the **event panel**, which is the one
## choice renderer this project has (LOOT_SITES_SPEC section 3: one renderer,
## two data sources). The chosen entry comes back here and starts the channel.
##
## `sheet_choices()` decides what is even offered -- mercy is gone once the
## valuables are, and destroy-the-evidence only exists after something has been
## taken. That gating is the dilemma, so it lives on the site and not here.
func _open_site_sheet(site: WorldSite) -> void:
	if site == null or villain == null:
		return
	if not site.in_reach(villain):
		_alert("He has to be standing at it.", "warn")
		return
	var choices: Array = site.sheet_choices(villain)
	if choices.is_empty():
		_alert("There is nothing left to decide here.", "info")
		return
	var sheet: Dictionary = LootCatalog.choice_sheet(site.choices_id)
	var opened: bool = event_panel_ui.present_sheet(
		site.display_name, String(sheet.get("prompt", "")), choices,
		func(choice: Dictionary):
			if not site.begin_action(villain, "choice", choice):
				_alert("He cannot do that from here.", "warn")
			inspector.refresh())
	if not opened:
		_alert("Answer what is already in front of you first.", "warn")

## **Command Undead: Escort**, and its way back out.
##
## No placement mode and no new branch in the input arbitration — the target is
## the man casting it, which is exactly why escort is a button on his panel
## rather than a fourth click-to-target mode. Re-anchoring drops the point where
## he stands, so the dead hold that ground instead of walking with him.
func _toggle_escort() -> void:
	if undead_command == null or villain == null:
		return
	if undead_command.is_active() and undead_command.rally_point.is_escorting():
		undead_command.anchor_to_ground(villain.position)
		_log("[color=#9fb6c8]The point settles into the ground. The dead hold it.[/color]",
			"characters events")
	else:
		var bound: int = undead_command.cast_escort(villain)
		_log("[color=#8fd8b0]The dead fall in behind him — %d of them.[/color]" % bound,
			"characters events")
	inspector.refresh()

func _job_place(job: String) -> String:
	match job:
		"woodcutter": return "woodmill"
		"farmer": return "farm"
		"guard": return "watch"
		_: return "village"

## **Flee the region** (ROGUELITE_REWORK section 1, 17.7): only from the lair;
## the player picks up to 3 things he found this run to carry out.
## A button on the guild's board. The guild decides; this only reports.
func _guild_action(g, action: String, id: int) -> void:
	var b: Dictionary = g.bounty(id)
	if b.is_empty():
		return
	var ok: bool = false
	match action:
		"take":
			ok = g.take(villain, id)
			if ok:
				_log("[color=#e0c890]He takes the job: %s.[/color]" % String(b["title"]), "events")
		"deliver":
			ok = g.deliver(villain, id)
		"collect":
			ok = g.turn_in(villain, id)
	if not ok and action != "take" and String(b.get("state", "")) == "done" and int(b.get("owed", 0)) > 0:
		_log("[color=orange]His party's hands are full. The clerk will hold the %d gold until he comes back with room.[/color]"
			% int(b["owed"]), "events")
	elif not ok:
		_log("[color=orange]The clerk shakes his head.[/color]", "events")
	inspector.refresh()

## The Items window, with the ground of whatever site he is standing at.
func _open_items() -> void:
	if items_dialog == null or villain == null or (run_lifecycle and run_lifecycle.ended):
		return
	var here: WorldSite = world_sites.lootable_in_reach(villain) if world_sites else null
	items_dialog.open(here if here != null and not here.relic_remainder.is_empty() else null)

func _request_flee() -> void:
	if run_lifecycle == null or not run_lifecycle.can_flee():
		_log("[color=orange]He can only flee the region from the lair. Get him home first.[/color]", "events")
		return
	_close_inspector()
	keep_dialog.open(run_lifecycle.run_items(), run_lifecycle._carried_ids())

func _open_lair() -> void:
	if lair_screen and run_lifecycle:
		lair_screen.show_lair(run_lifecycle.profile, villain.class_id if villain else "necromancer")

func _toggle_stance() -> void:
	if villain == null or not villain.is_alive():
		return
	villain.toggle_stance()
	if inspector.is_open():
		inspector.refresh()

func _set_escort_stance(stance: int) -> void:
	if undead_command == null:
		return
	undead_command.set_stance(stance)
	inspector.refresh()

## Puts part of the haul down. Where it lands is `SortieSystem`'s to decide --
## the site he is standing at, or a cache on the ground.
func _drop_load(kind: String, amount: int) -> void:
	if sortie_system == null:
		return
	var site: WorldSite = sortie_system.drop(kind, amount)
	if site:
		inspector.refresh()

func _drop_relic(relic_id: String) -> void:
	if sortie_system == null:
		return
	if sortie_system.drop_relic(relic_id):
		inspector.refresh()

## **F3 — the dev site overlay.** A playtesting aid and not a game feature: it
## labels every active site through the fog so a tester can reach the dens and
## the Band-4 sites without wandering.
##
## It changes nothing. No reveal, no fog write, no discovery flag — looking at a
## marker must never count as having found a site, because the Raven's pings
## (`RAVEN_SPEC.md`) and any later discovery gating would read exactly that.
## The overlay is read-only over `WorldSites` and the harness asserts the fog is
## byte-identical across a toggle.
##
## The log line is deliberately prefixed DEBUG so a bug report screenshot shows
## the tester had it on.
func _toggle_site_overlay() -> void:
	if debug_site_overlay == null:
		return
	var on: bool = debug_site_overlay.toggle()
	if minimap:
		minimap.queue_redraw()
	_log("[color=#e8e040]DEBUG: site overlay %s[/color]" % ("on" if on else "off"), "events")

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

## **Raise Dead, paid in bones** (ruling C, 2026-09-26): a skeleton climbs out
## of the ground at his feet, wherever he stands. The free version is the grave
## sheet's "Raise the corpse". The historical name stays so every button that
## already emits `recruit_worker_pressed` casts the spell.
func _recruit_worker() -> void:
	if villain == null or not villain.is_alive():
		return
	var at: Vector2 = villain.position + Vector2(18.0, 10.0)
	if world_map:
		at = world_map.nearest_walkable(at)
	var w := worker_system.raise_skeleton_at(at, worker_system.next_skeleton_name(),
		WorkerSystem.RECRUIT_COST)
	if w == null:
		_log("[color=orange]Raise Dead needs %d Bones in the stockpile. Graves give the dead for free.[/color]"
			% int(WorkerSystem.RECRUIT_COST.get("bones", 0)), "alerts")
		_alert("Not enough Bones to Raise Dead.", "warn")
		return
	EventBus.skeleton_raised.emit(villain, w, "bones")
	_log("[color=lightgreen]He speaks, and the ground gives up %s.[/color]" % w.worker_name, "characters")
	if inspector.is_open():
		inspector.refresh()
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
	# Gear is a physical thing, so it moves a physical attribute. Real equipment
	# slots that set the attack profile are COMBAT_SPEC section 9 and unbuilt;
	# until then this stays the flat +1 it always was, just to a stat that still
	# exists.
	var stats := ["strength", "dexterity", "endurance"]
	var stat: String = stats[randi() % stats.size()]
	f.apply_attributes({stat: mini(10, f.attribute(stat) + 1)})
	_log("[color=lightgreen]The Blacksmith forges gear for %s (+1 %s).[/color]" % [
		f.follower_name, stat.capitalize()], "characters")

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
		f.apply_attributes({"strength": mini(10, f.strength + 1)})
	_log("[color=lightgreen]The Barracks trains %d idle follower(s) (+1 Strength each).[/color]" % idle.size(), "characters")

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
	inspector_actions.site_action_requested.connect(_begin_site_action)
	inspector_actions.site_sheet_requested.connect(_open_site_sheet)
	inspector_actions.drop_requested.connect(_drop_load)
	inspector_actions.drop_relic_requested.connect(_drop_relic)
	inspector_actions.escort_toggle_requested.connect(_toggle_escort)
	inspector_actions.escort_stance_requested.connect(_set_escort_stance)
	inspector_actions.villain_stance_toggle_requested.connect(_toggle_stance)
	inspector_actions.guild_action_requested.connect(_guild_action)
	inspector_actions.ghoul_unlocked = func():
		return run_lifecycle != null and run_lifecycle.profile.level(villain.class_id) >= 2
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
		# Heal-at-dawn is a banked-relic effect (LOOT_SITES_SPEC section 7). The
		# hook lives here because the rest of the dawn work already does, and
		# because a relic that healed him while it was still in his hands would
		# undo section 7's whole point.
		var mended: int = villain.heal(villain.dawn_heal()) if villain else 0
		if mended > 0:
			_log("[color=#9fd8b0]The censer smokes at dawn. He mends %d.[/color]" % mended, "characters")
		hud_top_bar.refresh_stats()  # the top bar carries the Day/Night readout
	)

	# ---- Lootable sites (LOOT_SITES_SPEC section 9) ----
	EventBus.site_looted.connect(func(v, site, loot: Dictionary):
		if loot.is_empty():
			_log("[color=#9fb6c8]%s gives up nothing he can carry.[/color]" % site.display_name, "events")
		else:
			_log("[color=#d8c78a]%s: %s.[/color]" % [site.display_name, LootCatalog.describe(loot)], "events")
		if site.has_remainder():
			_log("[color=#c8a45a]He leaves %s behind. It stays there.[/color]" % site._remainder_label(), "events")
		hud_top_bar.refresh_stats()
	)
	EventBus.relic_found.connect(func(v, relic_id: String):
		if v != villain:
			return
		var r: Dictionary = LootCatalog.relic(relic_id)
		_log("[color=#e0c060]%s — %s %s[/color]"
			% [r.get("name", relic_id), r.get("description", ""), ItemsDialog.effect_text(relic_id)], "events alerts")
		_alert("Picked up: %s" % r.get("name", relic_id), "info")
	)
	# Items at his feet: the pick-up window (2026-09-26).
	EventBus.items_on_ground.connect(func(v, site, ids: Array):
		if v != villain:
			return
		_log("[color=#e0c060]On the ground at %s: %s.[/color]" % [site.display_name, LootCatalog.describe_relics(ids)], "events")
		if auto_open_items and not (run_lifecycle and run_lifecycle.ended):
			items_dialog.open(site)
	)
	EventBus.gear_changed.connect(func(v):
		if v == villain and hud_top_bar:
			hud_top_bar.refresh_stats()
	)
	# **The ledger R3 will read.** R2 consumes none of it beyond this line --
	# which is the point: the array is being written now so R3 has a history
	# rather than an archaeology problem.
	EventBus.deed_committed.connect(func(v, deed_id: String, axes: Dictionary):
		var words: Array = []
		for axis in axes.keys():
			words.append(String(axis).capitalize().replace("_", " "))
		_log("[color=#a898c8]Deed: %s%s[/color]" % [deed_id.replace("_", " "),
			"" if words.is_empty() else "  (%s)" % ", ".join(words)], "characters")
	)
	EventBus.site_guardian_engaged.connect(func(v, site):
		_alert("Something at %s has taken exception." % site.display_name, "warn")
	)

	# ---- The escort (ESCORT_SPEC §9) ----
	# **Cover state is announced, not silent** (§7): it is the one thing the dead
	# do that the player did not ask for, so it gets a line both ways.
	EventBus.escort_covering.connect(func(v, covering: bool):
		if covering:
			_log("[color=#8fd8b0][b]The dead close ranks.[/b][/color]", "characters alerts events")
			_alert("The dead close ranks around him.", "warn")
		else:
			_log("[color=#9fb6c8]They stand down.[/color]", "characters events")
	)
	EventBus.escort_stance_changed.connect(func(v, stance_name: String):
		_log("[color=#a898c8]The escort goes %s.[/color]" % stance_name.to_lower(),
			"characters events")
	)
	EventBus.escort_member_lost.connect(func(v, unit, cause: String):
		_log("[color=orange]One of the escort is down to %s — and whatever it was carrying with it.[/color]"
			% _a_name(cause), "characters alerts events")
	)

	# ---- The return leg (SORTIE_SPEC §9) ----
	# **The moment the haul becomes real.** Loud, because four minutes of walking
	# just paid out and the deposit is automatic -- there is no button press to
	# confirm it happened.
	EventBus.sortie_deposited.connect(func(v, load: Dictionary, relics: Array):
		if not load.is_empty():
			_log("[color=#8fd8a0]Banked at the Throne: %s.[/color]" % LootCatalog.describe(load),
				"events alerts")
			_alert("Banked: %s" % LootCatalog.describe(load), "good")
		hud_top_bar.refresh_stats()
	)
	EventBus.relic_banked.connect(func(v, relic_id: String):
		var r: Dictionary = LootCatalog.relic(relic_id)
		_log("[color=#e0c060]%s is yours, and awake.[/color]" % r.get("name", relic_id),
			"events alerts characters")
		_alert("%s — its effect is live." % r.get("name", relic_id), "good")
	)
	EventBus.sortie_load_dropped.connect(func(v, kind: String, amount: int, to_site):
		_log("[color=#c8a45a]Left %s at %s.[/color]"
			% [LootCatalog.describe({kind: amount}) if LootCatalog.LOOT_KINDS.has(kind)
				else String(LootCatalog.relic(kind).get("name", kind)), to_site.display_name],
			"events")
	)
	EventBus.sortie_cache_created.connect(func(v, cache):
		_log("[color=#c8a45a]You set it down in open country. It will be there when you come back.[/color]",
			"events")
		_alert("A cache left on the ground.", "info")
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
	# The villain going down. **Owner-checked**: `villain_died` fires for every
	# villain, and the combat harness kills a thousand throwaway ones (CLAUDE.md's
	# gotcha; this handler was the one that forgot, review 2026-09-26). What
	# happens next is RunLifecycle's -- this only says it out loud.
	EventBus.villain_died.connect(func(v, cause: String):
		if v != villain:
			return
		_log("[color=red][b]THE NECROMANCER HAS FALLEN.[/b][/color] (%s)" % cause,
			"events alerts characters")
		_alert("THE NECROMANCER HAS FALLEN.", "bad")
		_log("[color=#c8a45a]Everything he was carrying is lost where he fell.[/color]",
			"events characters")
		hud_top_bar.refresh_villain_hp()
	)
	# ---- The living village and the stance (LIVING_WORLD L1, ruling 15) ----
	EventBus.villain_stance_changed.connect(func(v, stance_name: String):
		if v != villain:
			return
		if villain.is_hunting():
			_log("[color=#ff9a80]He is Hunting. Anything living he walks up to is fair game — and anyone who sees it will remember.[/color]", "characters events")
		else:
			_log("[color=#b8a0e0]He is Hidden again. He will not start a fight with the living.[/color]", "characters events")
		hud_top_bar.set_stance(stance_name)
	)
	EventBus.villager_killed.connect(func(_vil, who, _killer):
		_log("[color=#e08080]%s is dead. His body lies where he fell.[/color]" % who.label(), "events characters")
		if inspector.is_open() and inspector.current_source() == who:
			_close_inspector()
	)
	EventBus.village_restaffed.connect(func(vil, who, from_job: String, to_job: String):
		if to_job == "guard" and from_job != "":
			_log("[color=#e0c080]%s: %s takes up a spear. The %s is a hand short.[/color]"
				% [vil.display_name, who.villager_name, _job_place(from_job)], "events")
		elif to_job != "":
			_log("[color=#c0b090]%s: %s is a %s now.[/color]" % [vil.display_name, who.villager_name, who.job_title().to_lower()], "events")
		else:
			_log("[color=#a09080]%s: %s has no work now.[/color]" % [vil.display_name, who.villager_name], "events")
	)
	EventBus.village_guard_trained.connect(func(vil, who):
		_log("[color=#e0c080]%s: %s has finished his training. The village has a real guard again.[/color]"
			% [vil.display_name, who.villager_name], "events")
	)
	EventBus.village_alarm.connect(func(vil, _at: Vector2):
		_log("[color=#ff8060]%s raises the alarm. The guards are coming.[/color]" % vil.display_name, "events alerts")
		_alert("%s raises the alarm." % vil.display_name, "warn")
	)
	# ---- The guild, the witnesses, standing (LIVING_WORLD L2) ----
	EventBus.witnessed.connect(func(v, who, act: String):
		if v != villain:
			return
		if who is Villager:
			_log("[color=#ffb070]%s saw him %s — and is running to tell.[/color]" % [who.villager_name, act], "events characters")
			_alert("Seen: %s is running to tell." % who.villager_name, "warn")
		else:
			_log("[color=#ffb070]The keeper in the guild's doorway saw him %s.[/color]" % act, "events")
	)
	EventBus.report_arrived.connect(func(v, who, _act: String, where: String):
		if v != villain or who == null:
			return
		_log("[color=#ff9070]%s reached %s with the news.[/color]" % [who.villager_name, where], "events")
	)
	EventBus.standing_changed.connect(func(v, faction: String, tier: int, why: String):
		if v != villain or faction != Guild.FACTION:
			return
		_log("[color=#ff9070]%s. The guild's standing: %s.[/color]" % [why, Necromancer.standing_name(tier)], "events")
		hud_top_bar.set_guild_standing(Necromancer.standing_name(tier))
		if tier == Necromancer.Standing.KNOWN:
			_alert("The guild knows what he is. Its doors are shut.", "bad")
		else:
			_alert("The guild has heard something.", "warn")
	)
	EventBus.guild_bounty_paid.connect(func(v, b: Dictionary, gold: int):
		if v != villain:
			return
		var still: String = "" if int(b.get("owed", 0)) <= 0 else " (%d still owed — his hands are full)" % int(b["owed"])
		_log("[color=#e8d070]The clerk counts out %d gold for \"%s\"%s. It is his when he banks it at the Throne.[/color]"
			% [gold, String(b["title"]), still], "events")
	)
	EventBus.blueprint_learned.connect(func(id: String, source: String):
		var name_: String = String(BuildingCatalog.get_building(id).get("display_name", id))
		_log("[color=#c8a8ff]Blueprint learned by %s: %s. It can be built from now on — this run and every run after.[/color]"
			% [source, name_], "events")
		_alert("Blueprint learned: %s" % name_, "good")
		_show_unlock_banner(name_, source)
		build_menu.populate()
	)
	# ---- The Raven (RAVEN_SPEC section 5) ----
	hud_top_bar.raven_chip_pressed.connect(_on_raven_chip)
	EventBus.raven_pinged.connect(func(v, site):
		if v != villain:
			return
		_log("[color=#c8a8ff]The Raven comes back at dawn: she has been to %s (Band %d). Honest, as ever — the road is yours.[/color]"
			% [site.display_name, site.band], "events")
		_alert("The Raven has found something.", "info")
		_refresh_raven_views()
	)
	EventBus.raven_silent.connect(func(v, _day: int):
		if v != villain:
			return
		_log("[color=#9a8ab8]The bird found nothing. The near country is picked clean.[/color]", "events")
		hud_top_bar.flicker_raven_silent(raven.outstanding())
	)
	EventBus.raven_ping_claimed.connect(func(v, _site):
		if v == villain:
			_refresh_raven_views()
	)
	EventBus.villain_woke.connect(func(v, left: int):
		if v != villain:
			return
		_log("[color=#b8a0e0]...and the Second Wake drags him back to the Throne. (%s)[/color]"
			% ("no more this run" if left <= 0 else "%d left" % left), "events characters")
		hud_top_bar.refresh_villain_hp()
	)
	EventBus.villain_levelled.connect(func(v, lvl: int, unlocks: Array):
		if v != villain:
			return
		_log("[color=gold]He grows in power — level %d.[/color]" % lvl, "events characters")
		_alert("Level %d." % lvl, "good")
		for u in unlocks:
			_log("[color=gold]Unlocked: %s — %s[/color]" % [String(u.get("name", "")),
				String(u.get("description", ""))], "events characters")
	)
	EventBus.run_ended.connect(func(v, summary: Dictionary):
		if v != villain:
			return
		_close_inspector()
		_log("[color=#c8a45a]%s[/color]" % String(summary.get("epitaph", "")), "events alerts")
		run_summary.show_summary(summary)
	)
	# Journey milestones. Logged rather than alerted: pacing information is
	# something you read afterwards, not something that should interrupt a walk.
	EventBus.travel_noted.connect(func(text: String, seconds: float):
		var stamp: String = "" if seconds <= 0.0 else " [%s]" % TravelLog._fmt(seconds)
		_log("[color=#9fb6c8]%s%s[/color]" % [text, stamp], "events")
	)
	# ---- The villain's own fight (NECROMANCER_SPEC §3/§9) ----
	# Loud, because walking into engage range is a decision and the player must
	# be certain it registered -- there is no attack button to confirm it.
	EventBus.villain_engaged.connect(func(v, foe_name: String):
		_log("[color=#c9a0ff]He raises a hand, and the air goes cold. — %s[/color]" % foe_name,
			"characters alerts events")
		_alert("The Necromancer is fighting a %s." % foe_name, "warn")
		hud_top_bar.refresh_villain_hp()
	)
	EventBus.villain_disengaged.connect(func(v, foe_name: String, reason: String):
		_log("[color=#9fb6c8]He breaks off from the %s — %s.[/color]" % [foe_name, reason],
			"characters events")
		hud_top_bar.refresh_villain_hp()
	)
	EventBus.combat_started.connect(func(attacker: String, defender: String):
		_log("[color=orange]%s sets on %s![/color]" % [_a_name(attacker, true), defender], "events alerts characters")
		_alert("%s is attacking %s." % [_a_name(attacker, true), defender], "warn")
	)
	EventBus.combat_joined.connect(func(f, attacker: String):
		_log("[color=lightgreen]%s wades in against the %s.[/color]" % [f.follower_name, attacker],
			"characters events")
		_alert("%s joins the fight." % f.follower_name, "good")
	)
	EventBus.worker_destroyed.connect(func(w, cause: String):
		_log("[color=red]%s tore apart %s.[/color]" % [_a_name(cause, true), w.worker_name], "events alerts characters")
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
		_log("[color=orange]%s brought down one of the deer. That food is gone.[/color]" % _a_name(predator, true),
			"events alerts")
		_alert("%s took a deer." % _a_name(predator, true), "warn")
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
## The Raven's chip: centre on the newest unseen mark (then cycle), drop
## villain-follow the way any manual pan does, and open the mark's panel.
func _on_raven_chip() -> void:
	if raven == null:
		return
	var site = raven.next_for_chip()
	if site == null:
		return
	camera.center_on_manual(site.position)
	var mark: Node2D = raven.marker_for(site)
	if mark:
		_inspect(mark)
	_refresh_raven_views()

func _refresh_raven_views() -> void:
	if raven:
		hud_top_bar.set_raven_count(raven.outstanding(), raven.unseen())
	if minimap:
		minimap.queue_redraw()

## "Level 3 — 120 / 200 XP · next: Second Wake at level 5", for his panel.
func _progress_line() -> String:
	if run_lifecycle == null or villain == null:
		return ""
	var p: MetaProfile = run_lifecycle.profile
	var total: int = p.xp(villain.class_id)
	var prog: Array = MetaProfile.level_progress(total)
	var text: String = "Level %d — %s" % [p.level(villain.class_id),
		("%d / %d XP" % [prog[0], prog[1]]) if int(prog[1]) > 0 else "max level"]
	var next: Dictionary = p.next_unlock(villain.class_id)
	if not next.is_empty():
		text += "  ·  next: %s at level %d" % [String(next.get("name", "")), int(next.get("level", 0))]
	if run_lifecycle.wakes_left > 0:
		text += "  ·  Second Wake ready"
	return text

## "a wolf" / "An outlaw": names that already carry their article ("An
## outlaw", "The Sexton") keep it; bare ones ("wolf") get one.
func _a_name(n, capital: bool = false) -> String:
	var s: String = String(n)
	var low: String = s.to_lower()
	if low.begins_with("a ") or low.begins_with("an ") or low.begins_with("the "):
		return (s.substr(0, 1).to_upper() + s.substr(1)) if capital else (s.substr(0, 1).to_lower() + s.substr(1))
	var art: String = "an" if "aeiou".contains(low.substr(0, 1)) else "a"
	return ("%s %s" % [art.capitalize(), s]) if capital else ("%s %s" % [art, s])

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
	if log_ticker:
		log_ticker.push(msg)
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
