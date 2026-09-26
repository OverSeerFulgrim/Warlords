extends Node
## The bird that never lies -- `RAVEN_SPEC.md` section 9.
##
##   godot --headless --path . res://tools/verify_raven.tscn
##
## The honesty invariant is asserted as five separate counts over a thousand
## dawns in which every lootable site is made a candidate by flag and then
## scrambled -- discovered or not, guarded or not, charged or not -- so the
## filter is what keeps each ping honest, never the data happening to be tidy.

const DAWNS: int = 1000

var _passed: int = 0
var _failed: int = 0
var _main = null
var _raven: Raven = null
var _sites: WorldSites = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	_raven = _main.raven
	_sites = _main.world_sites
	_raven.rng.seed = 20260926
	seed(20260926)
	print("\n=== The Raven (RAVEN_SPEC section 9) ===\n")
	_wiring()
	_discovery()
	_the_invariant_five_ways()
	_camp_occupancy()
	_the_cap()
	_silence_is_delivered()
	_cadence()
	_fog_is_untouched()
	_claiming_clears_the_mark()
	await _the_chip_drops_follow()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Setup and wiring -------------------------------------------

func _wiring() -> void:
	print("-- Per villain, and listening to the dawn --")
	_check("the Raven exists and holds its villain", _raven != null and _raven.villain == _main.villain)
	_check("...and its sites and fog as fields", _raven.world_sites == _sites and _raven.fog == _main.fog)
	_check("it is subscribed to dawn", EventBus.dawn_started.is_connected(_raven._on_dawn))
	var flagged: Array = _sites.lootable_sites().filter(func(s): return s.raven_eligible)
	var ids: Array = flagged.map(func(s): return s.site_id)
	_check("the authored pool is the minor sites (section 2)",
		ids.has("fresh_grave_hollow") and ids.has("hidden_cache") and ids.has("abandoned_camp")
		and flagged.all(func(s): return s.band <= 2), str(ids))
	_check("no dropped cache is ever eligible", not _sites.lootable_sites().any(
		func(s): return s.is_dropped_cache() and s.is_raven_eligible()))

func _discovery() -> void:
	print("-- Found means somebody of his stood where he could see it --")
	var site: WorldSite = _site("hidden_cache")
	var was: bool = site.discovered
	site.discovered = false
	var far: Array = _sites.update_discovery([[site.position + Vector2(64.0 * 20, 0), 7.0]])
	_check("a source twenty cells off finds nothing", not site.discovered and not far.has(site))
	var near: Array = _sites.update_discovery([[site.position + Vector2(64.0 * 5, 0), 7.0]])
	_check("a source inside its radius finds it", site.discovered and near.has(site))
	site.discovered = was

# ---------------- Section 4, five ways ---------------------------------------

func _the_invariant_five_ways() -> void:
	print("-- The honesty invariant, over %d dawns with everything scrambled --" % DAWNS)
	var saved: Array = _save_state()
	var sites: Array = _sites.lootable_sites().filter(func(s): return not s.is_dropped_cache())
	for s in sites:
		s.raven_eligible = true   # every site a candidate by flag; the invariant must do the filtering
	var bad := {"reachable": 0, "minor_band": 0, "unguarded": 0, "undiscovered": 0, "has_charge": 0}
	var pings: int = 0
	var band34_candidates: int = 0
	for i in range(DAWNS):
		_clear_pings()
		for s in sites:
			s.discovered = randf() < 0.5
			s.charges_left = randi_range(0, maxi(1, s.charges_max))
			s.cleared = randf() < 0.7
			if s.band >= 3:
				band34_candidates += 1
		var got = _raven.dawn(i + 1)
		if got == null:
			continue
		pings += 1
		var c: Dictionary = _sites.raven_checks(got)
		for k in bad.keys():
			if not c[k]:
				bad[k] += 1
	_check("pings happened, so this proved something (%d)" % pings, pings > 100)
	_check("...and Band 3-4 sites were on offer by flag the whole time", band34_candidates > 0)
	_check("never an unreachable site", bad["reachable"] == 0, str(bad))
	_check("never Band 3 or 4", bad["minor_band"] == 0, str(bad))
	_check("never guarded or occupied", bad["unguarded"] == 0, str(bad))
	_check("never a site he has already found", bad["undiscovered"] == 0, str(bad))
	_check("never a site with nothing left in it", bad["has_charge"] == 0, str(bad))
	_restore_state(saved)
	_clear_pings()

