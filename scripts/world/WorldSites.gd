extends Node2D
class_name WorldSites
## Owns every fixed site, patrol and site guardian on the world map, and answers
## "what did the player just click".
##
## Same shape as `ResourceField`: one container that loads its content from
## data, holds the nodes, and exposes queries -- **nothing reaches into `sites`,
## `patrols` or `guardians` directly**, so the pick rules and the guardian
## lifecycle stay in one place.
##
## Content lives in `data/world_sites.json`, positioned in **world cells**
## (converted here through `WorldMap`), because that is how the layout is
## reasoned about; the settlement's own buildings stay in settlement cells and
## are none of this file's business.
##
## ## What R2a added
##
## The optional `lootable` block per site (`LOOT_SITES_SPEC.md` section 8), the
## top-level `guardians` statline table, `lootable_in_reach()`, and the spawn /
## despawn of `SiteGuardian`s. Inert sites are untouched and the loader's
## behaviour for them is unchanged -- the manor, the church, the houses and the
## watchtower stay scenery, because they are Era-III business.

const DATA_PATH := "res://data/world_sites.json"

var world: WorldMap = null
var sites: Array = []      # Array[WorldSite]
var patrols: Array = []    # Array[Patrol]
var guardians: Array = []  # Array[SiteGuardian]

## The `kind -> statline` table `guardian.kind` selects from (section 8).
var guardian_kinds: Dictionary = {}

## Named landmarks the travel instrumentation measures to, `name -> position`.
## Built from the same entries, so a site added to the JSON is automatically
## something travel times get reported for.
var landmarks: Dictionary = {}

## Handed in by Main so a deed can be stamped with the game day. A Callable
## rather than a `DayNightCycle` reference for the same reason `Minimap` takes
## one: this stays a container with no idea what a clock is.
var day_provider: Callable = Callable()

