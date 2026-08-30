extends Node2D
class_name DebugSiteOverlay

## **A development aid, not a game feature.** F3 draws a flat yellow label over
## every active lootable site so a playtester can find the dens and the Band-4
## sites without wandering. Default off, and gated on `OS.is_debug_build()` at
## the input site so it can never be reached in an exported build.
##
## ## What it must never do, and why the list is this specific
##
## **It is read-only over `WorldSites`.** It draws nothing that changes
## anything: no reveal, no fog write, no discovery flag, no `pick_at`, no
## mutation of any site. Looking at a marker must not count as having found the
## site — because `RAVEN_SPEC.md`'s pings and any later discovery gating would
## read exactly that kind of state, and a debug aid that quietly marked
## everything discovered would perjure the bird for the rest of the run.
##
## As of R2b **no such flag exists** — sites carry loot state and nothing about
## being known — so today this rule costs nothing. It is written down because
## the moment somebody adds `discovered`, this file is the first place that
## would silently start setting it.
##
## ## Deliberately ugly
##
## Flat yellow text, a hollow ring, no site art, no panel chrome. It has to be
## impossible to mistake for the game at a glance in a screenshot, and it has to
## be obvious in a bug report that the tester had it on.
##
## ## Not in the HUD
##
## A `Node2D` in world space rather than a `Control` in `hud_root`: it follows
## the sites, not the screen, and it stays out of the HUD's sibling ordering
## (which is z-order *and* input order, and has eaten clicks twice). It draws
## above the fog by z-index and takes no input at all.

## Above `FogOfWar`'s 100 — the whole point is to see sites through unexplored
## ground. Nothing else in the project draws this high.
const Z_ABOVE_FOG: int = 200

const LABEL_COLOR := Color(1.0, 0.95, 0.25)
const RING_COLOR := Color(1.0, 0.95, 0.25, 0.75)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.85)
const SPENT_COLOR := Color(0.75, 0.72, 0.45, 0.7)
const UNREACHABLE_COLOR := Color(1.0, 0.3, 0.3)
const RING_RADIUS: float = 14.0
const FONT_SIZE: int = 13

## Read-only. Handed in by Main, never looked up.
var world_sites: WorldSites = null
var world: WorldMap = null

var _font: Font = ThemeDB.fallback_font
## site_id -> true for sites the villain cannot get to. Recomputed on each
## switch-on rather than per frame -- it is a flood fill over 20,736 cells, and
## the map does not move while the overlay is up.
var _unreachable: Dictionary = {}

func setup(p_world_sites: WorldSites, p_world: WorldMap) -> void:
	world_sites = p_world_sites
	world = p_world
	z_index = Z_ABOVE_FOG
	# Off until asked for, and costing nothing while off: an invisible CanvasItem
	# is not drawn, and `_draw` is the only thing this class does.
	visible = false

func is_on() -> bool:
	return visible

## Returns the new state, so the caller can log it without asking again.
func toggle() -> bool:
	visible = not visible
	if visible:
		_recompute_reachability()
		queue_redraw()
	return visible

# ---------------- Reachability ------------------------------------------------

## The same question `verify_terrain` asks at bake time, asked again live: does
## this site have a walkable cell **within its interaction reach** that connects
## to the lair?
##
## Duplicated on purpose rather than shared. The harness reads
## `data/world_map.json` before the game runs and would not notice a site moved
## at runtime; this reads the live `WorldMap`. The two agreeing is the point —
## and a playtester seeing red on a site the harness passed is a finding worth
## having immediately, which is exactly how the valley den should have been
## caught (it was reachable, so this would have stayed silent; the mouth width
## assertion is the one that catches that class).
func _recompute_reachability() -> void:
	_unreachable.clear()
	if world == null or world_sites == null:
		return
	var lair: Vector2i = world.lair_origin + Vector2i(
		SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2)
	var reached: Dictionary = _flood_from(lair)
	for site in _sites():
		if not _connects(site, reached):
			_unreachable[site.site_id] = true

