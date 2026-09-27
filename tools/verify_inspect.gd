extends Node
## **Every inspectable answers when clicked** (2026-09-26, after a playtest froze:
## clicking a den wolf mid-fight hit a script error in its panel, and a script
## error in the editor pauses the game).
##
##   godot --headless --path . res://tools/verify_inspect.tscn
##
## Calls `get_inspect_data()` on everything that implements it -- every node in
## the running Main scene, every worker, villager and the Necromancer -- and
## again on each site guardian in every state and wounded, because the panel
## re-reads its source every frame while it is open. A script error inside the
## call returns null, so "returns a titled Dictionary" is the whole test.

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 800)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(8):
		await get_tree().process_frame
	print("\n=== Every inspectable answers ===\n")
	GameState.bones = 20
	for i in range(3):
		_main._recruit_worker()
	await get_tree().process_frame
	_every_node()
	_data_objects()
	_guardians_in_every_state()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _answers(src) -> bool:
	var d = src.get_inspect_data()
	return d is Dictionary and not (d as Dictionary).is_empty() and (d as Dictionary).has("title")

func _every_node() -> void:
	print("-- Every node in the scene --")
	var by_script: Dictionary = {}   # script path -> [count, failures]
	var stack: Array = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n.has_method("get_inspect_data"):
			continue
		var key: String = n.get_script().resource_path.get_file() if n.get_script() else n.get_class()
		if not by_script.has(key):
			by_script[key] = [0, 0]
		by_script[key][0] += 1
		if not _answers(n):
			by_script[key][1] += 1
	for key in by_script.keys():
		_check("%s answers (%d of them)" % [key, by_script[key][0]], by_script[key][1] == 0,
			"%d failed" % by_script[key][1])
	for need in ["SiteGuardian.gd", "WorldSite.gd", "Guild.gd", "VillageBuilding.gd"]:
		_check("...and the scene has a %s to click" % need, by_script.has(need))

func _data_objects() -> void:
	print("-- The people --")
	_check("the Necromancer answers", _answers(_main.villain))
	var ok: bool = not _main.worker_system.workers.is_empty()
	for w in _main.worker_system.workers:
		ok = ok and _answers(w)
	_check("every one of his dead answers", ok)
	ok = not _main.village.villagers.is_empty()
	for v in _main.village.villagers:
		ok = ok and _answers(v)
	_check("every villager answers", ok)

func _guardians_in_every_state() -> void:
	print("-- Site guardians, in every state and wounded --")
	var guards: Array = []
	for s in _main.world_sites.sites:
		guards.append_array(s.guardians)
	_check("there are guardians to test", not guards.is_empty())
	var target = _main.worker_system.workers[0]
	var ok: bool = true
	for g in guards:
		var hp0: int = g.hp
		var st0: int = g.state
		for st in [SiteGuardian.State.PROWL, SiteGuardian.State.STALK, SiteGuardian.State.FIGHT]:
			g.state = st
			g._target = target
			for hp in [g.max_hp(), maxi(1, g.flee_below_hp + 1), maxi(1, g.flee_below_hp - 1)]:
				g.hp = hp
				ok = ok and _answers(g)
		g.hp = hp0
		g.state = st0
		g._target = null
	_check("every guardian answers in PROWL, STALK and FIGHT at full, wounded and fleeing hp", ok)

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
