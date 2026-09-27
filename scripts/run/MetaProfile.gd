extends RefCounted
class_name MetaProfile
## What survives between runs: XP per villain class, the chronicle, and **the
## stash** -- the gear and relics kept from runs, and how the Lair displays them
## (ROGUELITE_REWORK section 2's persist ledger, section 10, and the 2026-09-26
## rulings in section 17.6-17.7).
##
## ## A file, not an autoload
##
## The run lifecycle that owns one of these is per-villain, and a second class
## (the Demonologist) keeps its own XP under its own `class_id` in the same
## file. Nothing here is in-run state, so CLAUDE.md's "no per-villain state in
## an autoload" never comes up: this object is handed to whoever needs it.
##
## ## Levels are computed, never stored
##
## Only total XP is written. Level and unlocks are derived from it and
## `data/progression.json` at read time -- the same "computed at use time"
## discipline as effective skills -- so re-tuning the curve re-levels every
## profile without a migration.
##
## ## Persistence is opt-in
##
## `path == ""` keeps everything in memory. The harnesses instantiate
## `Main.tscn` and kill the villain on purpose; that must never write XP into
## the player's real profile, so `RunLifecycle` only hands a path over when Main
## is the running scene (see `Main._build_run_lifecycle`).

const DATA_PATH := "res://data/progression.json"
const DEFAULT_PATH := "user://meta_profile.json"
const VERSION := 1

var path: String = ""
var classes: Dictionary = {}     # class_id -> {"xp": int, "runs": int, "best_day": int}
var chronicle: Array = []        # newest last: {"run", "class", "ending", "day", "xp", "epitaph"}

## **The stash** (ROGUELITE_REWORK section 10, rulings 17.6-17.7): every item kept
## from a run. "Items" are gear and relics -- relics today; gold and resources
## reset every run. Each entry:
##   {"uid", "id" (relic id), "run", "day", "shelf" (-1 = not on display),
##    "carry" (true = going into the next run), "risked" (runs survived carried)}
## Shared across classes: the Lair is the player's, not the villain's.
var stash: Array = []
var _next_uid: int = 1

## **Blueprints known for good** (LIVING_WORLD section 9.1 / 12): building ids.
## Acquired from the world -- found, flipped, bought -- and never lost. You still
## build them each run. The Dark Altar is the first every player earns: it is
## inside the first wolf den (section 3).
var blueprints: Array = []

## Display spots in the Lair's hall. A room, not a warehouse -- more come with
## the room when the Lair grows.
const LAIR_SHELVES: int = 8
static var _data: Dictionary = {}

## The progression table, loaded once. Static so a harness can read the same
## numbers the game does without a profile in hand.
static func data() -> Dictionary:
	if _data.is_empty():
		if FileAccess.file_exists(DATA_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		if _data.is_empty():
			push_error("MetaProfile: %s missing or not a JSON object." % DATA_PATH)
			_data = {"level_curve": {"step": 100, "max_level": 20}, "unlocks": [], "deed_base": {},
				"band_multiplier": {}, "event_xp": {}, "run_end_xp": {}}
	return _data

# ---------------- Load / save -------------------------------------------------

static func open(file_path: String) -> MetaProfile:
	var p := MetaProfile.new()
	p.path = file_path
	if file_path != "" and FileAccess.file_exists(file_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			p.classes = parsed.get("classes", {})
			p.chronicle = parsed.get("chronicle", [])
			p.stash = parsed.get("stash", [])
			p.blueprints = parsed.get("blueprints", [])
			p._next_uid = int(parsed.get("next_uid", 1))
			for e in p.stash:
				p._next_uid = maxi(p._next_uid, int(e.get("uid", 0)) + 1)
		else:
			push_warning("MetaProfile: %s is unreadable; starting a fresh profile (the old file is left alone)." % file_path)
			p.path = file_path + ".fresh"
	return p

func save() -> bool:
	if path == "":
		return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("MetaProfile: cannot write %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify({"version": VERSION, "classes": classes, "chronicle": chronicle,
		"stash": stash, "next_uid": _next_uid, "blueprints": blueprints}, "\t"))
	f.close()
	return true

# ---------------- XP and level ------------------------------------------------

func _entry(class_id: String) -> Dictionary:
	if not classes.has(class_id):
		classes[class_id] = {"xp": 0, "runs": 0, "best_day": 0}
	return classes[class_id]

func xp(class_id: String) -> int:
	return int(_entry(class_id).get("xp", 0))

## Banks XP immediately (ROGUELITE section 9) and returns the level it lands on.
func add_xp(class_id: String, amount: int) -> int:
	if amount > 0:
		var e: Dictionary = _entry(class_id)
		e["xp"] = int(e.get("xp", 0)) + amount
		save()
	return level(class_id)

func level(class_id: String) -> int:
	return MetaProfile.level_for_xp(xp(class_id))

## Total XP needed to *be* level `lvl`: step x L x (L-1) / 2 (docs/design/PROGRESSION.md).
static func threshold(lvl: int) -> int:
	var step: int = int(data().get("level_curve", {}).get("step", 100))
	# L x (L-1) is always even, so the division is exact.
	@warning_ignore("integer_division")
	return step * lvl * (lvl - 1) / 2

static func max_level() -> int:
	return int(data().get("level_curve", {}).get("max_level", 20))

static func level_for_xp(total: int) -> int:
	var lvl: int = 1
	while lvl < max_level() and total >= threshold(lvl + 1):
		lvl += 1
	return lvl

