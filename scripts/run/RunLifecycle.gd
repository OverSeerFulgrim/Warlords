extends Node
class_name RunLifecycle
## The run, as a thing that starts and ends (ROGUELITE_REWORK section 1, R4-lite).
##
## Ruled 2026-09-26: **death ends the run.** A run-end screen shows the run's
## stats and the villain's XP and level; waking at the Throne after a death is an
## unlock earned by levelling ("Second Wake", `data/progression.json`), not the
## default. This node is the one place that decides which of those happens.
##
## ## One per villain, holding him as a field
##
## Like `SortieSystem`, it is handed its villain and never looks one up
## (ROGUELITE_REWORK section 11). Every signal carrying a villain is
## owner-checked -- the combat harness kills a thousand throwaway Necromancers,
## and each of those must not end the player's run.
##
## ## Order on death
##
## Built after `SortieSystem` and `CombatSystem`, so its `villain_died` handler
## runs third: the unbanked haul is already gone (SORTIE_SPEC section 6) and he
## is already out of every fight. Only then does this choose between waking him
## at the Throne and ending the run.
##
## ## What it does not do
##
## No flee-the-region (R4 proper), no map shuffle, no stash, no Lair hub. The
## victory condition is still GameState's legacy one until the manor exists; it
## is routed through here so that when it changes, the ending already has a home.

## Who and what. Set by Main before add_child.
var villain: Necromancer = null
var sortie_system: SortieSystem = null
var day_night: DayNightCycle = null
var profile: MetaProfile = null

## Pause the tree when the run ends. The harnesses that kill him to test
## something else turn this off rather than grinding to a halt.
var pause_on_end: bool = true

## Second Wakes left this run. Read from the profile's unlocks at start, so a
## level earned mid-run does not hand out a wake until the next run.
var wakes_left: int = 0

var ended: bool = false
var summary: Dictionary = {}

## Game-seconds this run has lasted. A delta accumulator, so it scales with the
## debug time scale like every other clock (CLAUDE.md) and stops while paused.
var run_seconds: float = 0.0

var stats: Dictionary = {
	"deeds": {},            # deed_id -> count
	"sites_looted": 0,
	"skeletons_raised": 0,  # every skeleton, graves and bones alike
	"raised_at_graves": 0,
	"wolves_killed": 0,
	"buildings_placed": 0,
	"banked_units": 0,
	"relics_banked": 0,
	"max_escort": 0,
	"wakes_used": 0,
	"xp": 0,
}

## Who struck him last -- read for the epitaph.
var _last_foe: String = ""

## Set the moment he dies without a wake, before the deferred end_run lands.
var _dying: bool = false

func _ready() -> void:
	if profile == null:
		profile = MetaProfile.open("")
	if villain != null:
		var def: Dictionary = MetaProfile.unlock_def("second_wake")
		if profile.has_unlock(villain.class_id, "second_wake"):
			wakes_left = int(def.get("uses_per_run", 1))
	EventBus.villain_died.connect(_on_villain_died)
	EventBus.deed_committed.connect(_on_deed)
	EventBus.villain_engaged.connect(_on_engaged)
	EventBus.site_looted.connect(_on_site_looted)
	EventBus.sortie_deposited.connect(_on_deposited)
	EventBus.skeleton_raised.connect(_on_skeleton_raised)
	EventBus.wolf_killed.connect(_on_wolf_killed)
	EventBus.building_placed.connect(_on_building_placed)
	GameState.game_lost.connect(_on_game_lost)
	GameState.game_won.connect(_on_game_won)
	set_process(true)

func _process(delta: float) -> void:
	if ended or villain == null:
		return
	run_seconds += delta
	stats["max_escort"] = maxi(int(stats["max_escort"]), villain.escort.size())

# ---------------- XP ----------------------------------------------------------

