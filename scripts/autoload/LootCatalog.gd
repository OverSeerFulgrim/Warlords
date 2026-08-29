extends Node
## LootCatalog (Autoload singleton)
## Loads `data/loot_tables.json`, `data/relics.json` and `data/site_choices.json`
## once and owns **the roll**, which is the only interesting thing in here.
##
## Same shape as `BuildingCatalog` and `RaceCatalog`: load-once, read-only, no
## construction. The difference is that this one also implements
## `LOOT_SITES_SPEC.md` section 5's rolling rule, because a table is not data
## you can read a number out of -- it is data you have to *resolve*, and putting
## the resolution anywhere else would mean `WorldSite`, the harness and any
## future caller each having their own idea of what "rolled twice without
## replacement of the unique entries" means.
##
## ## What the roll is
##
## `roll(table_id, drawn_relics)` picks `rolls` entries by weight. An entry
## marked `unique` is removed for the rest of *that* resolution. A relic entry
## names a rarity **tier**, not a relic: the catalog picks an undrawn relic of
## that tier, so `relics.json` can grow without a table edit. Relics are unique
## **per run** (section 7), and the caller owns the run-scoped drawn set -- this
## object is an autoload and must not accumulate run state (ROGUELITE_REWORK
## section 11: the villain owns per-villain state, and a second villain would
## draw from the same catalog with his own set).
##
## ## Why the harness can trust it
##
## `tools/verify_loot_tables.tscn` calls exactly this function 10,000 times per
## table and compares the means against section 5's band table. There is
## deliberately no second, simplified copy of the roll in the harness -- a
## harness that reimplements the thing it is checking only ever proves that two
## authors agreed.

const TABLES_PATH := "res://data/loot_tables.json"
const RELICS_PATH := "res://data/relics.json"
const CHOICES_PATH := "res://data/site_choices.json"

## The kinds a loot table may pay out. `gold` is new in R2 (section 5) and
## `arms` is the 2026-08-29 amendment's ruling 2 -- both field-only, neither
## worker-gatherable, which is section 1.1's first law expressed as a list.
const LOOT_KINDS := ["bones", "wood", "stone", "food", "gold", "dark_essence", "arms"]

## The kinds section 5's "mundane units" column counts. Gold and Dark Essence
## are tracked in their own columns, so they are deliberately not here; `arms`
## is, because a unit of arms fills a carry slot exactly like a unit of bones.
const MUNDANE_KINDS := ["bones", "wood", "stone", "food", "arms"]

const RELIC_TIERS := ["trinket", "uncommon", "rare", "legendary"]

var _tables: Dictionary = {}
var _relics: Dictionary = {}      # id -> Dictionary
var _by_tier: Dictionary = {}     # tier -> Array[String]
var _choices: Dictionary = {}

func _ready() -> void:
	_tables = _load_object(TABLES_PATH)
	_choices = _load_object(CHOICES_PATH)
	_load_relics()

