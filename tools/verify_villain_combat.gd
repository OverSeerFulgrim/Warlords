extends Node
## Verifies the villain's own fight against `NECROMANCER_SPEC.md` §10.
##
##   godot --headless --path . res://tools/verify_villain_combat.tscn
##
## A scene, not `-s` (the autoload gotcha: under `-s` this compiles before
## `GameState`, `EventBus` and `LootCatalog` exist).
##
## ## What is actually at risk here
##
## Two things, and neither is arithmetic. **The engage/cast split** is a design
## decision expressed as two different radii doing two different jobs (§3), and
## the failure mode is that they quietly collapse into one — either he starts
## sniping at five cells, or he cannot fight past biting distance. Both would
## still "work". And **the aura's band edge** is now the difference between
## sanctuary and a fair fight, so it is asserted from both sides rather than
## once: inside, nothing targets him and closing opens nothing; one step out,
## both are live.
##
## The 1,000-fight bands are the sidearm's balance (§1.2's "costly win"), and
## they are asserted as *bands* because a point estimate would fail on noise and
## teach everyone to ignore the harness.

const FIGHTS: int = 1000
const CELL: float = 64.0

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(10):
		await get_tree().process_frame

	seed(20260831)
	print("\n=== The villain's own fight (NECROMANCER_SPEC §10) ===\n")
	_the_contract_is_unchanged()
	_the_aura_is_a_place()
	await _engage_close()
	await _cast_far_and_disengage()
	await _retaliation_needs_no_input()
	_kiting_is_bounded()
	await _regen()
	_death_clears_before_anything_else_reads()
	_the_breadcrumb()
	_one_wolf_is_a_costly_win()
	_a_pack_is_not_soloable()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- The contract this slice only uses ---------------------------

## §9: `Combat.gd` and `Engagement.gd` are unchanged by this spec — C2 already
## widened the contract and this slice only reads it. Asserted, because "we did
## not have to touch the formula" is the claim that makes this a policy pass.
func _the_contract_is_unchanged() -> void:
	print("-- He fights through C2's contract, not a villain formula --")
	var v: Necromancer = _main.villain
	_check("he is Arcane by rule, not by special case",
		String(v.combat_profile()["profile"]) == Combat.PROFILE_ARCANE)
	_check("...because Intelligence 7 is his highest of Str/Dex/Int",
		v.attribute("intelligence") == 7
		and v.attribute("intelligence") > v.attribute("strength")
		and v.attribute("intelligence") > v.attribute("dexterity"))
	_check("...and Arcane defends with Intelligence -- Int vs Int",
		String(v.combat_profile()["defence_key"]) == "intelligence")
	_check("his reach is FIVE CELLS, off the profile table",
		is_equal_approx(float(v.combat_profile()["reach_px"]), Combat.REACH_RANGED_CELLS * CELL),
		"%.0f px" % float(v.combat_profile()["reach_px"]))
	_check("the engage radius is the wolf's, not a second number",
		is_equal_approx(CombatSystem.VILLAIN_ENGAGE_PX, Wolf.ENGAGE_RADIUS_PX))
	_check("...and it is much shorter than his reach -- the split is real",
		CombatSystem.VILLAIN_ENGAGE_PX < float(v.combat_profile()["reach_px"]) * 0.25)
	_check("End 6 still gives the 20 hp every R1 number was tuned against",
		v.max_hp() == 20, "%d" % v.max_hp())
	_check("the lair aura flag is GONE, not merely false (§8)",
		not ("LAIR_AURA_PROTECTS_VILLAIN" in CombatSystem))

# ---------------- §5: the aura, from both sides -------------------------------

