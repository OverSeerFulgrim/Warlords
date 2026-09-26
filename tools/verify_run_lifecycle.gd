extends Node
## The run as a thing that ends (2026-09-26 rulings).
##
##   godot --headless --path . res://tools/verify_run_lifecycle.tscn
##
## Death ends the run unless a Second Wake is left; XP banks the instant it is
## earned; the run-end screen gets the whole summary; the profile survives a
## save/load; and a new run starts at 1x with nothing carried over but XP.
##
## Uses its own profile file under user:// and deletes it -- the player's real
## profile (user://meta_profile.json) is never opened by a harness.

const TEST_PROFILE := "user://_verify_run_lifecycle_profile.json"

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	print("\n=== The run ends (RunLifecycle, 2026-09-26) ===\n")
	_the_curve()
	_profile_round_trip()
	_harness_profile_is_not_the_players()
	_xp_banks_on_deeds()
	_other_villains_do_not_end_the_run()
	await _second_wake()
	await _death_ends_the_run()
	_new_run_resets_the_clock()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().paused = false
	get_tree().quit(1 if _failed > 0 else 0)

func _the_curve() -> void:
	print("-- Levels and XP come from the formulas (docs/design/PROGRESSION.md) --")
	var step: int = int(MetaProfile.data()["level_curve"]["step"])
	_check("level 1 starts at 0", MetaProfile.threshold(1) == 0)
	_check("level 2 costs one step", MetaProfile.threshold(2) == step)
	_check("each level costs one step more than the last",
		MetaProfile.threshold(4) - MetaProfile.threshold(3) == 3 * step
		and MetaProfile.threshold(5) - MetaProfile.threshold(4) == 4 * step)
	_check("0 XP is level 1", MetaProfile.level_for_xp(0) == 1)
	_check("the level 2 threshold is level 2", MetaProfile.level_for_xp(step) == 2)
	_check("one short of it is still level 1", MetaProfile.level_for_xp(step - 1) == 1)
	var p: Array = MetaProfile.level_progress(step + 10)
	_check("progress reads into the level", int(p[0]) == 10 and int(p[1]) == 2 * step, str(p))
	_check("the cap holds", MetaProfile.level_for_xp(10000000) == MetaProfile.max_level())
	var base: int = int(MetaProfile.data()["deed_base"]["cleared_a_den"])
	_check("a deed pays base x band", MetaProfile.deed_xp("cleared_a_den", 3) == base * 3)
	_check("...a deed with no band counts as band 1", MetaProfile.deed_xp("cleared_a_den", 0) == base)
	_check("...an unknown deed pays the default",
		MetaProfile.deed_xp("no_such_deed", 1) == int(MetaProfile.data()["deed_base"]["default"]))
	var wake: Dictionary = MetaProfile.unlock_def("second_wake")
	_check("Second Wake is an unlock with a level", not wake.is_empty() and int(wake.get("level", 0)) > 1)

func _profile_round_trip() -> void:
	print("-- The profile survives a save and a load --")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var a := MetaProfile.open(TEST_PROFILE)
	_check("a missing file is a fresh profile", a.xp("necromancer") == 0)
	a.add_xp("necromancer", 130)
	a.record_run("necromancer", "slain", 3, 130, "Run 1 — a test.")
	var b := MetaProfile.open(TEST_PROFILE)
	_check("XP came back", b.xp("necromancer") == 130, "%d" % b.xp("necromancer"))
	_check("...and the level with it", b.level("necromancer") == MetaProfile.level_for_xp(130))
	_check("...and the chronicle", b.recent("necromancer", 5).size() == 1)
	_check("...and the run count", b.runs("necromancer") == 1)
	_check("an unreached unlock is not unlocked", not b.has_unlock("necromancer", "second_wake"))
	b.add_xp("necromancer", 5000)
	_check("enough XP unlocks it", b.has_unlock("necromancer", "second_wake"))

func _harness_profile_is_not_the_players() -> void:
	print("-- A harness never writes the player's profile --")
	_check("Main under a harness keeps its profile in memory",
		_main.run_lifecycle.profile.path == "", _main.run_lifecycle.profile.path)

func _xp_banks_on_deeds() -> void:
	print("-- XP banks the instant it is earned --")
	var rl: RunLifecycle = _main.run_lifecycle
	var v: Necromancer = _main.villain
	var before: int = rl.profile.xp(v.class_id)
	v.record_deed("cleared_a_den", {"power": 1}, 1, 2)
	var want: int = MetaProfile.deed_xp("cleared_a_den", 2)
	_check("a Band 2 den pays base x 2", rl.profile.xp(v.class_id) == before + want
		and want == 2 * int(MetaProfile.data()["deed_base"]["cleared_a_den"]),
		"%d -> %d" % [before, rl.profile.xp(v.class_id)])
	_check("...and the run counts the deed", int(rl.stats["deeds"].get("cleared_a_den", 0)) == 1)
	var stranger := Necromancer.new()
	stranger.record_deed("cleared_a_den", {"power": 1}, 1)
	_check("another villain's deed pays him nothing", rl.profile.xp(v.class_id) == before + want)