## Banks `amount` now, and announces a level-up with whatever it unlocked.
func award(amount: int, reason: String) -> void:
	if amount <= 0 or villain == null:
		return
	var before: int = profile.level(villain.class_id)
	profile.add_xp(villain.class_id, amount)
	stats["xp"] = int(stats["xp"]) + amount
	var total: int = profile.xp(villain.class_id)
	EventBus.xp_gained.emit(villain, amount, total, reason)
	var after: int = profile.level(villain.class_id)
	if after > before:
		var fresh: Array = []
		for u in MetaProfile.data().get("unlocks", []):
			var at: int = int(u.get("level", 1))
			if at > before and at <= after:
				fresh.append(u)
		EventBus.villain_levelled.emit(villain, after, fresh)

func _xp_for_deed(deed_id: String) -> int:
	var table: Dictionary = MetaProfile.data().get("deed_xp", {})
	return int(table.get(deed_id, table.get("default", 0)))

func _event_xp(key: String) -> int:
	return int(MetaProfile.data().get("event_xp", {}).get(key, 0))

# ---------------- Listening (owner-checked) -----------------------------------

func _mine(v) -> bool:
	return v != null and v == villain and not ended and not _dying

func _on_deed(v, deed_id: String, _axes: Dictionary) -> void:
	if not _mine(v):
		return
	var d: Dictionary = stats["deeds"]
	d[deed_id] = int(d.get(deed_id, 0)) + 1
	award(_xp_for_deed(deed_id), deed_id)

func _on_engaged(v, foe_name: String) -> void:
	if _mine(v):
		_last_foe = foe_name

func _on_site_looted(v, _site, _loot: Dictionary) -> void:
	if _mine(v):
		stats["sites_looted"] = int(stats["sites_looted"]) + 1

func _on_deposited(v, load_in: Dictionary, relics: Array) -> void:
	if not _mine(v):
		return
	var units: int = 0
	for k in load_in.keys():
		units += int(load_in[k])
	stats["banked_units"] = int(stats["banked_units"]) + units
	stats["relics_banked"] = int(stats["relics_banked"]) + relics.size()
	award(units * _event_xp("banked_unit") + relics.size() * _event_xp("relic_banked"), "brought home")

func _on_skeleton_raised(v, _unit, source: String) -> void:
	if not _mine(v):
		return
	stats["skeletons_raised"] = int(stats["skeletons_raised"]) + 1
	if source == "grave":
		stats["raised_at_graves"] = int(stats["raised_at_graves"]) + 1

## Not villain-scoped: a wolf dies to his escort, his workers or him, and all
## of those are his settlement's. A second villain's settlement will need its
## own filter here.
func _on_wolf_killed(_at: Vector2, _bones: int) -> void:
	if ended:
		return
	stats["wolves_killed"] = int(stats["wolves_killed"]) + 1
	award(_event_xp("wolf_killed"), "wolf killed")

func _on_building_placed(building, _cell: Vector2i) -> void:
	# The Throne is seeded, not built -- it paid 5 XP at the start of every run
	# until the first scripted playthrough caught it.
	if ended or (building != null and "is_main_building" in building and building.is_main_building):
		return
	stats["buildings_placed"] = int(stats["buildings_placed"]) + 1
	award(_event_xp("building_placed"), "building raised")

# ---------------- Endings -----------------------------------------------------

## Third in line (see the header). The haul is gone and he is out of every
## fight; a Second Wake puts him back at the Throne, otherwise the run is over.
func _on_villain_died(v, cause: String) -> void:
	if not _mine(v):
		return
	if wakes_left > 0:
		wakes_left -= 1
		stats["wakes_used"] = int(stats["wakes_used"]) + 1
		var at: Vector2 = sortie_system.throne_position() if sortie_system else Vector2.INF
		if at != Vector2.INF:
			v.place_at(at)
		v.clear_move_target()
		v.heal_full()
		EventBus.villain_woke.emit(v, wakes_left)
		return
	var by: String = _last_foe if _last_foe != "" else cause
	# **Deferred to the end of the frame.** `villain_died` is emitted from inside
	# a combat exchange; ending the run there paused the tree mid-exchange and
	# put the epitaph in the log above the line announcing the death. Waiting
	# one idle step lets every other handler (Main's log, the HUD) finish first.
	# `_dying` blocks a second death or a Surrender in the same frame.
	_dying = true
	end_run.call_deferred("slain", by)

