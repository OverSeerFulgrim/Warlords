extends Node2D
class_name WorldSites
## Owns every fixed site and patrol on the world map, and answers "what did the
## player just click".
##
## Same shape as `ResourceField`: one container that loads its content from
## data, holds the nodes, and exposes queries -- **nothing reaches into `sites`
## or `patrols` directly**, so the pick rules stay in one place.
##
## Content lives in `data/world_sites.json`, positioned in **world cells**
## (converted here through `WorldMap`), because that is how the layout is
## reasoned about; the settlement's own buildings stay in settlement cells and
## are none of this file's business.

const DATA_PATH := "res://data/world_sites.json"

var world: WorldMap = null
var sites: Array = []      # Array[WorldSite]
var patrols: Array = []    # Array[Patrol]

## Named landmarks the travel instrumentation measures to, `name -> position`.
## Built from the same entries, so a site added to the JSON is automatically
## something travel times get reported for.
var landmarks: Dictionary = {}

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
	for entry in data.get("sites", []):
		_add_site(entry)
	for entry in data.get("patrols", []):
		_add_patrol(entry)
	return true

func _add_site(entry: Dictionary) -> void:
	var cell: Array = entry.get("cell", [0, 0])
	var at: Vector2 = world.cell_centre_px(Vector2i(int(cell[0]), int(cell[1])))
	var site := WorldSite.new()
	site.name = "Site_%s" % String(entry.get("id", "x"))
	add_child(site)
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

## Closest patrol then site within its own pick radius, or null. Patrols first
## for the same reason characters outrank scenery everywhere else: a man
## standing in front of a house is the thing you meant to click.
func pick_at(world_pos: Vector2) -> Node2D:
	for p in patrols:
		if world_pos.distance_to(p.position) <= p.hit_radius():
			return p
	var best: WorldSite = null
	var best_dist: float = INF
	for s in sites:
		var d: float = world_pos.distance_to(s.position)
		if d <= s.hit_radius() and d < best_dist:
			best_dist = d
			best = s
	return best
