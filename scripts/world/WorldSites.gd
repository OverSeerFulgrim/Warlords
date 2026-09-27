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
## Skeletons pulled out of graves, as the Workers they became. The ledger entry
## on the villain is still the record; this is the roster side, kept so a
## harness (and anything later) can ask "what came out of the ground here".
var raised: Array = []     # Array[Laborer]

## Turns a raised corpse into a unit: `func(at: Vector2, villain, site) ->
## Laborer`. Main hands in `WorkerSystem.raise_skeleton_at` with no cost. Unset,
## a raise records the ledger entry and puts nothing on the map -- which is the
## bug the 2026-09-26 review found, so Main always sets it.
var raise_handler: Callable = Callable()

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

## Where loot goes when a site pays out: `SortieSystem.take_into_party`. Held
## here rather than assigned site-by-site so that a site created at *runtime* --
## a dropped cache -- inherits it too, which the first version of this got wrong.
## Unset, sites fall back to the villain's own hands.
var party_filler: Callable = Callable()

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
	site.dead_riser = _raise_dead
	site.party_filler = party_filler
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

# ---------------- Dropped caches (SORTIE_SPEC amendment ruling 2) -------------

## A cache left in open country, holding exactly what was dropped in it.
##
## **Full reuse of the site machinery**, which is what the ruling asks for and
## also why it is this short: a cache is a site with `charges: 0` and a
## remainder. `actions_for()` already offers "Collect what you left" for a
## remainder and nothing else for zero charges; `is_spent()` already flips to
## the looted sprite when the last of it is taken. There is no cache *type* in
## code beyond the label.
##
## **Outside the density budget** (the 10-15 active sites): those are authored
## in `world_sites.json` and counted from the file, so a cache the player
## created cannot inflate it. **Never Raven-eligible** -- see
## `WorldSite.is_raven_eligible()`.
func spawn_dropped_cache(at: Vector2, suffix: String, sprite: String,
		looted_sprite: String, size_px: float) -> WorldSite:
	var band: int = 2
	if world:
		band = int(world.band_at(at).get("band", 2))
	var site := WorldSite.new()
	site.name = "DroppedCache_%s" % suffix
	site.day_provider = func(): return int(day_provider.call()) if day_provider.is_valid() else 1
	site.party_filler = party_filler
	site.guardian_spawner = _post_guardians
	site.dead_riser = _raise_dead
	site.setup({
		"id": "dropped_%s" % suffix,
		"name": "A Dropped Cache",
		"subtitle": "Yours, left where you put it",
		"sprite": sprite,
		"description": "Everything you could not carry, in a heap where you set it down. Nothing has found it yet.",
		"details": [],
		"lootable": {
			"type": "dropped_cache",
			"band": band,
			# Zero charges: it has no table and nothing to roll. Its whole
			# content is the remainder the drop puts in it.
			"charges": 0,
			"loot_table": "",
			"choices": "",
			"looted_sprite": looted_sprite,
			"guardian": null,
			"notice": {"threat": 0},
			"pool": "dropped",
			"active_count": 0,
		},
	}, at, size_px)
	add_child(site)
	sites.append(site)
	return site

## **A body where a villager fell** (LIVING_WORLD L1). An ordinary lootable
## site, like the dropped cache: the grave sheet's grammar -- raise it (a free
## skeleton, the Raise Dead ruling C applied to a fresh corpse), search it, or
## hide it -- from `site_choices.json`'s `body_choices`. Outside the density
## budget and never Raven-eligible, for the same reasons the cache is not.
const BODY_SPRITE := "res://assets/placeholder/generated/villager_body.png"
const BODY_SPRITE_GONE := "res://assets/placeholder/generated/villager_body_gone.png"

func spawn_body(at: Vector2, who: String) -> WorldSite:
	var band: int = 2
	if world:
		band = int(world.band_at(at).get("band", 2))
	var site := WorldSite.new()
	_bodies += 1
	site.name = "Body_%d" % _bodies
	site.day_provider = func(): return int(day_provider.call()) if day_provider.is_valid() else 1
	site.party_filler = party_filler
	site.guardian_spawner = _post_guardians
	site.dead_riser = _raise_dead
	site.setup({
		"id": "body_%d" % _bodies,
		"name": "%s's Body" % who,
		"subtitle": "Where he fell",
		"sprite": BODY_SPRITE,
		"description": "Still warm. The village will want him buried, if anyone finds him first.",
		"details": [],
		"lootable": {
			"type": "villager_body",
			"band": band,
			"charges": 1,
			"loot_table": "villager_body",
			"choices": "body_choices",
			"looted_sprite": BODY_SPRITE_GONE,
			"guardian": null,
			"notice": {"threat": 1},
			"pool": "bodies",
			"active_count": 0,
		},
	}, at, 44.0)
	# Found where he fell: nobody needs to discover a body they just made.
	site.discovered = true
	add_child(site)
	sites.append(site)
	return site

var _bodies: int = 0

func dropped_caches() -> Array:
	return sites.filter(func(s: WorldSite): return s.loot_type == "dropped_cache")