func _on_game_lost(reason: String) -> void:
	end_run("throne_fell", reason)

func _on_game_won() -> void:
	end_run("victory", "")

## Surrender. Main's button, and the only ending the player chooses.
func abandon() -> void:
	if _dying:
		return
	end_run("abandoned", "")

func end_run(ending: String, detail: String) -> void:
	if ended or villain == null:
		return
	# Survival pays once, here, in full days -- the part of the run that was not
	# any single deed.
	var days_done: int = maxi(0, (day_night.day_number if day_night else 1) - 1)
	var ends: Dictionary = MetaProfile.data().get("run_end_xp", {})
	award(days_done * int(ends.get("per_day", 0)), "days survived")
	if ending == "victory":
		award(int(ends.get("victory", 0)), "victory")
	ended = true

	var day: int = day_night.day_number if day_night else 1
	var run_number: int = profile.runs(villain.class_id) + 1
	var epitaph: String = _epitaph(run_number, ending, detail, day)
	profile.record_run(villain.class_id, ending, day, int(stats["xp"]), epitaph)

	var total: int = profile.xp(villain.class_id)
	summary = {
		"ending": ending,
		"detail": detail,
		"title": _title(ending),
		"epitaph": epitaph,
		"run_number": run_number,
		"day": day,
		"run_seconds": run_seconds,
		"stats": stats.duplicate(true),
		"xp_run": int(stats["xp"]),
		"xp_total": total,
		"level": profile.level(villain.class_id),
		"progress": MetaProfile.level_progress(total),
		"next_unlock": profile.next_unlock(villain.class_id),
		"unlocked": profile.unlocked(villain.class_id),
		"chronicle": profile.recent(villain.class_id, 5),
		"persistent": profile.path != "",
	}
	if pause_on_end and is_inside_tree():
		get_tree().paused = true
	EventBus.run_ended.emit(villain, summary)

func _title(ending: String) -> String:
	match ending:
		"slain": return "The Necromancer has fallen"
		"throne_fell": return "The Throne has fallen"
		"abandoned": return "The run is abandoned"
		"victory": return "Victory"
	return "The run is over"

## "Run 4 — slain by a Pack wolf on day 2, having raised 3 of the dead and
## cleared a den." ROGUELITE section 9's chronicle line, built from the stats.
func _epitaph(n: int, ending: String, detail: String, day: int) -> String:
	var how: String
	match ending:
		"slain":
			how = "slain by %s on day %d" % [_article(detail), day] if detail != "" else "slain on day %d" % day
		"throne_fell":
			how = "the Throne fell on day %d" % day
		"abandoned":
			how = "abandoned on day %d" % day
		"victory":
			how = "victorious on day %d" % day
		_:
			how = "ended on day %d" % day
	var feats: Array = []
	var deeds: Dictionary = stats["deeds"]
	var raised: int = int(stats["skeletons_raised"])
	if raised > 0:
		feats.append("raised %d of the dead" % raised)
	var dens: int = int(deeds.get("cleared_a_den", 0))
	if dens > 0:
		feats.append("cleared %s" % ("a den" if dens == 1 else "%d dens" % dens))
	var robbed: int = int(deeds.get("rob_the_dead", 0))
	if robbed > 0:
		feats.append("robbed %d %s" % [robbed, "grave" if robbed == 1 else "graves"])
	if feats.size() < 2 and int(stats["sites_looted"]) > 0:
		feats.append("looted %d %s" % [int(stats["sites_looted"]), "site" if int(stats["sites_looted"]) == 1 else "sites"])
	var tail: String = ""
	if feats.is_empty():
		tail = ", having done nothing the world will remember"
	else:
		var two: Array = feats.slice(0, 2)
		tail = ", having " + " and ".join(two)
	return "Run %d — %s%s." % [n, how, tail]

func _article(name: String) -> String:
	if name.begins_with("The ") or name.begins_with("the "):
		return name
	var first: String = name.substr(0, 1).to_lower()
	return ("an " if "aeiou".contains(first) else "a ") + name