func build(p_world: WorldMap) -> bool:
	world = p_world
	if not FileAccess.file_exists(DATA_PATH):
		push_error("WorldSites: %s missing." % DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldSites: %s is not a JSON object." % DATA_PATH)
		return false
	var data: Dictionary = parsed
	guardian_kinds = data.get("guardians", {})
	for entry in data.get("sites", []):
		_add_site(entry)
	for entry in data.get("patrols", []):
		_add_patrol(entry)
	_spawn_guardians()
	return true

func _add_site(entry: Dictionary) -> void:
	var cell: Array = entry.get("cell", [0, 0])
	var at: Vector2 = world.cell_centre_px(Vector2i(int(cell[0]), int(cell[1])))
	var site := WorldSite.new()
	site.name = "Site_%s" % String(entry.get("id", "x"))
	add_child(site)
	site.day_provider = func(): return int(day_provider.call()) if day_provider.is_valid() else 1
	site.guardian_spawner = _post_guardians
	site.setup(entry, at, float(entry.get("size", 56.0)))
	sites.append(site)
	if bool(entry.get("landmark", false)):
		landmarks[site.display_name] = at

func _add_patrol(entry: Dictionary) -> void:
	var points := PackedVector2Array()
	for wp in entry.get("waypoints", []):
		points.append(world.cell_centre_px(Vector2i(int(wp[0]), int(wp[1]))))
	if points.size() < 2:
		push_warning("WorldSites: patrol '%s' needs at least 2 waypoints." % entry.get("name", "?"))
		return
	var patrol := Patrol.new()
	patrol.name = "Patrol_%s" % String(entry.get("name", "x")).replace(" ", "_")
	add_child(patrol)
	patrol.setup(entry, points, world)
	patrols.append(patrol)

# ---------------- Guardians ---------------------------------------------------

## One `SiteGuardian` per `count`, posted in a small ring around the site so a
## pack reads as a pack rather than as one sprite drawn three times. Spawned at
## build rather than on approach: `abandoned_camp` rolls occupancy at
## *activation* (section 3), and a guardian that appeared when the player got
## close would be the surprise section 1.3 forbids.
func _spawn_guardians() -> void:
	for site in sites:
		if site.guardian_spec.is_empty():
			continue
		var kind: String = String(site.guardian_spec.get("kind", ""))
		var spec: Dictionary = guardian_kinds.get(kind, {})
		if spec.is_empty():
			push_warning("WorldSites: site '%s' wants guardian kind '%s', which is not in the guardians table."
				% [site.site_id, kind])
			site.cleared = true
			continue
		_post_guardians(site, kind, int(site.guardian_spec.get("count", 1)))

## Posts `count` guardians of `kind` around `site` and marks it guarded. Used
## both at build and by the multi-charge sites' per-pull roll -- one spawn path,
## so a sentinel that climbs out of a battlefield is the same object as one that
## was always in the crypt.
func _post_guardians(site: WorldSite, kind: String, count: int) -> void:
	var spec: Dictionary = guardian_kinds.get(kind, {})
	if spec.is_empty():
		push_warning("WorldSites: no guardian kind '%s' for site '%s'." % [kind, site.site_id])
		return
	for i in range(maxi(1, count)):
		var angle: float = TAU * float(site.guardians.size()) / float(maxi(2, count + 1))
		var offset := Vector2(cos(angle), sin(angle)) * float(SettlementGrid.CELL_SIZE)
		var at: Vector2 = site.position + offset
		if world:
			at = world.nearest_walkable(at)
		var g := SiteGuardian.new()
		g.name = "Guardian_%s_%d" % [site.site_id, site.guardians.size()]
		# **setup() before add_child()**, and it matters: `SiteGuardian._ready()`
		# builds the sprite from the fields setup writes, and adding it to the
		# tree first runs _ready with none of them set. That is the bug that
		# produced three wolves with no sprite the first time this ran.
		g.setup(kind, spec, site, at, world)
		add_child(g)
		guardians.append(g)
		site.guardians.append(g)
	site.cleared = false

## Removes a guardian that died or left, and clears its site when it was the
## last one standing. `villain` is the one who did it -- passed in, never looked
## up, so the Power deed lands on the right ledger (ROGUELITE_REWORK section 11).
func remove_guardian(guardian: SiteGuardian, villain) -> void:
	if guardian == null:
		return
	var site: WorldSite = guardian.site
	guardians.erase(guardian)
	if site:
		site.guardians.erase(guardian)
		if site.guardians.is_empty():
			site.cancel_channel("the fight is over")
			site.mark_cleared(villain)
	guardian.queue_free()

## Every guardian still able to object. The policy layer iterates this rather
## than reaching into `guardians`.
func live_guardians() -> Array:
	var out: Array = []
	for g in guardians:
		if is_instance_valid(g) and g.is_alive() and not g.has_left():
			out.append(g)
	return out

## **The dusk gate** (section 3b). While at least one den stands, the settlement
## keeps getting wolves at dusk; when the last one is cleared, the raids stop
## for the run. The fiction and the mechanics finally agree about where wolves
## live.
func any_den_uncleared() -> bool:
	for site in sites:
		if site.is_den() and site.is_guarded():
			return true
	return false

func dens() -> Array:
	return sites.filter(func(s: WorldSite): return s.is_den())

# ---------------- Queries -----------------------------------------------------

## The lootable site he is standing on, or null. **Takes the villain**, never
## looks one up: sites answer to whoever walked up (section 3), and a second
## villain on the same map would ask the same question about himself.
func lootable_in_reach(villain) -> WorldSite:
	if villain == null:
		return null
	var best: WorldSite = null
	var best_dist: float = INF
	for s in sites:
		if not s.lootable:
			continue
		var d: float = villain.position.distance_to(s.position)
		if d <= s.interact_radius() and d < best_dist:
			best_dist = d
			best = s
	return best

func lootable_sites() -> Array:
	return sites.filter(func(s: WorldSite): return s.lootable)

## Every site that is still worth walking to. Read by the log and by anything
## that wants to know whether the world still has anything in it.
func unspent_lootable_count() -> int:
	var n: int = 0
	for s in lootable_sites():
		if not s.is_spent():
			n += 1
	return n

## Closest patrol, then guardian, then site within its own pick radius, or null.
## Characters first for the same reason everywhere else: a man standing in front
## of a house is the thing you meant to click, and a wolf standing over a den is
## very much the thing you meant to click.
func pick_at(world_pos: Vector2) -> Node2D:
	for p in patrols:
		if world_pos.distance_to(p.position) <= p.hit_radius():
			return p
	for g in guardians:
		if is_instance_valid(g) and world_pos.distance_to(g.position) <= g.hit_radius():
			return g
	var best: WorldSite = null
	var best_dist: float = INF
	for s in sites:
		var d: float = world_pos.distance_to(s.position)
		if d <= s.hit_radius() and d < best_dist:
			best_dist = d
			best = s
	return best