func _camp_occupancy() -> void:
	print("-- The camp: occupancy rolled at activation, and the bird knows --")
	var camp: WorldSite = _site("abandoned_camp")
	_check("the camp has an authored occupancy", not camp.occupancy.is_empty(), str(camp.occupancy))
	var chance: float = float(camp.occupancy.get("chance", 0.0))
	var probe := WorldSite.new()
	var block: Dictionary = _block_for("abandoned_camp")
	var hits: int = 0
	for i in range(2000):
		probe._setup_lootable(block)
		if probe.occupied:
			hits += 1
			if probe.guardian_spec.is_empty() or probe.cleared:
				_check("an occupied roll posts guardians", false, str(probe.guardian_spec))
				break
	probe.free()
	var rate: float = float(hits) / 2000.0
	_check("occupancy rolls near its chance (%.1f%% vs %.0f%%)" % [rate * 100.0, chance * 100.0],
		absf(rate - chance) < 0.04)

	var saved: Array = _save_state()
	for s in _sites.lootable_sites():
		s.discovered = true   # only the camp is left to find
	camp.discovered = false
	camp.charges_left = maxi(1, camp.charges_max)
	camp.cleared = false      # occupied
	var named: bool = false
	for i in range(300):
		_clear_pings()
		if _raven.dawn(i + 1) == camp:
			named = true
	_check("an occupied camp is never pinged", not named)
	camp.cleared = true       # empty
	_check("an empty one is eligible", _sites.undiscovered_eligible().has(camp))
	_restore_state(saved)
	_clear_pings()

# ---------------- Section 3 ---------------------------------------------------

func _the_cap() -> void:
	print("-- The cap: three outstanding, and then nothing until one is claimed --")
	var saved: Array = _save_state()
	_open_the_pool()
	for i in range(200):
		_raven.dawn(i + 1)
		if _raven.outstanding() >= Raven.MAX_OUTSTANDING_PINGS:
			break
	_check("it fills to the cap", _raven.outstanding() == Raven.MAX_OUTSTANDING_PINGS, "%d" % _raven.outstanding())
	var fourth: bool = false
	for i in range(200):
		if _raven.dawn(300 + i) != null:
			fourth = true
	_check("no fourth ping while three are outstanding", not fourth and _raven.outstanding() == 3)
	var first = _raven.pings[0]["site"]
	EventBus.site_looted.emit(_main.villain, first, {})
	_check("claiming one opens a slot", _raven.outstanding() == 2)
	_restore_state(saved)
	_clear_pings()

func _silence_is_delivered() -> void:
	print("-- A silent day is delivered, never invented over --")
	var saved: Array = _save_state()
	for s in _sites.lootable_sites():
		s.discovered = true
	var silent := [0]
	var conn := func(_v, _d: int): silent[0] += 1
	EventBus.raven_silent.connect(conn)
	var pinged: bool = false
	for i in range(100):
		if _raven.dawn(i + 1) != null:
			pinged = true
	EventBus.raven_silent.disconnect(conn)
	_check("with nothing honest to name, nothing is named", not pinged and _raven.outstanding() == 0)
	_check("...and raven_silent fires instead", silent[0] > 0, "%d" % silent[0])
	_restore_state(saved)
	_clear_pings()

func _cadence() -> void:
	print("-- Cadence: about 70% of dawns, with news to give --")
	var saved: Array = _save_state()
	_open_the_pool()
	var hits: int = 0
	for i in range(DAWNS):
		_clear_pings()
		if _raven.dawn(i + 1) != null:
			hits += 1
	var rate: float = float(hits) / float(DAWNS)
	_check("near %d%% (%.1f%%)" % [Raven.RAVEN_PING_CHANCE_PERCENT, rate * 100.0],
		absf(rate - Raven.RAVEN_PING_CHANCE_PERCENT / 100.0) < 0.05)
	_restore_state(saved)
	_clear_pings()

