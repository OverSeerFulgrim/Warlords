extends Node
## RaceCatalog (Autoload singleton)
## Loads data/races.json once and exposes it read-only -- same load-once
## pattern as BuildingCatalog, and the consumer the previous pass predicted
## when it added races.json as data-ahead-of-its-loader.
##
## Right now the only caller is Worker.gd (the "skeleton_worker" row: might,
## walk_speed, and the three labor skills). The recruit generator, food/morale
## tick, and fund-a-house placement rules will all read from here too -- which
## is why this exposes the whole row rather than just the handful of fields
## Worker currently needs.

const RACES_PATH := "res://data/races.json"
## Recruitment tuning lives in its own file because it's the playtest knobs
## (rarity weights, roll dice, exceptional chance), not facts about a race.
## Loaded here rather than in a fourth autoload because every consumer that
## wants one wants the other -- RecruitGenerator needs the roster *and* the
## weights in the same breath.
const RECRUITMENT_PATH := "res://data/recruitment.json"

## FOUNDATION_SPEC section 1: the Human Peasant is 5 in everything, and every
## other race is stated relative to him. Used as the fallback for a missing
## race/stat so a typo'd race id degrades to "average" instead of to zero --
## a 0 skill would divide-by-zero in the gather-time formula (see
## FOUNDATION_SPEC section 6), which is a much worse failure than being wrong.
const REFERENCE_VALUE: int = 5

var _races: Dictionary = {}
var _recruitment: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	_races = _load_json(RACES_PATH)
	# Same "_"-prefixed documentation-key convention as buildings.json --
	# stripped here for the same reason BuildingCatalog strips it: all_ids()
	# below iterates every top-level key.
	for key in _races.keys().duplicate():
		if key.begins_with("_"):
			_races.erase(key)
	# recruitment.json is NOT stripped: nothing iterates its top-level keys,
	# every read is a known-name lookup, and stripping would need a second
	# convention for its "_comment_*" keys anyway.
	_recruitment = _load_json(RECRUITMENT_PATH)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("RaceCatalog: %s not found" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_warning("RaceCatalog: failed to parse %s" % path)
		return {}
	return parsed

## The raw data Dictionary for a race id, or {} if unknown.
func get_race(id: String) -> Dictionary:
	return _races.get(id, {})

func all_ids() -> Array:
	return _races.keys()

## Recruitable races only -- excludes the Human Peasant reference row and the
## player-made Skeleton Worker. Nothing calls this yet; it's what the recruit
## generator will draw its offer pool from.
func recruitable_ids() -> Array:
	var result: Array = []
	for id in _races.keys():
		if _races[id].get("recruitable", false):
			result.append(id)
	return result

## One of the four character stats (might/guile/influence/loyalty).
func stat(race_id: String, stat_name: String) -> int:
	return _races.get(race_id, {}).get("stats", {}).get(stat_name, REFERENCE_VALUE)

## One of the three labor skills (woodcutting/mining/foraging). These drive
## work *speed*, not permissions -- anyone can chop, skill decides how fast
## (FOUNDATION_SPEC section 1).
func labor(race_id: String, skill_name: String) -> int:
	return _races.get(race_id, {}).get("labor", {}).get(skill_name, REFERENCE_VALUE)

## Racial constant, 1.0 = the Human Peasant = 1 grid cell per second.
func walk_speed(race_id: String) -> float:
	return float(_races.get(race_id, {}).get("walk_speed", 1.0))

## Racial constant. 0 for undead -- skeletons eat nothing.
func food_per_meal(race_id: String) -> float:
	return float(_races.get(race_id, {}).get("food_per_meal", 1.0))

## res:// path to the race's on-map token art, or "" if it has none (the
## Human Peasant reference row). Data-driven so adding a race never means
## touching a sprite Dictionary in Main.gd -- see races.json's
## "_comment_sprites", which also lists the unused *_Armed / _Miner variants.
func sprite(race_id: String) -> String:
	return _races.get(race_id, {}).get("sprite", "")

func category(race_id: String) -> String:
	return _races.get(race_id, {}).get("category", "")

func rarity(race_id: String) -> String:
	return _races.get(race_id, {}).get("rarity", "")

## Recruitable race ids in a given category (e.g. every "Warrior" race).
func ids_in_category(cat: String) -> Array:
	var result: Array = []
	for id in _races.keys():
		var row: Dictionary = _races[id]
		if row.get("recruitable", false) and row.get("category", "") == cat:
			result.append(id)
	return result

# ---------------- Recruitment tuning (data/recruitment.json) ----------------

## The rarity weights in force at a given settlement Power -- RACES.md's
## "power attracts power". Walks the tier table and takes the last entry whose
## min_power has been reached, so the table stays declarative and adding a tier
## is a JSON edit rather than another branch here.
func rarity_weights_for_power(power: int) -> Dictionary:
	var tiers: Array = _recruitment.get("power_rarity_tiers", [])
	var chosen: Dictionary = {}
	for tier in tiers:
		if power >= int(tier.get("min_power", 0)):
			chosen = tier.get("weights", {})
	return chosen

func exceptional_chance_percent() -> float:
	return float(_recruitment.get("exceptional_chance_percent", 5))

## "might" / "guile" / "foraging" / "best_labor" / "none" -- see
## recruitment.json's _comment_exceptional for what best_labor means.
func defining_stat_for_category(cat: String) -> String:
	return _recruitment.get("category_defining_stat", {}).get(cat, "none")

func first_run_categories() -> Array:
	return _recruitment.get("first_run_categories", [])

func stat_roll_config() -> Dictionary:
	return _recruitment.get("stat_roll", {"dice_sides": 3, "min_value": 1, "max_value": 10})