# ---------------- Raised dead -------------------------------------------------

## Puts a body on the map for each ledger entry the villain just made.
##
## One skeleton per entry, offset slightly around the grave so two raised from
## the same plot do not stack into one silhouette.
##
## **A real unit from its first frame** (ruling C, 2026-09-26). The first two
## versions of this put an inert `RaisedDead` view at the graveside and wrote
## "R2d binds them into the escort" -- R2d never did, and the review caught the
## corpse standing there for the rest of the run. Now the entry is live on
## arrival: the skeleton joins the roster, so an active escort binds it the next
## frame and otherwise it walks home to work. `dormant` stays in the entry as a
## record, set false.
func _raise_dead(site: WorldSite, villain, entries: Array) -> void:
	for i in range(entries.size()):
		var angle: float = TAU * float(raised.size() + i) / 5.0
		var at: Vector2 = site.position + Vector2(cos(angle), sin(angle)) \
			* float(SettlementGrid.CELL_SIZE) * 0.7
		if world:
			at = world.nearest_walkable(at)
		if not raise_handler.is_valid():
			push_warning("WorldSites: no raise_handler -- the corpse at %s stays in the ground." % site.site_id)
			continue
		var unit = raise_handler.call(at, villain, site)
		if unit == null:
			continue
		entries[i]["dormant"] = false
		entries[i]["unit"] = unit
		raised.append(unit)
		EventBus.skeleton_raised.emit(villain, unit, "grave")

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

## The nearest den still standing, or null. Feeds **the breadcrumb** (designer
## ruling, 2026-08-30 playtest: finding a den felt like a chore) -- one direction
## word in the dawn "tracks" log line (CombatSystem._note_the_tracks), so a
## player who has met the wolf has some idea
## which way their home is.
##
## Deliberately **not** a marker, not a path, and not a change to where wolves
## spawn: the entry point stays settlement-relative exactly as before (a wolf
## pathed from a den sixty cells away arrives at midnight or never). It is a hint
## in a sentence, and it goes quiet when the last den falls, because the quiet is
## the reward.
func nearest_uncleared_den(from: Vector2) -> WorldSite:
	var best: WorldSite = null
	var best_dist: float = INF
	for site in dens():
		if not site.is_guarded():
			continue
		var d: float = from.distance_to(site.position)
		if d < best_dist:
			best_dist = d
			best = site
	return best

# ---------------- Queries -----------------------------------------------------

## The lootable site he is standing on, or null. **Takes the villain**, never
## looks one up: sites answer to whoever walked up (section 3), and a second
## villain on the same map would ask the same question about himself.
# ---------------- Reachability (moved here from DebugSiteOverlay) --------------

## Cells a flood fill from the lair reaches, keyed `y * width + x`. Computed once:
## the map is fixed for the run. The F3 overlay and the Raven both ask through
## `is_reachable()`, so "can he get there" means one thing in this project.
var _reach_flood: Dictionary = {}
var _reach_done: bool = false

func is_reachable(site: WorldSite) -> bool:
	if world == null or site == null:
		return false
	if not _reach_done:
		_reach_done = true
		var lair: Vector2i = world.lair_origin + Vector2i(
			floori(SettlementGrid.GRID_WIDTH / 2.0), floori(SettlementGrid.GRID_HEIGHT / 2.0))
		_reach_flood = _flood_from(lair)
	return _connects(site, _reach_flood)

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

## Reachable means a walkable, flood-reached cell lies within the site's own
## interaction radius -- where he would have to stand to act on it.
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

# ---------------- Discovery and the Raven's pool (RAVEN_SPEC) ------------------

## Marks sites found by whoever is out there. `sources` is Main's fog-source
## list, `[[position, radius_cells], ...]` -- the villain's disc and each
## friendly unit's -- so "found" means exactly "somebody of his stood where he
## could see it". Read-only over the fog; returns the sites newly found.
func update_discovery(sources: Array) -> Array:
	var found: Array = []
	for site in sites:
		if not site.lootable or site.discovered:
			continue
		for src in sources:
			var r: float = float(src[1]) * float(WorldMap.CELL_SIZE)
			if site.position.distance_to(src[0]) <= r:
				site.discovered = true
				found.append(site)
				break
	return found

## RAVEN_SPEC section 4, as five separate answers so a harness can assert each.
func raven_checks(site: WorldSite) -> Dictionary:
	return {
		"reachable": is_reachable(site),
		"minor_band": site.band <= 2,
		"unguarded": not site.is_guarded(),
		"undiscovered": not site.discovered,
		"has_charge": site.charges_left > 0,
	}

## Every site the Raven may honestly name today: flagged eligible, and passing
## all five checks. Empty is a legal and correct answer.
func undiscovered_eligible() -> Array:
	var out: Array = []
	for site in sites:
		if not site.is_raven_eligible():
			continue
		var ok: bool = true
		for v in raven_checks(site).values():
			if not v:
				ok = false
				break
		if ok:
			out.append(site)
	return out

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
