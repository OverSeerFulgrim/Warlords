extends Node
## Raise Dead (ruling C, 2026-09-26) and the R2 close-out fixes from the
## 2026-09-26 review.
##
##   godot --headless --path . res://tools/verify_raise_dead.tscn
##
## Every raise here goes through the path the game uses -- the grave's own
## `_resolve_choice`, and `Main._recruit_worker` for the bones version -- never
## `add_worker` by hand. A hand-added worker is exactly how the escort harness
## passed for a month while a raised corpse stood inert at the graveside.

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
	seed(20260926)
	print("\n=== Raise Dead, and the R2 close-out (2026-09-26) ===\n")
	_no_free_skeleton()
	await _raise_with_bones()
	await _raise_from_a_grave()
	await _raised_joins_an_active_escort()
	await _dismissed_loads_go_home()
	_relics_stay_unique_through_caches()
	_collect_counts_the_escort()
	_timed_recruitment_is_off()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- The opening ------------------------------------------------

func _no_free_skeleton() -> void:
	print("-- No free skeleton at the start (LIVING_WORLD ruling 9) --")
	_check("the roster starts empty", _main.worker_system.workers.is_empty(),
		"%d workers" % _main.worker_system.workers.size())
	_check("...and the starting bones do NOT pay for Raise Dead -- the first dead come from a grave",
		not GameState.can_afford_cost(WorkerSystem.RECRUIT_COST) and GameState.bones == 3,
		"bones=%d" % GameState.bones)

# ---------------- Bones --------------------------------------------------------

func _raise_with_bones() -> void:
	print("-- Raise Dead for bones, at his feet --")
	var v: Necromancer = _main.villain
	var ws: WorkerSystem = _main.worker_system
	v.place_at(_main.world_map.cell_centre_px(Vector2i(40, 64)))
	GameState.bones = 7
	var seen: Array = []
	var conn := func(who, unit, source: String): seen.append([who, unit, source])
	EventBus.skeleton_raised.connect(conn)
	_main._recruit_worker()
	EventBus.skeleton_raised.disconnect(conn)
	_check("one skeleton rose", ws.workers.size() == 1, "%d" % ws.workers.size())
	_check("...and cost 5 bones", GameState.bones == 2, "bones=%d" % GameState.bones)
	if ws.workers.is_empty():
		return
	var w = ws.workers[0]
	_check("...where HE stands, not at the Throne",
		w.position.distance_to(v.position) < float(SettlementGrid.CELL_SIZE),
		"%.0f px away" % w.position.distance_to(v.position))
	_check("...announced as a bones raise, for him",
		seen.size() == 1 and seen[0][0] == v and seen[0][2] == "bones", str(seen))
	_main._recruit_worker()
	_check("with 2 bones left, nothing rises", ws.workers.size() == 1)
	_check("...and nothing is spent", GameState.bones == 2)
	# Put him home and the skeleton to work, out of the way of the tests below.
	w.position = ws.home_position
	GameState.bones = 10

# ---------------- Graves -------------------------------------------------------

func _raise_from_a_grave() -> void:
	print("-- A corpse from a grave: free, real, at the graveside --")
	var v: Necromancer = _main.villain
	var ws: WorkerSystem = _main.worker_system
	var grave: WorldSite = _site("fresh_grave_hollow")
	_check("a fresh grave to raise from", grave != null)
	if grave == null:
		return
	v.place_at(grave.position + Vector2(20, 0))
	var bones_before: int = GameState.bones
	var roster_before: int = ws.workers.size()
	grave._resolve_choice(v, _choice(grave, "raise"))
	_check("a skeleton joined the roster", ws.workers.size() == roster_before + 1,
		"%d -> %d" % [roster_before, ws.workers.size()])
	_check("...for free", GameState.bones == bones_before)
	if ws.workers.size() <= roster_before:
		return
	var risen = ws.workers[ws.workers.size() - 1]
	_check("...at the graveside", risen.position.distance_to(grave.position) < 1.5 * SettlementGrid.CELL_SIZE)
	_check("...in the labour pool, so it walks home to work", ws.laborers().has(risen))
	var before: Vector2 = risen.position
	await _wait(0.6)
	_check("...and it is moving", risen.position.distance_to(before) > 1.0,
		"%.1f px" % risen.position.distance_to(before))