## The band edge, asserted from both sides — which is the only way to assert a
## rule whose whole content is "here but not there".
func _the_aura_is_a_place() -> void:
	print("-- The aura is a place, not a flag (§5) --")
	var combat: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	var world: WorldMap = _main.world_map

	var inside: Vector2i = world.lair_band.position + world.lair_band.size / 2
	v.place_at(world.cell_centre_px(inside))
	_check("standing in the middle of his band, he is home", v.is_in_lair_band())
	_check("...so the aura holds", combat.aura_protects_villain())
	_check("...and he is not on the menu", not _prey_includes_villain(combat, v))

	# One step past the edge. Same villain, same frame, opposite answers.
	var outside := Vector2i(world.lair_band.position.x + world.lair_band.size.x + 1,
		world.lair_band.position.y + world.lair_band.size.y / 2)
	v.place_at(world.cell_centre_px(outside))
	_check("one cell past the edge, he is not", not v.is_in_lair_band())
	_check("...the aura is gone", not combat.aura_protects_villain())
	_check("...and he is prey like anyone else (§4)", _prey_includes_villain(combat, v))

	# The wolf's panel must tell the truth about which side he is on, because a
	# panel still promising protection out here would be an expensive lie.
	var wolf := Wolf.new()
	add_child(wolf)
	wolf.setup(Vector2.ZERO, Rect2(), Vector2.ZERO, world, v)
	_check("the wolf's panel says the protection has lapsed",
		_promise_line(wolf).findn("nothing keeps it off") >= 0, _promise_line(wolf))
	v.place_at(world.cell_centre_px(inside))
	_check("...and says it holds once he is home again",
		_promise_line(wolf).findn("his own valley") >= 0, _promise_line(wolf))
	wolf.queue_free()

func _prey_includes_villain(combat: CombatSystem, v: Necromancer) -> bool:
	return combat._prey_candidates().has(v)

func _promise_line(wolf: Wolf) -> String:
	for row in wolf.get_inspect_data().get("details", []):
		var text: String = String(row.get("value", ""))
		if text.findn("Necromancer") >= 0:
			return text
	return ""

# ---------------- §3: engage close --------------------------------------------

## Walking in is attacking — and standing at five cells is not. The second half
## is the one worth testing: it is the difference between this design and a
## 5-cell auto-engage, and nothing about the game would look broken if it broke.
func _engage_close() -> void:
	print("-- Engage close: 26px opens a fight, five cells does not (§3) --")
	var combat: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	var wolf: Wolf = _lone_wolf(Vector2(4000, 4000))

	# Just inside his reach but far outside biting distance.
	v.place_at(wolf.position + Vector2(CELL * 4.0, 0.0))
	for i in range(6):
		combat._process(0.1)
	_check("at four cells he starts nothing -- he never auto-seeks",
		not combat.villain_is_engaged())
	_check("...and the wolf has not been handed a fight either", not combat.is_fighting())

	# Walk in. Twenty-five pixels: inside 26, and unambiguously "touching".
	var engaged: Array = []
	var conn := func(_v, foe: String): engaged.append(foe)
	EventBus.villain_engaged.connect(conn)
	v.place_at(wolf.position + Vector2(25.0, 0.0))
	combat._process(0.1)
	EventBus.villain_engaged.disconnect(conn)
	_check("walking to within 26px opens one", combat.villain_is_engaged())
	_check("...and announces it", engaged.size() == 1, str(engaged))
	_check("...against the wolf he walked up to",
		combat.villain_foe_name() == wolf.combat_name(), combat.villain_foe_name())
	# §9: no in_combat on him, ever. Rooting him is the one thing forbidden.
	_check("he is NOT rooted -- no in_combat state on him", not ("in_combat" in v))
	_check("...and the panel can still say who he is fighting",
		v.activity_label().findn("Fighting") >= 0, v.activity_label())

	# And the exchange really lands, both ways, through the ordinary Engagement.
	var hp_before: int = v.hp
	var wolf_hp: int = wolf.hp
	for i in range(int(Combat.EXCHANGE_INTERVAL / 0.1) + 4):
		combat._process(0.1)
		await get_tree().process_frame
	_check("the exchange lands on the wolf", wolf.hp < wolf_hp, "%d -> %d" % [wolf_hp, wolf.hp])
	_check("...and on him -- both swings land", v.hp < hp_before, "%d -> %d" % [hp_before, v.hp])
	_cleanup(wolf)

# ---------------- §3: cast far, and walking out -------------------------------