# ---------------- Section 1.4: no fog, ever ------------------------------------

func _fog_is_untouched() -> void:
	print("-- Fog is byte-identical before and after %d pings --" % DAWNS)
	var saved: Array = _save_state()
	var fog: FogOfWar = _main.fog
	var before: PackedByteArray = fog._image.get_data()
	var explored_before: int = fog.explored_count()
	_open_the_pool()
	var made: int = 0
	for i in range(DAWNS):
		_clear_pings()
		if _raven.dawn(i + 1) != null:
			made += 1
	_check("%d pings were made" % made, made > 100)
	_check("the fog image did not change by a single byte", fog._image.get_data() == before)
	_check("...and no cell was explored", fog.explored_count() == explored_before)
	_restore_state(saved)
	_clear_pings()

func _claiming_clears_the_mark() -> void:
	print("-- A claimed ping clears its mark; marks sit above the fog --")
	var saved: Array = _save_state()
	_open_the_pool()
	var site = null
	for i in range(50):
		site = _raven.dawn(i + 1)
		if site != null:
			break
	_check("a ping to look at", site != null)
	if site == null:
		_restore_state(saved)
		return
	var mark: Node2D = _raven.marker_for(site)
	_check("it has a mark on the world", mark != null and mark.is_inside_tree())
	_check("...drawn above the fog", mark.z_index > _main.fog.z_index,
		"%d vs fog %d" % [mark.z_index, _main.fog.z_index])
	_check("...and on the minimap", _raven.minimap_points().has(site.position))
	_check("...and it inspects as the Raven's Word",
		String(mark.get_inspect_data().get("title", "")) == "The Raven's Word")
	EventBus.site_looted.emit(_main.villain, site, {})
	_check("looting it claims the ping", _raven.outstanding() == 0)
	_check("...and the mark is going", mark.is_queued_for_deletion())
	_check("...and the minimap forgets it", not _raven.minimap_points().has(site.position))
	_restore_state(saved)
	_clear_pings()

func _the_chip_drops_follow() -> void:
	print("-- Centring on a ping drops villain-follow --")
	var saved: Array = _save_state()
	_open_the_pool()
	var site = null
	for i in range(50):
		site = _raven.dawn(i + 1)
		if site != null:
			break
	var vc: VillainController = _main.villain_controller
	vc.following = true
	var ticks: int = _main.camera.manual_pan_ticks
	_main._on_raven_chip()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the chip counted as a manual pan", _main.camera.manual_pan_ticks == ticks + 1)
	_check("...and follow is off", not vc.following)
	_check("...and the ping is marked seen", _raven.unseen() == 0)
	_check("...and its panel is open", _main.inspector.is_open())
	_restore_state(saved)
	_clear_pings()

# ---------------- Helpers ------------------------------------------------------

## Makes every minor flagged site honestly nameable.
func _open_the_pool() -> void:
	for s in _sites.lootable_sites():
		if s.raven_eligible:
			s.discovered = false
			s.charges_left = maxi(1, s.charges_max)
			s.cleared = true

func _clear_pings() -> void:
	for p in _raven.pings:
		if is_instance_valid(p["marker"]):
			p["marker"].queue_free()
	_raven.pings.clear()

func _save_state() -> Array:
	var out: Array = []
	for s in _sites.lootable_sites():
		out.append([s, s.discovered, s.charges_left, s.cleared, s.raven_eligible])
	return out

func _restore_state(saved: Array) -> void:
	for row in saved:
		var s = row[0]
		s.discovered = row[1]
		s.charges_left = row[2]
		s.cleared = row[3]
		s.raven_eligible = row[4]

func _site(id: String) -> WorldSite:
	for s in _sites.sites:
		if s.site_id == id:
			return s
	return null

func _block_for(id: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_sites.json"))
	for e in parsed.get("sites", []):
		if String(e.get("id", "")) == id:
			return e.get("lootable", {})
	return {}

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
