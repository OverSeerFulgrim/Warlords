extends Node
class_name MissionSystem
## Gorgon's-Alliance-style hand-picked party missions, distinct from the
## passive Bounty Board. Resolution is an abstracted stat check (see design
## doc Section 5) rather than tactical combat, by design -- keeps this system
## inside the Phase 1 scope budget.

const MISSIONS_PATH := "res://data/missions.json"

var _missions: Array = []

func _ready() -> void:
	_load_missions()

func _load_missions() -> void:
	if not FileAccess.file_exists(MISSIONS_PATH):
		push_warning("MissionSystem: missions.json not found")
		return
	var f := FileAccess.open(MISSIONS_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed != null:
		_missions = parsed

func get_missions() -> Array:
	return _missions

## party: Array[Follower]. Uses the best relevant-stat follower in the party
## as the lead; others contribute a small flat bonus (reflects "having backup"
## without needing full squad simulation).
func dispatch(mission: Dictionary, party: Array) -> void:
	if party.is_empty():
		push_warning("MissionSystem.dispatch: empty party")
		return
	for f in party:
		f.is_busy = true
	EventBus.mission_dispatched.emit(mission, party)
	_resolve(mission, party)

func _resolve(mission: Dictionary, party: Array) -> void:
	# "strength" rather than the retired "might" -- see Follower.mission_check,
	# which resolves any of the nine attributes or twelve skills by name.
	var stat: String = mission.get("relevant_stat", "strength")
	var difficulty: int = mission.get("difficulty", 5)

	var best_check: int = 0
	for f in party:
		best_check = max(best_check, f.mission_check(stat))
	var support_bonus: int = max(0, party.size() - 1)  # backup helps a little
	var total: int = best_check + support_bonus

	var outcome: String
	if total >= difficulty + 3:
		outcome = "SUCCESS"
	elif total >= difficulty:
		outcome = "COMPLICATED"
	else:
		outcome = "FAILURE"

	_apply_outcome(mission, party, outcome)

	for f in party:
		f.is_busy = false

	EventBus.mission_resolved.emit(mission, party, outcome)
	print("[Mission] %s -> %s" % [mission.get("title", "?"), outcome])

func _apply_outcome(mission: Dictionary, party: Array, outcome: String) -> void:
	match outcome:
		"SUCCESS":
			_apply_effects(mission.get("reward", {}))
		"COMPLICATED":
			_apply_effects(mission.get("reward", {}))
			_apply_effects(mission.get("complication_effects", {}))
		"FAILURE":
			var fail_effects: Dictionary = mission.get("failure_effects", {})
			_apply_effects(fail_effects)
			if fail_effects.get("follower_captured", false) and not party.is_empty():
				var lost: Follower = party[randi() % party.size()]
				GameState.remove_follower(lost)
				print("[Mission] %s was captured and lost." % lost.follower_name)

func _apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var value = effects[key]
		match key:
			"dark_essence":
				# **Retired as a source, kept as a sink.** Dark Essence is field
				# loot only (LOOT_SITES_SPEC section 5, ROGUELITE_REWORK section
				# 8): exclusively found out in the world, by the villain, on
				# foot. A mission resolved from a menu at home may still *cost*
				# it -- spending is what it has always lacked -- but it may not
				# print it, and this refuses loudly rather than silently so a
				# re-added grant in missions.json is a warning and not a
				# quietly-broken design rule.
				if value >= 0:
					push_warning("MissionSystem: mission grants %d dark_essence; it is field loot only (LOOT_SITES_SPEC 5). Ignored." % value)
				else:
					GameState.spend_resource("dark_essence", -value)
			"bones":
				GameState.add_resource("bones", value)
			"reputation":
				GameState.add_reputation(value)
			"threat":
				GameState.add_threat(value)
			_:
				pass  # non-numeric flags like follower_captured handled by caller