func _cast_far_and_disengage() -> void:
	print("-- Cast far, and walking out is disengaging (§3) --")
	var combat: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	var wolf: Wolf = _lone_wolf(Vector2(4600, 4000))
	# The wolf must not close the distance while we measure reach, so it is held
	# in its post-spawn prowl (may_hunt() is false until the delay elapses).
	v.place_at(wolf.position + Vector2(25.0, 0.0))
	combat._process(0.1)
	_check("engaged at biting distance", combat.villain_is_engaged())

	# Step back to four cells: inside his five-cell reach, far outside melee.
	v.place_at(wolf.position + Vector2(CELL * 4.0, 0.0))
	combat._process(0.1)
	_check("he keeps casting from four cells -- the escort's whole point",
		combat.villain_is_engaged())
	var wolf_hp: int = wolf.hp
	for i in range(int(Combat.EXCHANGE_INTERVAL / 0.1) + 4):
		combat._process(0.1)
		await get_tree().process_frame
	_check("...and the damage lands from there", wolf.hp < wolf_hp,
		"%d -> %d" % [wolf_hp, wolf.hp])

	# Past five cells: the swings stop.
	var left: Array = []
	var conn := func(_v, foe: String, reason: String): left.append(reason)
	EventBus.villain_disengaged.connect(conn)
	v.place_at(wolf.position + Vector2(CELL * 6.0, 0.0))
	combat._process(0.1)
	EventBus.villain_disengaged.disconnect(conn)
	_check("walking past five cells ends it", not combat.villain_is_engaged())
	_check("...and says why", left.size() == 1 and String(left[0]).findn("reach") >= 0, str(left))
	wolf_hp = wolf.hp
	for i in range(int(Combat.EXCHANGE_INTERVAL / 0.1) + 4):
		combat._process(0.1)
		await get_tree().process_frame
	_check("...and no further exchange lands on the wolf", wolf.hp == wolf_hp)
	_cleanup(wolf)

# ---------------- §4: retaliation ---------------------------------------------

func _retaliation_needs_no_input() -> void:
	print("-- Anything that hits him is engaged back, no input (§4) --")
	var combat: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	var wolf: Wolf = _lone_wolf(Vector2(5200, 4000))
	# He is at four cells: too far to have started anything himself, which is
	# what makes this retaliation rather than a fight he walked into.
	v.place_at(wolf.position + Vector2(CELL * 4.0, 0.0))
	combat._process(0.1)
	_check("he started nothing at four cells", not combat.villain_is_engaged())

	# The wolf attacks him, exactly as its own policy would.
	combat.engage(wolf, v)
	_check("being attacked puts him in the fight with no input", combat.villain_is_engaged())
	var wolf_hp: int = wolf.hp
	for i in range(int(Combat.EXCHANGE_INTERVAL / 0.1) + 4):
		combat._process(0.1)
	_check("...and he answers, from range", wolf.hp < wolf_hp, "%d -> %d" % [wolf_hp, wolf.hp])
	_cleanup(wolf)

# ---------------- §3: kiting is bounded ---------------------------------------