func _flood_from(from: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	# The lair band is guaranteed walkable, but snap anyway rather than assume:
	# a flood fill that starts on rock silently reports the whole map sealed.
	var start: Vector2i = world.cell_at(world.nearest_walkable(world.cell_centre_px(from)))
	if not world.is_walkable_cell(start):
		return seen
	var queue: Array = [start]
	seen[start.y * world.width + start.x] = true
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = here + d
			if n.x < 0 or n.y < 0 or n.x >= world.width or n.y >= world.height:
				continue
			var key: int = n.y * world.width + n.x
			if seen.has(key) or not world.is_walkable_cell(n):
				continue
			seen[key] = true
			queue.append(n)
	return seen

func _connects(site: WorldSite, reached: Dictionary) -> bool:
	var cell: Vector2i = world.cell_at(site.position)
	var reach: float = site.interact_radius()
	var span: int = int(ceil(reach / float(WorldMap.CELL_SIZE))) + 1
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
				continue
			if site.position.distance_to(world.cell_centre_px(c)) > reach:
				continue
			if world.is_walkable_cell(c) and reached.has(c.y * world.width + c.x):
				return true
	return false

## Every site with a `lootable` block — the fifteen the density budget calls
## *active* (`LOOT_SITES_SPEC.md` §2). The manor, church, houses and watchtower
## are inert scenery and are deliberately not labelled: this exists to find the
## things worth walking to.
##
## Asked of `WorldSites` through its own public query rather than by reaching
## into `sites`, which is that container's standing rule.
func _sites() -> Array:
	return world_sites.lootable_sites() if world_sites else []

func _draw() -> void:
	for site in _sites():
		var at: Vector2 = to_local(site.global_position)
		var spent: bool = site.is_spent()
		var tint: Color = SPENT_COLOR if spent else LABEL_COLOR
		draw_arc(at, RING_RADIUS, 0.0, TAU, 20, RING_COLOR if not spent else SPENT_COLOR, 1.5)
		# Band and guard state are the two things that decide whether it is worth
		# walking to, so they go in the label rather than needing a click.
		var line: String = "%s  ·  B%d" % [site.display_name, site.band]
		if site.is_guarded():
			line += "  ·  guarded"
		if spent:
			line += "  ·  spent"
		# **The whole reason this got written** (2026-08-30): a den the player
		# could not get into shipped, because nothing checked. Red, loud, and
		# on screen the instant a tester turns the overlay on.
		if _unreachable.has(site.site_id):
			_text(at + Vector2(0.0, -RING_RADIUS - 6.0), line, tint)
			_text(at + Vector2(0.0, -RING_RADIUS - 20.0), "UNREACHABLE", UNREACHABLE_COLOR)
			draw_arc(at, RING_RADIUS + 4.0, 0.0, TAU, 20, UNREACHABLE_COLOR, 2.0)
			continue
		_text(at + Vector2(0.0, -RING_RADIUS - 6.0), line, tint)

## One-pixel drop shadow, because flat yellow on snow is unreadable and a debug
## aid nobody can read is worse than none.
func _text(at: Vector2, line: String, tint: Color) -> void:
	var width: float = _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var origin: Vector2 = at - Vector2(width * 0.5, 0.0)
	draw_string(_font, origin + Vector2(1, 1), line, HORIZONTAL_ALIGNMENT_LEFT, -1,
		FONT_SIZE, SHADOW_COLOR)
	draw_string(_font, origin, line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, tint)

## Positions for the minimap's debug dots, in engine space.
##
## Handed to `Minimap` as a Callable so the minimap keeps knowing nothing about
## sites: it draws points, and only while this overlay is on. Its header's rule
## about live contents is deliberately suspended here and nowhere else — this is
## a debug build, with the overlay explicitly switched on by a keypress.
func minimap_points() -> Array:
	if not visible:
		return []
	var out: Array = []
	for site in _sites():
		out.append(site.global_position)
	return out
