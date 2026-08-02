extends Node
## BuildingCatalog (Autoload singleton)
## Loads data/buildings.json once and exposes it read-only, mirroring the
## data-driven pattern already used for events.json / missions.json /
## followers.json. Building instances themselves are still built via
## Building.make_from_data() (see Building.gd) -- this autoload only owns the
## catalog data, not construction, keeping a single source of truth for "what
## buildings exist and what do they cost" that both the build-menu UI and the
## recruitment housing-gate can query without holding a reference to Main.gd.

const BUILDINGS_PATH := "res://data/buildings.json"

var _buildings: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(BUILDINGS_PATH):
		push_warning("BuildingCatalog: buildings.json not found at %s" % BUILDINGS_PATH)
		return
	var f := FileAccess.open(BUILDINGS_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_warning("BuildingCatalog: failed to parse buildings.json")
		return
	_buildings = parsed
	# Strip documentation-only keys (e.g. "_comment", same convention as
	# events.json/missions.json/followers.json) so callers that iterate all
	# entries (all_ids, buildable_ids) never mistake one for a real building.
	# Those other loaders get away without this because they only ever look
	# up a single known key by id -- BuildingCatalog is the first one here
	# that iterates every top-level key, so this is where it has to be handled.
	for key in _buildings.keys().duplicate():
		if key.begins_with("_"):
			_buildings.erase(key)

## Returns the raw data Dictionary for a building_id, or {} if unknown.
func get_building(id: String) -> Dictionary:
	return _buildings.get(id, {})

## All building_ids in catalog order (Dictionary preserves insertion order in
## GDScript, so this matches buildings.json's authored order).
func all_ids() -> Array:
	return _buildings.keys()

## Buildable-in-the-build-menu entries only -- excludes "main" (auto-placed,
## never player-built), anything flagged `"locked": true` (out of scope for the
## current roadmap stage, but kept in the catalog -- see buildings.json's
## "_comment_locked"), and anything whose "requires" prerequisite building
## isn't present in the given settlement yet.
##
## Note the difference between the two exclusions: `locked` hides an entry from
## the *player*, while everything else in this autoload (get_building,
## all_ids) still returns it, so seeding, the housing gate, and any already-
## placed instance keep working unchanged.
func buildable_ids(settlement) -> Array:
	var result: Array = []
	for id in _buildings.keys():
		var data: Dictionary = _buildings[id]
		if data.get("category", "") == "main":
			continue
		if data.get("locked", false):
			continue
		# "unique": only one can ever exist, so it leaves the menu once built.
		# The Barracks is the only such entry (FOUNDATION_SPEC section 9:
		# "Capacity 5. Only one can ever exist.").
		if data.get("unique", false) and settlement.has_building(id):
			continue
		var requires: String = data.get("requires", "")
		if requires != "" and not settlement.has_building(requires):
			continue
		result.append(id)
	return result