## The sidearm's whole balance, and it is arithmetic rather than behaviour.
##
## **The load-bearing rule is that the wolf is faster than he is.** That is what
## "it *will* catch him" means, and it is what makes kiting bounded by his hit
## points rather than by his legs: on flat ground he can never open the gap, so
## retreating is a delaying tactic and never an escape.
##
## ## A discrepancy worth recording, not papering over
##
## §10 asks for "at most 2-3 exchanges before the wolf closes". **That figure
## does not follow from any of the numbers the spec itself states.** Closing the
## full reach gap (5 cells down to biting distance, 294px) at the difference
## between the two speeds takes 15.3s, which is ten exchange intervals — and
## even using §3's own quoted "78px/s against his 64" it would be fourteen, not
## three.
##
## Both speeds are correct and deliberate: his 1.0 cells/sec is R1's tuned
## travel value (TERRAIN_SPEC §9 — explicitly not a knob) and the wolf's 1.3 is
## what COMBAT_SPEC §7 asks for by name. So the constants are right and the
## prose is wrong, and the honest thing is to assert the derived truth and hand
## the designer the arithmetic rather than quietly weaken the check or bend a
## tuned number to fit a sentence.
##
## Asserted as a pinned band around the shipped figure, so any drift in his
## Speed, the wolf's chase, his reach or the exchange interval trips it.
func _kiting_is_bounded() -> void:
	print("-- Kiting is real but bounded (§3) --")
	var v: Necromancer = _main.villain
	var wolf := Wolf.new()
	add_child(wolf)
	var chase: float = wolf.chase_speed_px()
	var flee: float = v.move_speed_px()
	_check("the wolf is faster than he is -- it WILL catch him", chase > flee,
		"%.0f vs %.0f px/s" % [chase, flee])
	_check("...so retreating can never open the gap: kiting delays, never escapes",
		chase - flee > 0.0 and flee / chase < 1.0,
		"%.0f vs %.0f px/s" % [flee, chase])

	# Flat ground, he runs from the edge of his reach, the wolf closes the gap.
	# How many exchange intervals fit into that closing time is how many casts
	# range is worth.
	var gap: float = float(v.combat_profile()["reach_px"]) - Wolf.ENGAGE_RADIUS_PX
	var seconds: float = gap / (chase - flee)
	var casts: int = int(floor(seconds / Combat.EXCHANGE_INTERVAL))
	print("    a full-reach retreat buys %.1fs = %d exchanges before it closes" % [seconds, casts])
	print("    NOTE: §10 says 2-3. The shipped speeds give %d; see this function's header." % casts)
	_check("a retreat buys a bounded number of casts, not immunity",
		casts >= 8 and casts <= 12, "%d -- Speed, chase, reach or the interval has moved" % casts)
	wolf.queue_free()

# ---------------- Amendment ruling 1: regen ------------------------------------

func _regen() -> void:
	print("-- Out-of-combat regen: a trickle afield, strong at home (amendment 1) --")
	var combat: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	var world: WorldMap = _main.world_map
	var outside := Vector2i(world.lair_band.position.x + world.lair_band.size.x + 3,
		world.lair_band.position.y + world.lair_band.size.y / 2)
	var inside: Vector2i = world.lair_band.position + world.lair_band.size / 2

	# Afield.
	v.place_at(world.cell_centre_px(outside))
	v.hp = 10
	combat._tick_villain_regen(CombatSystem.VILLAIN_REGEN_FIELD_SECONDS * 0.5)
	_check("half a field interval heals nothing yet", v.hp == 10, "%d" % v.hp)
	combat._tick_villain_regen(CombatSystem.VILLAIN_REGEN_FIELD_SECONDS * 0.6)
	_check("a full field interval heals exactly one", v.hp == 11, "%d" % v.hp)

	# The constraint that sets the rate: waiting must cost daylight.
	var to_full: float = float(v.max_hp() - 10) * CombatSystem.VILLAIN_REGEN_FIELD_SECONDS
	print("    healing 10 hp afield costs %.0fs of a %.0fs day"
		% [to_full, DayNightCycle.DAY_SECONDS])
	_check("a den fight cannot be reset by circling the clearing",
		to_full > 120.0, "%.0fs" % to_full)

	# At home, the same test flips the rate.
	v.place_at(world.cell_centre_px(inside))
	v.hp = 10
	combat._regen_timer = 0.0
	var lair_seconds: float = CombatSystem.VILLAIN_REGEN_FIELD_SECONDS \
		/ CombatSystem.VILLAIN_REGEN_LAIR_MULTIPLIER
	combat._tick_villain_regen(lair_seconds * 1.05)
	_check("crossing into the band multiplies it", v.hp == 11, "%d" % v.hp)
	_check("...and it is the SAME position test the aura uses",
		v.is_in_lair_band() and combat.aura_protects_villain())

	# Suppressed entirely while engaged.
	var wolf: Wolf = _lone_wolf(Vector2(5800, 4000))
	v.place_at(wolf.position + Vector2(25.0, 0.0))
	combat._process(0.1)
	_check("he is fighting", combat.villain_is_engaged())
	v.hp = 10
	combat._regen_timer = 0.0
	combat._tick_villain_regen(CombatSystem.VILLAIN_REGEN_FIELD_SECONDS * 3.0)
	_check("regen is STOPPED while engaged, not merely slowed", v.hp == 10, "%d" % v.hp)
	_cleanup(wolf)
	v.heal_full()

