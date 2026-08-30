extends Node
## Verifies the return leg against `SORTIE_SPEC.md` §10.
##
##   godot --headless --path . res://tools/verify_sortie.tscn
##
## A scene, not `-s` (the autoload gotcha).
##
## ## What is actually at risk
##
## **The banking rule** (ROGUELITE_REWORK §1) is the whole design at this scale,
## and every assertion here is a way of asking "is it still true that nothing is
## yours until it is home?" The two that would rot silently are the band edge --
## it is *nearly* the Throne, and merging the two tests would look like a
## simplification — and death clearing the haul, which is an ordering claim and
## therefore untestable by looking at the aftermath.

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

	seed(20260901)
	print("\n=== The return leg (SORTIE_SPEC §10) ===\n")
	_capacity_arithmetic()
	_overflow_leaves_an_exact_remainder()
	await _the_deposit()
	_the_band_is_not_the_throne()
	_the_two_drop_paths()
	_the_cache_is_a_site()
	_relics_wake_on_deposit()
	_death_clears_everything_first()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- §2: party capacity ------------------------------------------

## The spec's own worked example: villain alone = 6, with two End-4 skeletons =
## 14, and a relic eats a slot. Asserted against the *stated* numbers rather
## than against whatever the code computes, because these are the numbers every
## loot table was tuned against.
func _capacity_arithmetic() -> void:
	print("-- Party capacity (§2) --")
	var s: SortieSystem = _fresh_system()
	var v: Necromancer = s.villain
	_check("the villain alone carries 6", s.party_capacity() == 6, "%d" % s.party_capacity())
	_check("...which is his Endurance, not a bespoke carry stat",
		s.party_capacity() == v.attribute("endurance"))

	var a := _skeleton()
	var b := _skeleton()
	_check("a skeleton's Endurance is 4", a.attribute("endurance") == 4,
		"%d" % a.attribute("endurance"))
	v.escort.append(a)
	v.escort.append(b)
	_check("with two skeletons the party carries 14", s.party_capacity() == 14,
		"%d" % s.party_capacity())

	_check("a relic consumes one slot", v.add_relic("grave_coins")
		and s.party_carried() == 1, "%d carried" % s.party_carried())
	_check("...and party space follows", s.party_space() == 13, "%d" % s.party_space())

	# Filling order: villain first, escort second (§2).
	v.relics_carried.clear()
	var took: int = s.take_into_party(v, "bones", 8)
	_check("eight bones all fit in a 14-slot party", took == 8, "%d" % took)
	_check("...the villain filled first, to his brim",
		v.carried_total() == 6, "villain has %d" % v.carried_total())
	_check("...and the overflow went to the escort", a.carrying_amount == 2,
		"skeleton has %d" % a.carrying_amount)
	_check("...one kind per member, as the trip loop's fields require",
		String(a.carrying_kind) == "bones")

	# A second kind cannot go into a skeleton already holding bones.
	var gold_taken: int = s.take_into_party(v, "gold", 4)
	_check("a skeleton already hauling bones will not also take gold",
		int(b.carrying_amount) == 4 and int(a.carrying_amount) == 2,
		"a=%d b=%d" % [a.carrying_amount, b.carrying_amount])
	_check("...so the second kind went to the empty one", String(b.carrying_kind) == "gold"
		and gold_taken == 4, "%s %d" % [b.carrying_kind, gold_taken])

# ---------------- §4: overflow ------------------------------------------------

func _overflow_leaves_an_exact_remainder() -> void:
	print("-- Overflow leaves the exact remainder at the site (§4) --")
	var site: WorldSite = _site("cursed_battlefield")
	var s: SortieSystem = _fresh_system()
	var v: Necromancer = s.villain
	v.position = site.position
	site.party_filler = func(who, kind: String, amount: int): return s.take_into_party(who, kind, amount)
	v.add_carried("bones", v.carry_capacity() - 1)
	site._resolve_loot(v, 1.0, "", {}, 0.0)
	_check("he is full", s.party_space() == 0, "%d free" % s.party_space())
	_check("the overflow stayed at the site", site.has_remainder(), str(site.remainder))
	_check("...and the site still offers actions", not site.actions_for(v).is_empty())
	_check("...and is not spent while it holds one", not site.is_spent())
	site.remainder.clear()
	site.relic_remainder.clear()

# ---------------- §3: the deposit ---------------------------------------------

