class_name Witnesses
extends Node
## **Seen, and told** (LIVING_WORLD_SPEC section 8.1, ruling 15; L2, built
## 2026-09-26).
##
## A unit that sees the Necromancer do something -- raise the dead, or strike
## down the living -- gets a **!** and becomes a **runner**, headed for the
## nearest settlement (the village's Guardhouse, or the Guild). His standing
## drops **only on arrival**: run the man down before the gate, and nobody hears.
##
## **What a unit can see is its attention range** (ruling 15): longer by day,
## shorter at night, one number per kind of watcher for now
## (`data/guild.json`). The keeper behind the guild's counter sees what happens
## within range of the door, and he is already where the report is going.
##
## Only the first report of each deed lowers standing: three villagers who saw
## the same raising are one report, told three times.
##
## Per villain: holds its villain as a field and ignores deeds by anyone else.

var villain: Necromancer = null
var village = null           # Village
var guild: Guild = null
var day_night: DayNightCycle = null

var _next_act: int = 1
var _reported: Dictionary = {}    # act id -> true
var _keys: Dictionary = {}        # one deed told once, however often it re-starts

func _ready() -> void:
	EventBus.skeleton_raised.connect(_on_raised)
	EventBus.villager_attacked.connect(_on_villager_attacked)

func _is_day() -> bool:
	return day_night == null or day_night.is_day

## Something happened at `at`. Everyone who could see it becomes a runner; the
## keeper, if the door is in range, reports on the spot.
func witness(act: String, at: Vector2, victim = null, key: String = "") -> int:
	if villain == null or guild == null:
		return 0
	if key != "":
		if _keys.has(key):
			return 0
		_keys[key] = true
	var id: int = _next_act
	_next_act += 1
	var seen: int = 0
	var reach: float = guild.attention_px(_is_day())
	if village:
		for v in village.living():
			if v == victim or v.runner_to != Vector2.ZERO or v.is_guard():
				continue
			if v.position.distance_to(at) > reach:
				continue
			v.start_run(_nearest_refuge(v.position), {"villain": villain, "act": act, "id": id})
			seen += 1
			EventBus.witnessed.emit(villain, v, act)
	if guild.position.distance_to(at) <= reach:
		seen += 1
		EventBus.witnessed.emit(villain, guild, act)
		_report(act, id, guild.display_name)
	return seen

## The nearer of the Guildhall and the village's Guardhouse.
func _nearest_refuge(from: Vector2) -> Vector2:
	var best: Vector2 = guild.position if guild else from
	if village and village.buildings.has("guardhouse"):
		var gh: Vector2 = village.buildings["guardhouse"].position
		if guild == null or from.distance_to(gh) < from.distance_to(best):
			best = gh
	return best

func _on_raised(v, unit, _source: String) -> void:
	if v != villain or unit == null:
		return
	witness("raising the dead", unit.position)

## Striking the living. Whoever struck -- him or his escort -- the deed is his.
func _on_villager_attacked(victim, by) -> void:
	if villain == null or by == null:
		return
	if by != villain and not (by is Worker and by.rallied):
		return
	witness("killing %s" % victim.villager_name, victim.position, victim,
		"kill_%d" % victim.get_instance_id())

## A runner got there. First report of a deed counts; the rest are the same news.
func arrive(report: Dictionary, where: String) -> void:
	if report.get("villain") != villain:
		return
	_report(String(report.get("act", "")), int(report.get("id", 0)), where)

func _report(act: String, id: int, where: String) -> void:
	if _reported.has(id):
		return
	_reported[id] = true
	GameState.add_threat(guild.report_threat() if guild else 5)
	villain.lower_standing(Guild.FACTION, "%s — seen %s, told at %s" % [
		"Word reaches the guild", act, where])