# ---------------- §6: his zero -------------------------------------------------

## SORTIE_SPEC §6 requires the haul cleared "before anything else reads them".
## That is an ordering claim, so it is tested by *reading it from a later
## handler* rather than by inspecting the aftermath.
func _death_clears_before_anything_else_reads() -> void:
	print("-- His zero: the haul is gone before anyone can read it (§6) --")
	var v: Necromancer = _main.villain
	var world: WorldMap = _main.world_map
	v.place_at(world.cell_centre_px(Vector2i(70, 70)))
	v.heal_full()
	v.carried.clear()
	v.add_carried("gold", 4)
	v.add_relic("grave_coins")
	_check("he is carrying something worth losing",
		v.carried_total() == 5, "%d" % v.carried_total())

	# Connected now, so it runs AFTER CombatSystem's (connected at _ready).
	var seen: Array = []
	var conn := func(who, _cause: String):
		seen.append({"carried": who.carried.duplicate(), "relics": who.relics_carried.size()})
	EventBus.villain_died.connect(conn)
	v.take_damage(v.max_hp() * 2)
	EventBus.villain_died.disconnect(conn)

	_check("villain_died fired", seen.size() == 1)
	if seen.is_empty():
		return
	_check("...and by the time a later handler looks, the haul is already gone",
		Dictionary(seen[0]["carried"]).is_empty() and int(seen[0]["relics"]) == 0,
		str(seen[0]))
	_check("he respawns at full hp", v.hp == v.max_hp(), "%d" % v.hp)
	var throne: Building = _main.settlement.get_main_building()
	if throne:
		var half: float = CELL * 0.5
		var at := Vector2(throne.cell.x * CELL + half, throne.cell.y * CELL + half)
		_check("...at the Throne", v.position.distance_to(at) < 1.0,
			"%.0f px away" % v.position.distance_to(at))
	_check("...and he is not still in a fight", not _main.combat_system.villain_is_engaged())

# ---------------- 4c: the breadcrumb ------------------------------------------

func _the_breadcrumb() -> void:
	print("-- The dusk line points at a den (designer ruling 2026-08-30) --")
	var combat: CombatSystem = _main.combat_system
	var sites: WorldSites = _main.world_sites
	_check("there is a den to point at", sites.nearest_uncleared_den(Vector2.ZERO) != null)

	var lines: Array = []
	var conn := func(text: String, _s: float): lines.append(text)
	EventBus.travel_noted.connect(conn)
	combat._note_where_they_come_from()
	EventBus.travel_noted.disconnect(conn)
	_check("the dusk handler says where they come from", lines.size() == 1, str(lines))
	if not lines.is_empty():
		var line: String = String(lines[0])
		print("    %s" % line)
		_check("...in plain words, not coordinates",
			line.findn("woods") >= 0 and line.find("(") < 0, line)

	# The compass itself, from a known bearing rather than from whatever the map
	# happens to hold: +x is east, +y is south on screen.
	_check("east reads as east",
		combat._compass_phrase(Vector2.ZERO, Vector2(100, 0)).findn("eastern") >= 0)
	_check("south reads as south",
		combat._compass_phrase(Vector2.ZERO, Vector2(0, 100)).findn("south woods") >= 0)
	_check("north reads as north",
		combat._compass_phrase(Vector2.ZERO, Vector2(0, -100)).findn("north woods") >= 0)
	_check("west reads as west",
		combat._compass_phrase(Vector2.ZERO, Vector2(-100, 0)).findn("western") >= 0)

	# Silent when the last den falls: the quiet is the reward.
	var guardians: Array = []
	for den in sites.dens():
		guardians.append_array(den.guardians.duplicate())
	for g in guardians:
		sites.remove_guardian(g, _main.villain)
	lines.clear()
	var conn2 := func(text: String, _s: float): lines.append(text)
	EventBus.travel_noted.connect(conn2)
	combat._note_where_they_come_from()
	EventBus.travel_noted.disconnect(conn2)
	_check("with every den cleared it says nothing at all", lines.is_empty(), str(lines))