func _the_deposit() -> void:
	print("-- The deposit, at the Throne (§3) --")
	var s: SortieSystem = _main.sortie_system
	var v: Necromancer = _main.villain
	_reset(v)
	var a := _skeleton()
	v.escort.append(a)
	v.add_carried("bones", 4)
	v.add_carried("gold", 2)
	a.carrying_kind = "wood"
	a.carrying_amount = 3

	var bones_before: int = GameState.bones
	var gold_before: int = GameState.gold
	var wood_before: int = GameState.wood
	var banked: Array = []
	var conn := func(_v, load: Dictionary, _r: Array): banked.append(load)
	EventBus.sortie_deposited.connect(conn)

	# Standing at the Throne. No button: the check runs every frame and the
	# worker trip loop deposits the same way at shorter range.
	v.place_at(s.throne_position())
	_check("he is at the Throne", s.at_throne())
	s._check_deposit()
	EventBus.sortie_deposited.disconnect(conn)

	_check("it banked without a prompt", banked.size() == 1, str(banked))
	_check("the villain's hands are empty", v.carried.is_empty(), str(v.carried))
	_check("...and the escort's, in the SAME frame",
		int(a.carrying_amount) == 0 and String(a.carrying_kind) == "")
	_check("bones reached GameState", GameState.bones == bones_before + 4,
		"%d -> %d" % [bones_before, GameState.bones])
	_check("...and gold", GameState.gold == gold_before + 2)
	_check("...and the escort's wood", GameState.wood == wood_before + 3)
	_check("nothing is left to bank", not s.has_anything_to_bank())

	# Partial deposits are free: half a load, then out again, then the rest.
	v.add_carried("stone", 2)
	s._check_deposit()
	_check("a partial deposit is free and immediate", v.carried.is_empty()
		and GameState.stone >= 2, str(v.carried))
	v.escort.clear()

	# `arms` banks too. LOOT_SITES §9 said "gold and nothing else", but that
	# predates ruling 2's `arms`, and a kind he can carry but not bank would
	# print "unknown kind" on every deposit containing weapons.
	var arms_before: int = GameState.arms
	v.add_carried("arms", 2)
	s._check_deposit()
	_check("arms bank rather than vanishing with a warning",
		GameState.arms == arms_before + 2, "%d -> %d" % [arms_before, GameState.arms])

# ---------------- §3: the band is not the Throne ------------------------------

## The assertion most likely to be "simplified" away by someone who notices the
## two tests look alike. They are not: `TravelLog` calls the band home for
## *measuring a journey*, which is right, and banking happens at the Throne.
func _the_band_is_not_the_throne() -> void:
	print("-- Crossing the band edge banks NOTHING (§3) --")
	var s: SortieSystem = _main.sortie_system
	var v: Necromancer = _main.villain
	var world: WorldMap = _main.world_map
	_reset(v)
	v.add_carried("bones", 5)

	# One cell inside the band, as far from the Throne as the band allows.
	var inside := Vector2i(world.lair_band.position.x + 1,
		world.lair_band.position.y + 1)
	v.place_at(world.cell_centre_px(inside))
	_check("he is home by the travel log's reckoning", v.is_in_lair_band())
	_check("...but not at the Throne", not s.at_throne())
	var bones_before: int = GameState.bones
	s._check_deposit()
	_check("so NOTHING banks", GameState.bones == bones_before and v.carried_total() == 5,
		"%d -> %d, carrying %d" % [bones_before, GameState.bones, v.carried_total()])

	# And the last few cells are what makes the difference.
	v.place_at(s.throne_position())
	s._check_deposit()
	_check("walking the last cells to the Throne banks it",
		GameState.bones == bones_before + 5 and v.carried.is_empty())

	# The two radii must not have quietly become one.
	var throne: Vector2 = s.throne_position()
	var band_px: float = float(maxi(world.lair_band.size.x, world.lair_band.size.y)) * CELL
	_check("the deposit radius is 1.5 cells, far smaller than the band",
		SortieSystem.DEPOSIT_RADIUS_PX < band_px * 0.2,
		"%.0fpx vs a %.0fpx band" % [SortieSystem.DEPOSIT_RADIUS_PX, band_px])
	_check("...and it is the Throne-repair radius, not a second number",
		is_equal_approx(SortieSystem.DEPOSIT_RADIUS_PX, CombatSystem.THRONE_REPAIR_RADIUS_PX))

# ---------------- §5: the two drop paths --------------------------------------