func _raised_joins_an_active_escort() -> void:
	print("-- A raise with the escort up joins it the next frame --")
	var v: Necromancer = _main.villain
	var uc: UndeadCommand = _main.undead_command
	var grave: WorldSite = _site("fresh_grave_scree")
	if grave == null:
		_check("a second grave", false)
		return
	v.place_at(grave.position + Vector2(20, 0))
	uc.cast_escort(v)
	await get_tree().process_frame
	var before: int = v.escort.size()
	grave._resolve_choice(v, _choice(grave, "raise"))
	uc._process(0.1)
	_check("the escort grew by one", v.escort.size() == before + 1, "%d -> %d" % [before, v.escort.size()])

# ---------------- Escort loads -------------------------------------------------

func _dismissed_loads_go_home() -> void:
	print("-- A dismissed escort's load is banked, never relabelled --")
	var v: Necromancer = _main.villain
	var uc: UndeadCommand = _main.undead_command
	var ws: WorkerSystem = _main.worker_system
	if v.escort.is_empty():
		_check("an escort to load", false)
		return
	var member = v.escort[0]
	member.carrying_kind = "gold"
	member.carrying_amount = 3
	var gold_before: int = GameState.gold
	uc.dismiss()
	# Bring it home fast: it walks straight, and the test is about what it does
	# with the load, not how long the walk is.
	member.position = ws.home_position + Vector2(40, 0)
	var waited: float = 0.0
	while int(member.carrying_amount) > 0 and waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check("the gold reached the stockpile", GameState.gold == gold_before + 3,
		"gold %d -> %d, still carrying %d %s" % [gold_before, GameState.gold,
		int(member.carrying_amount), String(member.carrying_kind)])

# ---------------- Relics -------------------------------------------------------

func _relics_stay_unique_through_caches() -> void:
	print("-- A relic left in a cache is still drawn, and can be picked back up --")
	var v := Necromancer.new()
	v.note_relics_rolled(["grave_coins"])
	_check("a rolled relic counts as drawn even when not in hand",
		v.drawn_relic_ids().has("grave_coins"))
	_check("...so the catalog will not roll it again",
		not _rolls_relic(v, "grave_coins"))
	_check("...and he can still pick it up from the cache", v.add_relic("grave_coins"))
	_check("...but not a second time while he holds it", not v.add_relic("grave_coins"))
	v.bank_relics()
	_check("...or once it is banked", not v.add_relic("grave_coins"))

## True if 2,000 rolls of every table ever produce `id` for this villain.
func _rolls_relic(v: Necromancer, id: String) -> bool:
	for t in ["crypt", "valuable_grave", "wolf_den", "small_cache", "abandoned_camp"]:
		for i in range(400):
			var r: Dictionary = LootCatalog.roll(t, v.drawn_relic_ids(), 1.0)
			if r.get("relics", []).has(id):
				return true
	return false

# ---------------- Collect ------------------------------------------------------

func _collect_counts_the_escort() -> void:
	print("-- Collect is offered when his hands are full but the escort has room --")
	var v := Necromancer.new()
	var s1 := Worker.new("Arms A")
	v.escort.append(s1)
	v.add_carried("bones", v.carry_capacity())
	var site: WorldSite = _site("hidden_cache")
	if site == null:
		_check("a cache to leave things in", false)
		return
	site.remainder["gold"] = 2
	var row: Dictionary = {}
	for a in site.actions_for(v):
		if String(a.get("id", "")) == "collect":
			row = a
	_check("his hands are full", v.carry_space() == 0)
	_check("...but Collect is enabled, because the escort has arms",
		bool(row.get("enabled", false)), str(row))
	site.remainder.erase("gold")
	site.relic_remainder.append("grave_coins")
	row = {}
	for a in site.actions_for(v):
		if String(a.get("id", "")) == "collect":
			row = a
	_check("a relic only goes in HIS hands, so a relic-only remainder stays disabled",
		not bool(row.get("enabled", true)), str(row))
	site.relic_remainder.clear()

# ---------------- Recruitment timer ---------------------------------------------

func _timed_recruitment_is_off() -> void:
	print("-- The timed recruit offer is off (ROGUELITE_REWORK section 7) --")
	_check("the switch is off", not EventSystem.TIMED_RECRUIT_OFFERS)
	_check("...so a Barracks would not start the clock", not _main.event_system.events_enabled())

# ---------------- Helpers -------------------------------------------------------

func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _site(id: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.site_id == id:
			return s
	return null

func _choice(site: WorldSite, id: String) -> Dictionary:
	for c in LootCatalog.choice_sheet(site.choices_id).get("choices", []):
		if String(c.get("id", "")) == id:
			return c
	return {}

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