# ---------------- §10: the win-rate bands --------------------------------------

## Simulated with `Combat.exchange()` directly -- the same call `Engagement`
## makes, without the frame clock, because 1,000 fights at 1.5s an exchange is
## not something to run in real time. The arithmetic under test is the formula's,
## and this is the formula.
func _one_wolf_is_a_costly_win() -> void:
	print("-- Int 7 vs one wolf: a costly win (§1.2, §10) --")
	var wins: int = 0
	var hp_left: float = 0.0
	for i in range(FIGHTS):
		var r: Dictionary = _simulate(1)
		if bool(r["won"]):
			wins += 1
			hp_left += float(r["hp"])
	var rate: float = float(wins) / float(FIGHTS)
	var avg: float = hp_left / maxf(1.0, float(wins))
	print("    won %.1f%% of %d, averaging %.1f of 20 hp left" % [rate * 100.0, FIGHTS, avg])
	_check("he wins the large majority", rate >= 0.80, "%.1f%%" % (rate * 100.0))
	_check("...but it COSTS him -- not a walkover", avg <= 15.0, "%.1f hp left" % avg)
	_check("...and he is not untouchable", avg < 20.0, "%.1f" % avg)

func _a_pack_is_not_soloable() -> void:
	print("-- Alone against a three-wolf den pack: no (§10) --")
	var wins: int = 0
	for i in range(FIGHTS):
		if bool(_simulate(3)["won"]):
			wins += 1
	var rate: float = float(wins) / float(FIGHTS)
	print("    won %.1f%% of %d" % [rate * 100.0, FIGHTS])
	_check("he loses or flees the large majority -- the den needs an escort",
		rate <= 0.20, "%.1f%%" % (rate * 100.0))

## One fight to a conclusion. `Engagement` gives the lone attacker one exchange
## per defender per tick; here the villain is the lone defender against `count`
## wolves, so he takes `count` exchanges per interval and deals one back to each
## in turn -- which is the same shape, from the other side.
##
## "Won" means every wolf is dead or fled while he is above his flee fraction:
## a villain at 3 hp who technically cleared the clearing has not won anything
## the design cares about.
func _simulate(count: int) -> Dictionary:
	var v := Necromancer.new()
	var pack: Array = []
	for i in range(count):
		pack.append(Wolf.new())
	var guard: int = 0
	while v.is_alive() and guard < 500:
		guard += 1
		var standing: Array = pack.filter(func(w): return w.is_alive() and not w.should_flee())
		if standing.is_empty():
			break
		# He answers the nearest one; they all bite.
		Combat.exchange(standing[0], v)
		for w in standing.slice(1):
			v.take_damage(Combat.damage_roll(w.combat_profile()["attack_attr"],
				v.combat_defence(w.combat_profile()["defence_key"])))
		if v.hp_fraction() < Combat.FLEE_HP_FRACTION:
			break   # the player would run, and the design says the player decides
	var cleared: bool = true
	for w in pack:
		if w.is_alive() and not w.should_flee():
			cleared = false
	return {"won": cleared and v.is_alive() and v.hp_fraction() >= Combat.FLEE_HP_FRACTION,
		"hp": v.hp}

# ---------------- Helpers ------------------------------------------------------

## A wolf placed well outside the lair band, past its hunt delay so it is a live
## participant rather than a prowler.
func _lone_wolf(at: Vector2) -> Wolf:
	var combat: CombatSystem = _main.combat_system
	var wolf: Wolf = combat.spawn_wolf(at)
	wolf._hunt_delay_left = 0.0
	return wolf

func _cleanup(wolf: Wolf) -> void:
	var combat: CombatSystem = _main.combat_system
	combat._end_engagements_with(wolf)
	combat._end_engagements_with_defender(_main.villain)
	combat.wolves.erase(wolf)
	wolf.queue_free()

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
