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
const RING_RADIUS: float = 14.0
const FONT_SIZE: int = 13

## Read-only. Handed in by Main, never looked up.
var world_sites: WorldSites = null

var _font: Font = ThemeDB.fallback_font

func setup(p_world_sites: WorldSites) -> void:
	world_sites = p_world_sites
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
		queue_redraw()
	return visible

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