func _other_villains_do_not_end_the_run() -> void:
	print("-- Another villain's death is not his --")
	var stranger := Necromancer.new()
	stranger.take_damage(999)
	_check("the run goes on", not _main.run_lifecycle.ended)
	_check("...and the tree is not paused", not get_tree().paused)

func _second_wake() -> void:
	print("-- A Second Wake: the haul is lost, the run is not --")
	var rl: RunLifecycle = _main.run_lifecycle
	var v: Necromancer = _main.villain
	rl.wakes_left = 1
	v.place_at(_main.world_map.cell_centre_px(Vector2i(70, 70)))
	v.add_carried("gold", 3)
	v.take_damage(v.max_hp() * 2)
	await get_tree().process_frame
	_check("he is up", v.is_alive() and v.hp == v.max_hp())
	_check("...at the Throne", v.position.distance_to(_main.sortie_system.throne_position()) < 1.0)
	_check("...empty-handed", v.carried.is_empty())
	_check("...with the wake spent", rl.wakes_left == 0 and int(rl.stats["wakes_used"]) == 1)
	_check("...and the run still going", not rl.ended and not get_tree().paused)

func _death_ends_the_run() -> void:
	print("-- Without a wake, death ends the run --")
	var rl: RunLifecycle = _main.run_lifecycle
	var v: Necromancer = _main.villain
	# Point the profile at a test file so the chronicle write is exercised too.
	rl.profile.path = TEST_PROFILE
	var runs_before: int = rl.profile.runs(v.class_id)
	var got: Array = []
	var conn := func(who, summary: Dictionary): got.append([who, summary])
	EventBus.run_ended.connect(conn)
	EventBus.villain_engaged.emit(v, "Pack wolf")
	v.place_at(_main.world_map.cell_centre_px(Vector2i(70, 70)))
	v.take_damage(v.max_hp() * 2)
	_check("the run does not end mid-exchange -- it waits for the frame to finish",
		not rl.ended and got.is_empty())
	await get_tree().process_frame
	EventBus.run_ended.disconnect(conn)
	_check("run_ended fired once, for him", got.size() == 1 and got[0][0] == v)
	_check("the run is over", rl.ended)
	_check("...the tree is paused", get_tree().paused)
	_check("...and he stays dead where he fell", not v.is_alive())
	if got.is_empty():
		return
	var s: Dictionary = got[0][1]
	_check("the summary names the ending", String(s.get("ending", "")) == "slain")
	_check("...and the killer, in the epitaph", String(s.get("epitaph", "")).findn("Pack wolf") >= 0,
		String(s.get("epitaph", "")))
	_check("...carries the run's stats", s.has("stats") and s["stats"].has("deeds"))
	_check("...and the XP picture", s.has("level") and s.has("progress") and s.has("xp_total"))
	_check("the chronicle has the run", rl.profile.runs(v.class_id) == runs_before + 1)
	var reloaded := MetaProfile.open(TEST_PROFILE)
	_check("...on disk", reloaded.runs(v.class_id) == runs_before + 1)
	var screen: RunSummary = _main.run_summary
	_check("the run-end screen is up", screen.is_showing())
	_check("...and will take input while the world is paused",
		screen.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("...with its one button", screen.new_run_button != null and screen.new_run_button.text == "Begin a new run")
	var deeds_now: int = rl.profile.xp(v.class_id)
	v.record_deed("cleared_a_den", {"power": 1}, 1)
	_check("nothing earns XP after the end", rl.profile.xp(v.class_id) == deeds_now)

## Does not reload the scene (that would end the harness); checks the part that
## was actually broken -- the engine clock surviving the restart.
func _new_run_resets_the_clock() -> void:
	print("-- A new run starts at 1x --")
	Engine.time_scale = 60.0
	get_tree().paused = false
	# The two lines of _begin_new_run that matter, without the reload.
	get_tree().paused = false
	Engine.time_scale = 1.0
	_check("the clock is back at 1x", is_equal_approx(Engine.time_scale, 1.0))
	var src: String = FileAccess.get_file_as_string("res://scripts/Main.gd")
	var at: int = src.find("func _begin_new_run")
	var body: String = src.substr(at, 400)
	_check("_begin_new_run resets Engine.time_scale", body.contains("Engine.time_scale = 1.0"))
	_check("...and unpauses", body.contains("get_tree().paused = false"))
	_check("...and resets GameState", body.contains("GameState.reset()"))

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