## `[xp into this level, xp this level spans]`; the span is 0 at the cap.
static func level_progress(total: int) -> Array:
	var lvl: int = level_for_xp(total)
	if lvl >= max_level():
		return [total - threshold(lvl), 0]
	return [total - threshold(lvl), threshold(lvl + 1) - threshold(lvl)]

## XP for one deed: its base size times the band it happened in. Unknown deeds
## pay `default`; a deed with no band (0) counts as band 1.
static func deed_xp(deed_id: String, band: int) -> int:
	var bases: Dictionary = data().get("deed_base", {})
	var base: int = int(bases.get(deed_id, bases.get("default", 0)))
	var mults: Dictionary = data().get("band_multiplier", {})
	var b: int = clampi(band, 1, 4)
	return base * int(mults.get(str(b), b))

static func event_xp(key: String) -> int:
	return int(data().get("event_xp", {}).get(key, 0))

# ---------------- Unlocks -----------------------------------------------------

func unlocked(class_id: String) -> Array:
	var lvl: int = level(class_id)
	return data().get("unlocks", []).filter(func(u): return int(u.get("level", 1)) <= lvl)

func has_unlock(class_id: String, unlock_id: String) -> bool:
	for u in unlocked(class_id):
		if String(u.get("id", "")) == unlock_id:
			return true
	return false

## The first unlock not yet reached, or {} when there is none left.
func next_unlock(class_id: String) -> Dictionary:
	var lvl: int = level(class_id)
	var best: Dictionary = {}
	for u in data().get("unlocks", []):
		var at: int = int(u.get("level", 1))
		if at > lvl and (best.is_empty() or at < int(best.get("level", 999))):
			best = u
	return best

static func unlock_def(unlock_id: String) -> Dictionary:
	for u in data().get("unlocks", []):
		if String(u.get("id", "")) == unlock_id:
			return u
	return {}

# ---------------- The chronicle -----------------------------------------------

## Records a finished run and returns its number for this class.
func record_run(class_id: String, ending: String, day: int, run_xp: int, epitaph: String) -> int:
	var e: Dictionary = _entry(class_id)
	e["runs"] = int(e.get("runs", 0)) + 1
	e["best_day"] = maxi(int(e.get("best_day", 0)), day)
	chronicle.append({"run": int(e["runs"]), "class": class_id, "ending": ending,
		"day": day, "xp": run_xp, "epitaph": epitaph})
	var keep: int = int(data().get("chronicle_keep", 50))
	while chronicle.size() > keep:
		chronicle.pop_front()
	save()
	return int(e["runs"])

func runs(class_id: String) -> int:
	return int(_entry(class_id).get("runs", 0))

func recent(class_id: String, n: int) -> Array:
	var out: Array = chronicle.filter(func(c): return String(c.get("class", "")) == class_id)
	return out.slice(maxi(0, out.size() - n))

# ---------------- Blueprints (LIVING_WORLD section 9.1) ------------------------

func knows_blueprint(id: String) -> bool:
	return blueprints.has(id)

## Learns one, for good. Returns false if it was already known.
func learn_blueprint(id: String) -> bool:
	if id == "" or blueprints.has(id):
		return false
	blueprints.append(id)
	save()
	return true

# ---------------- The stash and the Lair (ROGUELITE_REWORK section 10) ---------

## Adds a kept item and returns its entry.
func add_to_stash(item_id: String, run: int, day: int) -> Dictionary:
	var e := {"uid": _next_uid, "id": item_id, "run": run, "day": day,
		"shelf": -1, "carry": false, "risked": 0}
	_next_uid += 1
	stash.append(e)
	save()
	return e

func stash_entry(uid: int) -> Dictionary:
	for e in stash:
		if int(e.get("uid", 0)) == uid:
			return e
	return {}

## Gone for good -- what death does to an item carried into a run.
func remove_from_stash(uid: int) -> void:
	for i in range(stash.size()):
		if int(stash[i].get("uid", 0)) == uid:
			stash.remove_at(i)
			save()
			return

## How many stash items may go into a run: 1, unlockable to a maximum of 3
## (section 10: "never exceed 3"). Each `relic_slot` unlock reached adds one.
func carry_slots(class_id: String) -> int:
	var n: int = 1
	for u in unlocked(class_id):
		if String(u.get("id", "")).begins_with("relic_slot"):
			n += 1
	return mini(n, 3)

func carried_entries() -> Array:
	return stash.filter(func(e): return bool(e.get("carry", false)))

## Marks an item to go into the next run. Refuses past the slot count.
func set_carry(class_id: String, uid: int, on: bool) -> bool:
	var e: Dictionary = stash_entry(uid)
	if e.is_empty():
		return false
	if on and not bool(e.get("carry", false)) and carried_entries().size() >= carry_slots(class_id):
		return false
	e["carry"] = on
	save()
	return true

## Puts an item on a shelf in the hall (or takes it down with -1). One item per
## shelf; whatever was there goes back into the stash.
func set_shelf(uid: int, shelf: int) -> bool:
	var e: Dictionary = stash_entry(uid)
	if e.is_empty() or shelf >= LAIR_SHELVES:
		return false
	if shelf >= 0:
		for other in stash:
			if int(other.get("shelf", -1)) == shelf:
				other["shelf"] = -1
	e["shelf"] = shelf
	save()
	return true

func on_shelf(shelf: int) -> Dictionary:
	for e in stash:
		if int(e.get("shelf", -1)) == shelf:
			return e
	return {}
