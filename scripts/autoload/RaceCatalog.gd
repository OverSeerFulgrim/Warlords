extends Node
## RaceCatalog (Autoload singleton)
## Loads data/races.json once and exposes it read-only -- same load-once
## pattern as BuildingCatalog, and the consumer the previous pass predicted
## when it added races.json as data-ahead-of-its-loader.
##
## Since the C2 stat rework this also owns the **derivation layer**: the six
## skill templates, the one-governing-attribute-per-skill map, and the formula
## that turns a baseline skill plus an attribute into the number the game
## actually uses. All three are DATA (`data/races.json`, written by
## `tools/export_roster.gd` from the workbook), not code -- COMBAT_SPEC §12
## step 3 is explicit that rebalancing must stay a data edit.
##
## `data/races.json` also carries the villain and wolf rows, which are units
## rather than recruitable races (COMBAT_SPEC amendment 2026-08-06 note 4).
## They have `attributes` and no skills; `recruitable_ids()` and
## `ids_in_category()` already exclude them by reading `recruitable`.

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
## Pulled out of races.json before the "_"-key strip below, because they are
## documentation-keyed by convention but genuinely load-bearing data.
var _templates: Dictionary = {}
var _governing: Dictionary = {}
var _derivation: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	_races = _load_json(RACES_PATH)
	# Read the derivation blocks BEFORE the strip. They are "_"-prefixed to keep
	# them out of all_ids(), but unlike the comment keys they are real data.
	_templates = _races.get("_skill_templates", {})
	_governing = _races.get("_governing_attribute", {})
	_derivation = _races.get("_derivation", {})
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

# ---------------- Attributes, skills, derivation (COMBAT_SPEC §2) -----------

## The nine attributes for a race, as authored in the workbook. Empty for an
## unknown id -- callers get REFERENCE_VALUE per attribute through
## `attribute()`, which is what keeps a typo'd id "average" rather than zero.
func attributes(race_id: String) -> Dictionary:
	return _races.get(race_id, {}).get("attributes", {})

## One of the nine. Falls back to the Human Peasant's 5 (see REFERENCE_VALUE) --
## except that a genuinely absent attribute is a data question, so an unknown
## *name* is worth noticing rather than silently averaging.
func attribute(race_id: String, attr_name: String) -> int:
	return int(attributes(race_id).get(attr_name, REFERENCE_VALUE))

## Baseline (pre-derivation) value for one of the twelve skills: the race's
## template value, unless the race overrides it.
##
## Template-plus-overrides rather than 204 authored numbers is COMBAT_SPEC §12
## step 2, and keeping it resolved *here* rather than flattened at export time
## is step 3: editing a template in the workbook still moves every race that
## did not opt out.
func skill_baseline(race_id: String, skill_name: String) -> int:
	var row: Dictionary = _races.get(race_id, {})
	var overrides: Dictionary = row.get("skill_overrides", {})
	if overrides.has(skill_name):
		return int(overrides[skill_name])
	var template: Dictionary = _templates.get(row.get("skill_template", ""), {})
	return int(template.get(skill_name, REFERENCE_VALUE))

## All twelve baselines for a race. Creature rows return {} -- a wolf has
## attributes but does not mine.
func skill_baselines(race_id: String) -> Dictionary:
	var out: Dictionary = {}
	if not _races.get(race_id, {}).has("skill_template"):
		return out
	for skill in _governing.keys():
		out[skill] = skill_baseline(race_id, skill)
	return out

## Which attribute governs a skill -- exactly one, never two (COMBAT_SPEC §2.2).
func governing_attribute(skill_name: String) -> String:
	return String(_governing.get(skill_name, ""))

func all_skill_names() -> Array:
	return _governing.keys()

## `effective_skill = clamp(skill + floor((attr - 5) / divisor), 1, 10)`.
##
## **Computed at use time, never stored** (COMBAT_SPEC §2.3): a stored copy goes
## stale the moment gear, training or a trait moves the attribute -- the same
## reasoning that keeps `max_hp()` computed.
##
## The float division is not incidental. Integer division truncates toward
## zero, so `(2 - 5) / 2` would give -1 where the formula wants -2, and every
## below-average attribute would quietly round in the unit's favour.
##
## The floor of 1 is **not cosmetic**: gather time is `4.0s * 5 / skill`, so a 0
## divides by zero, and a low template value plus a -2 modifier reaches 0 easily
## (a Skeleton Worker's Research lands at -1 before the clamp).
func effective_skill(baseline: int, attribute_value: int) -> int:
	var divisor: float = float(_derivation.get("divisor", 2))
	if divisor == 0.0:
		divisor = 2.0
	var modifier: int = floori(float(attribute_value - REFERENCE_VALUE) / divisor)
	return clampi(baseline + modifier, int(_derivation.get("min", 1)),
		int(_derivation.get("max", 10)))

## The race's effective value for a skill, resolving template, override and
## governing attribute in one call. What every consumer should use.
func effective_skill_for_race(race_id: String, skill_name: String) -> int:
	return effective_skill(skill_baseline(race_id, skill_name),
		attribute(race_id, governing_attribute(skill_name)))

func skill_templates() -> Dictionary:
	return _templates

func derivation() -> Dictionary:
	return _derivation

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

## The **attribute** the 5% exceptional roll bumps for a category:
## "strength" / "intelligence" / "perception" / "best_labor_attribute" / "none".
## See recruitment.json's _comment_exceptional for why the bump moved from a
## skill to an attribute, and what best_labor_attribute resolves to per recruit.
func defining_stat_for_category(cat: String) -> String:
	return _recruitment.get("category_defining_stat", {}).get(cat, "none")

func first_run_categories() -> Array:
	return _recruitment.get("first_run_categories", [])

func stat_roll_config() -> Dictionary:
	return _recruitment.get("stat_roll", {"dice_sides": 3, "min_value": 1, "max_value": 10})