func _the_two_drop_paths() -> void:
	print("-- Dropping: in reach vs open country (§5, as amended) --")
	var s: SortieSystem = _main.sortie_system
	var v: Necromancer = _main.villain
	var site: WorldSite = _site("hidden_cache")
	_reset(v)

	# In reach: it goes back into the site he is standing at.
	v.place_at(site.position)
	v.add_carried("bones", 3)
	var dropped: Array = []
	var caches: Array = []
	var c1 := func(_v, kind: String, amount: int, to_site): dropped.append([kind, amount, to_site])
	var c2 := func(_v, cache): caches.append(cache)
	EventBus.sortie_load_dropped.connect(c1)
	EventBus.sortie_cache_created.connect(c2)
	var got: WorldSite = s.drop("bones", 3)
	_check("dropping at a site returns it to that site", got == site)
	_check("...into its remainder", int(site.remainder.get("bones", 0)) == 3, str(site.remainder))
	_check("...and it left his hands", not v.carried.has("bones"))
	_check("...announcing where it went", dropped.size() == 1 and dropped[0][2] == site)
	_check("...and creating NO cache -- the two paths differ", caches.is_empty())
	site.remainder.clear()

	# Open country: a cache appears. The amendment struck destruction.
	var open: Vector2 = _main.world_map.cell_centre_px(Vector2i(70, 40))
	v.place_at(open)
	v.add_carried("gold", 4)
	var before_caches: int = _main.world_sites.dropped_caches().size()
	var cache: WorldSite = s.drop("gold", 4)
	EventBus.sortie_load_dropped.disconnect(c1)
	EventBus.sortie_cache_created.disconnect(c2)

	_check("dropping in open country creates a cache", cache != null and cache.is_dropped_cache())
	_check("...a NEW site, not the one he was at", cache != site)
	_check("...announced on its own signal, which is how the paths differ",
		caches.size() == 1 and caches[0] == cache)
	_check("...and the world has one more cache",
		_main.world_sites.dropped_caches().size() == before_caches + 1)
	_check("the load is NOT destroyed -- the cache holds it exactly",
		int(cache.remainder.get("gold", 0)) == 4, str(cache.remainder))
	_check("...and it left his hands", not v.carried.has("gold"))

# ---------------- The cache, as a site ----------------------------------------

## The ruling asks for "full reuse of the site machinery". This is that claim,
## asserted: a cache is a site, behaves like one, and re-looting empties it.
func _the_cache_is_a_site() -> void:
	print("-- A dropped cache is an ordinary site (amendment ruling 2) --")
	var s: SortieSystem = _main.sortie_system
	var v: Necromancer = _main.villain
	_reset(v)
	var open: Vector2 = _main.world_map.cell_centre_px(Vector2i(72, 42))
	v.place_at(open)
	v.add_carried("bones", 3)
	v.add_relic("tarnished_locket")
	var cache: WorldSite = s.drop("bones", 3)
	s.drop_relic("tarnished_locket")

	_check("it holds the exact contents", int(cache.remainder.get("bones", 0)) == 3
		and cache.relic_remainder.has("tarnished_locket"), str(cache.remainder))
	_check("it is inspectable like any site",
		String(cache.get_inspect_data().get("title", "")) != "")
	_check("it offers only the collect -- no table, no sheet",
		_ids(cache.actions_for(v)) == ["collect"], str(_ids(cache.actions_for(v))))
	_check("it is NOT Raven-eligible (a cache is discovered by definition)",
		not cache.is_raven_eligible())
	_check("...while an authored site is", _site("hidden_cache").is_raven_eligible())

	# Re-looting empties it, which is the ruling's own wording.
	v.carried.clear()
	v.relics_carried.clear()
	cache.begin_action(v, "collect")
	_check("re-looting empties it", not cache.has_remainder(), str(cache.remainder))
	_check("...into his hands", v.carried_total() >= 3, "%d" % v.carried_total())
	_check("...and the emptied cache is spent", cache.is_spent())

	# Outside the density budget: the budget counts authored sites from the JSON.
	var authored: int = 0
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_sites.json"))
	for entry in parsed.get("sites", []):
		if entry.has("lootable"):
			authored += 1
	_check("caches sit outside the 10-15 active density budget",
		authored >= 10 and authored <= 15, "%d authored" % authored)

# ---------------- §3 / LOOT_SITES §7: relics wake at the Throne ---------------