func _load_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("LootCatalog: %s not found" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("LootCatalog: %s is not a JSON object" % path)
		return {}
	var out: Dictionary = parsed
	# Same underscore convention every other data file uses for documentation
	# keys, and the same reason BuildingCatalog strips them: this loader
	# iterates all top-level keys, so a "_comment" would otherwise read as a
	# table with no entries.
	for key in out.keys().duplicate():
		if String(key).begins_with("_"):
			out.erase(key)
	return out

func _load_relics() -> void:
	var data: Dictionary = _load_object(RELICS_PATH)
	for entry in data.get("relics", []):
		var id: String = String(entry.get("id", ""))
		if id == "":
			continue
		_relics[id] = entry
		var tier: String = String(entry.get("tier", "trinket"))
		if not _by_tier.has(tier):
			_by_tier[tier] = []
		_by_tier[tier].append(id)

# ---------------- Reading ----------------------------------------------------

func has_table(id: String) -> bool:
	return _tables.has(id)

func table(id: String) -> Dictionary:
	return _tables.get(id, {})

func table_ids() -> Array:
	return _tables.keys()

func relic(id: String) -> Dictionary:
	return _relics.get(id, {})

func has_relic(id: String) -> bool:
	return _relics.has(id)

func relic_ids() -> Array:
	return _relics.keys()

func relics_of_tier(tier: String) -> Array:
	return _by_tier.get(tier, [])

func choice_sheet(id: String) -> Dictionary:
	return _choices.get(id, {})

func has_choice_sheet(id: String) -> bool:
	return _choices.has(id)

func choice_sheet_ids() -> Array:
	return _choices.keys()

# ---------------- The roll ---------------------------------------------------

## Resolves `table_id` once. `drawn_relics` is the run's already-found relic ids
## -- passed in, never held here, so relic uniqueness is the villain's state and
## not the autoload's.
##
## Returns `{"resources": {kind: amount}, "relics": [id]}`. Amounts are the raw
## roll: nothing here knows about carry capacity, and what does not fit becomes
## the site's remainder charge (`SORTIE_SPEC.md` section 4), which is the
## caller's job.
##
## `fraction` scales the resource half only, for choices that take part of a
## haul (the shrine's "leave the stone standing"). Relics do not halve -- half a
## relic is not a thing -- so a fractional take rolls them at the same odds.
func roll(table_id: String, drawn_relics: Array = [], fraction: float = 1.0) -> Dictionary:
	var out := {"resources": {}, "relics": []}
	var t: Dictionary = _tables.get(table_id, {})
	if t.is_empty():
		push_warning("LootCatalog.roll: no table '%s'" % table_id)
		return out
	var taken: Array = drawn_relics.duplicate()

	# Guaranteed entries resolve before the weighted rolls and are not part of
	# them -- that is what makes "the crypt always pays a rare" and "the outlaw
	# cave always has weapons in it" true by data rather than by a lucky table.
	for entry in t.get("guaranteed", []):
		_resolve_entry(entry, out, taken, fraction)

	var pool: Array = []
	for entry in t.get("entries", []):
		pool.append(entry)
	var rolls: int = int(t.get("rolls", 1))
	for i in range(rolls):
		if pool.is_empty():
			break
		var entry: Dictionary = _pick_weighted(pool)
		if entry.is_empty():
			break
		if bool(entry.get("unique", false)):
			pool.erase(entry)
		_resolve_entry(entry, out, taken, fraction)
	return out

func _pick_weighted(pool: Array) -> Dictionary:
	var total: float = 0.0
	for entry in pool:
		total += maxf(0.0, float(entry.get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var pick: float = randf() * total
	for entry in pool:
		pick -= maxf(0.0, float(entry.get("weight", 0.0)))
		if pick <= 0.0:
			return entry
	return pool[pool.size() - 1]

## One entry into the result. Three shapes: a named relic, a relic tier, or a
## resource amount. A relic entry that finds nothing left of its tier pays out
## nothing rather than substituting -- relics are unique per run and a silent
## downgrade would make "guaranteed rare" quietly false on the second crypt.
func _resolve_entry(entry: Dictionary, out: Dictionary, taken: Array, fraction: float) -> void:
	if entry.has("relic") or entry.has("relic_tier"):
		var id: String = ""
		if entry.has("relic"):
			id = String(entry["relic"])
			if taken.has(id) or not _relics.has(id):
				return
		else:
			id = _undrawn_of_tier(String(entry["relic_tier"]), taken)
			if id == "":
				return
		taken.append(id)
		out["relics"].append(id)
		return
	var kind: String = String(entry.get("kind", ""))
	if kind == "":
		return
	if not LOOT_KINDS.has(kind):
		push_warning("LootCatalog: unknown loot kind '%s'" % kind)
		return
	var lo: int = int(entry.get("min", 1))
	var hi: int = int(entry.get("max", lo))
	var amount: int = randi_range(mini(lo, hi), maxi(lo, hi))
	if fraction < 1.0:
		# Rounded up: a half-take of one unit is one unit, because a choice that
		# can pay literally nothing is not a choice worth putting on the panel.
		amount = maxi(1, int(ceil(float(amount) * fraction)))
	if amount <= 0:
		return
	out["resources"][kind] = int(out["resources"].get(kind, 0)) + amount

func _undrawn_of_tier(tier: String, taken: Array) -> String:
	var candidates: Array = []
	for id in _by_tier.get(tier, []):
		if not taken.has(id):
			candidates.append(id)
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]

# ---------------- Small helpers the panel and the log share -------------------

## "3 Bones, 2 Gold" -- in one place, so the log line and the inspection payload
## cannot describe the same haul differently.
static func describe(resources: Dictionary) -> String:
	var parts: Array = []
	for kind in resources.keys():
		parts.append("%d %s" % [int(resources[kind]), String(kind).capitalize().replace("_", " ")])
	return ", ".join(parts) if not parts.is_empty() else "nothing"

func describe_relics(ids: Array) -> String:
	var parts: Array = []
	for id in ids:
		parts.append(String(relic(id).get("name", id)))
	return ", ".join(parts)