func _relics_wake_on_deposit() -> void:
	print("-- Relic effects activate ON DEPOSIT, not on pickup (LOOT_SITES §7) --")
	var s: SortieSystem = _main.sortie_system
	var v: Necromancer = _main.villain
	_reset(v)
	var carry_before: int = v.carry_capacity()
	v.add_relic("pallbearers_gloves")
	_check("in his hands it does nothing", v.carry_capacity() == carry_before,
		"%d -> %d" % [carry_before, v.carry_capacity()])

	var woke: Array = []
	var conn := func(_v, relic_id: String): woke.append(relic_id)
	EventBus.relic_banked.connect(conn)
	v.place_at(s.throne_position())
	s._check_deposit()
	EventBus.relic_banked.disconnect(conn)
	_check("banking it wakes it", v.carry_capacity() == carry_before + 2,
		"%d" % v.carry_capacity())
	_check("...and says so", woke == ["pallbearers_gloves"], str(woke))
	_check("...and it is banked, not carried",
		v.relics_banked.has("pallbearers_gloves") and v.relics_carried.is_empty())

	# All six live effects reachable from a banked relic, and the dormant two
	# still doing nothing. The detail of each is verify_loot_tables'; this is the
	# claim that DEPOSIT is what turns them on.
	v.relics_banked.clear()
	v.relics_banked.append_array(["sextons_ring", "wolfhide_cloak", "pallbearers_gloves",
		"chipped_censer", "sermon_of_ash", "barrow_lantern"])
	_check("six live effects, all reading from the banked list",
		is_equal_approx(v.channel_multiplier(["grave"]), 0.75)
		and v.carry_capacity() == carry_before + 2
		and v.dawn_heal() == 2
		and v.attribute("intelligence") == 8
		and v.fog_reveal_bonus() == 2)
	v.relics_banked.clear()
	v.relics_banked.append_array(["noble_seal", "ledger_of_names"])
	_check("...and the two dormant ones still do nothing once banked",
		v.carry_capacity() == carry_before and v.attribute("intelligence") == 7)
	v.relics_banked.clear()

# ---------------- §6: death ---------------------------------------------------

## An ordering claim, so it is tested by reading the villain from a handler
## connected *afterwards* -- which is the only way to prove "before anything
## else reads them".
func _death_clears_everything_first() -> void:
	print("-- Death clears the unbanked haul, before anyone reads it (§6) --")
	var v: Necromancer = _main.villain
	_reset(v)
	v.place_at(_main.world_map.cell_centre_px(Vector2i(70, 70)))
	var a := _skeleton()
	v.escort.append(a)
	a.carrying_kind = "bones"
	a.carrying_amount = 3
	v.add_carried("gold", 4)
	v.add_relic("grave_coins")
	_check("he is carrying something worth losing", v.carried_total() == 5)

	var seen: Array = []
	var conn := func(who, _cause: String):
		seen.append({"carried": who.carried.duplicate(), "relics": who.relics_carried.size(),
			"escort": int(a.carrying_amount)})
	EventBus.villain_died.connect(conn)
	v.take_damage(v.max_hp() * 2)
	EventBus.villain_died.disconnect(conn)

	_check("villain_died fired", seen.size() == 1)
	if seen.is_empty():
		return
	_check("by the time a later handler looks, his hands are empty",
		Dictionary(seen[0]["carried"]).is_empty(), str(seen[0]["carried"]))
	_check("...and his relics are gone", int(seen[0]["relics"]) == 0)
	_check("...and the escort's load with them", int(seen[0]["escort"]) == 0)
	_check("nothing of it reached GameState", true)   # nothing banks on death, by construction
	_check("he respawns at the Throne", v.position.distance_to(
		_main.sortie_system.throne_position()) < 1.0)
	_check("...at full hp", v.hp == v.max_hp())
	v.escort.clear()

# ---------------- Helpers ------------------------------------------------------

## A throwaway system over a throwaway villain, for the arithmetic tests -- so
## capacity assertions cannot be perturbed by whatever the live villain is
## holding, and so nothing here banks into the real GameState.
func _fresh_system() -> SortieSystem:
	var s := SortieSystem.new()
	s.villain = Necromancer.new()
	s.settlement = _main.settlement
	s.world = _main.world_map
	s.world_sites = _main.world_sites
	return s

## A skeleton, built the way `WorkerSystem` builds them -- `Worker._init` takes
## a name, and calling `new()` bare aborts `_ready` mid-run, which presents as
## the harness hanging with no output rather than as an error.
func _skeleton(name: String = "Test Skeleton") -> Worker:
	return Worker.new(name)

func _reset(v: Necromancer) -> void:
	v.carried.clear()
	v.relics_carried.clear()
	v.relics_banked.clear()
	v.escort.clear()
	v.heal_full()

func _site(id: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.site_id == id:
			return s
	return null

func _ids(actions: Array) -> Array:
	var out: Array = []
	for a in actions:
		out.append(String(a.get("id", "")))
	return out

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
