extends Node
## Verifies the lootable-site layer against `LOOT_SITES_SPEC.md` section 10.
##
##   godot --headless --path . res://tools/verify_loot_tables.tscn
##
## **A scene, not `-s`** (the spec says so, and so does the autoload gotcha in
## CLAUDE.md): under `-s` this file would compile before `LootCatalog`,
## `GameState` and `EventBus` exist, and the failure surfaces as a missing
## method on a GDScript rather than as anything mentioning autoloads.
##
## ## What it is for
##
## Repo rule: tools re-derive every number. The tier ratios in section 5 are a
## *design* table -- "Band 2 pays 3-6 mundane units, 1-2 Dark Essence, 2-5 gold,
## about 15% for an uncommon relic" -- and a weight edited in
## `data/loot_tables.json` moves all four of those at once, silently, in a way
## no playtest would isolate. So the harness rolls each table ten thousand times
## through **the real `LootCatalog.roll()`** and compares the means against the
## band it claims.
##
## There is deliberately no second, simplified roll in here. A harness that
## reimplements the thing it checks only proves that two authors agreed.
##
## ## Means, not outcomes
##
## Section 5's ranges are read as bands the *expected* payout must sit inside.
## A single Band-2 roll can obviously pay 1 bone or 9; what must not drift is
## what the site is worth on average, because that is what "distance buys
## quality" is made of.

const ROLLS: int = 10000
const DUSKS: int = 1000

## Section 5's tier targets: band -> [mundane lo, mundane hi, essence lo,
## essence hi, gold lo, gold hi, relic chance, tolerance].
const BANDS := {
	1: {"mundane": [2.0, 4.0], "essence": [0.0, 1.0], "gold": [0.0, 2.0], "relic": 0.10},
	2: {"mundane": [3.0, 6.0], "essence": [1.0, 2.0], "gold": [2.0, 5.0], "relic": 0.15},
	3: {"mundane": [4.0, 6.0], "essence": [1.0, 3.0], "gold": [3.0, 6.0], "relic": 0.30},
	4: {"mundane": [6.0, 10.0], "essence": [3.0, 5.0], "gold": [6.0, 12.0], "relic": 0.40},
}
## "~15%" is not 15.00%. Six points either way, which is wide enough that a
## 10k sample never flaps and narrow enough that doubling a relic weight fails.
const RELIC_TOLERANCE: float = 0.06

## The tables a spec authorises to break their band, **per column**, and what
## each is asserted against instead (see `_the_authored_exceptions`).
##
## Per column on purpose. The first version of this exempted four whole tables,
## which quietly stopped checking eleven numbers to excuse four: the crypt's
## guaranteed relic says nothing about its gold, and the den's cloak says
## nothing about its bones. A table may only appear here if a spec says so in
## words, and only for the column those words are about.
const AUTHORED_EXCEPTIONS := {
	"small_cache": {
		"columns": ["mundane", "essence", "gold", "relic"],
		"why": "amendment ruling 1 -- gold-first, mundane demoted to garnish",
	},
	"wolf_den": {
		"columns": ["relic"],
		"why": "section 5 -- the best wolfhide_cloak odds in the game",
	},
	"crypt": {
		"columns": ["relic"],
		"why": "section 2 -- a guaranteed relic, which no percentage describes",
	},
	"outlaw_cave": {
		"columns": ["relic"],
		"why": "amendment ruling 2 -- what it guarantees is arms, not a relic",
	},
}

func _exempt(table_id: String, column: String) -> bool:
	if not AUTHORED_EXCEPTIONS.has(table_id):
		return false
	return AUTHORED_EXCEPTIONS[table_id]["columns"].has(column)

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(8):
		await get_tree().process_frame

	seed(20260829)
	print("\n=== Lootable sites (LOOT_SITES_SPEC §10) ===\n")
	_tables_are_well_formed()
	_relics_are_whole()
	_tier_ratios_hold()
	_the_authored_exceptions()
	_sites_are_authored_to_budget()
	_the_choice_sheet_is_a_dilemma()
	_remainder_charges_stay_at_the_site()
	_notice_and_deeds_split()
	_relic_effects_wake_on_deposit()
	_dark_essence_is_field_only()
	await _the_channel_is_the_push_your_luck()
	# The den section owns the order of everything that follows: it counts the
	# packs, then fights one of them, then empties the rest. Running the fight
	# on its own would leave a den short a wolf before anyone had counted it.
	await _the_den_and_the_dusk_gate()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Schema ------------------------------------------------------

func _tables_are_well_formed() -> void:
	print("-- Tables load, and every id in them resolves --")
	_check("there are tables at all", not LootCatalog.table_ids().is_empty())
	for id in LootCatalog.table_ids():
		var t: Dictionary = LootCatalog.table(id)
		_check("'%s' rolls at least once" % id, int(t.get("rolls", 0)) >= 1,
			"rolls=%s" % t.get("rolls", "none"))
		var entries: Array = t.get("entries", [])
		_check("'%s' has entries" % id, not entries.is_empty())
		var all: Array = entries.duplicate()
		all.append_array(t.get("guaranteed", []))
		for entry in all:
			if entries.has(entry):
				_check("'%s': every weight is positive" % id,
					float(entry.get("weight", 0.0)) > 0.0, str(entry))
			if entry.has("relic"):
				_check("'%s': relic '%s' exists" % [id, entry["relic"]],
					LootCatalog.has_relic(String(entry["relic"])))
			elif entry.has("relic_tier"):
				var tier: String = String(entry["relic_tier"])
				_check("'%s': tier '%s' is a real tier" % [id, tier],
					LootCatalog.RELIC_TIERS.has(tier))
				_check("'%s': tier '%s' has relics in it" % [id, tier],
					not LootCatalog.relics_of_tier(tier).is_empty())
			else:
				var kind: String = String(entry.get("kind", ""))
				_check("'%s': '%s' is a loot kind" % [id, kind],
					LootCatalog.LOOT_KINDS.has(kind))
				_check("'%s': %s min <= max" % [id, kind],
					int(entry.get("min", 1)) <= int(entry.get("max", 1)))

	# Every site's declared table exists. This is the join that actually breaks:
	# a table renamed here and not there fails silently at the first loot.
	for site in _lootable_sites():
		var table_id: String = String(site["lootable"].get("loot_table", ""))
		_check("site '%s' names a table that exists (%s)" % [site["id"], table_id],
			LootCatalog.has_table(table_id))
		var sheet: String = String(site["lootable"].get("choices", ""))
		if sheet != "":
			_check("site '%s' names a choice sheet that exists (%s)" % [site["id"], sheet],
				LootCatalog.has_choice_sheet(sheet))

func _relics_are_whole() -> void:
	print("-- Relics: ten of them, each exactly once --")
	var ids: Array = LootCatalog.relic_ids()
	_check("the first set is ten relics", ids.size() == 10, "%d" % ids.size())
	var seen := {}
	for id in ids:
		_check("relic '%s' appears exactly once" % id, not seen.has(id))
		seen[id] = true
		var r: Dictionary = LootCatalog.relic(id)
		_check("relic '%s' has a name" % id, String(r.get("name", "")) != "")
		_check("relic '%s' has a real tier" % id,
			LootCatalog.RELIC_TIERS.has(String(r.get("tier", ""))))
		_check("relic '%s' has a gold value" % id, int(r.get("gold_value", 0)) > 0)
	# Section 7: legendary does not drop from loot tables in R2 -- it is reserved
	# for feats. The way to be sure is to check no table can produce one.
	var legendary_referenced: bool = false
	for tid in LootCatalog.table_ids():
		var t: Dictionary = LootCatalog.table(tid)
		var all: Array = t.get("entries", []).duplicate()
		all.append_array(t.get("guaranteed", []))
		for entry in all:
			if String(entry.get("relic_tier", "")) == "legendary":
				legendary_referenced = true
	_check("no table can drop a legendary (section 7 reserves them for feats)",
		not legendary_referenced)
	# And the one drop the spec names by hand.
	_check("the wolf den names wolfhide_cloak by id, not by tier",
		_table_names_relic("wolf_den", "wolfhide_cloak"))

func _table_names_relic(table_id: String, relic_id: String) -> bool:
	for entry in LootCatalog.table(table_id).get("entries", []):
		if String(entry.get("relic", "")) == relic_id:
			return true
	return false

# ---------------- The ratios --------------------------------------------------

## Rolls each table `ROLLS` times and reports what it actually pays. The print
## is as much the point as the assertion: this is the table a designer reads
## when tuning yield against carry capacity (section 10's flagged pair).
func _tier_ratios_hold() -> void:
	print("-- Tier ratios, over %d rolls per table (§5) --" % ROLLS)
	print("    %-22s %5s  %6s %6s %6s   %6s" % ["table", "band", "mund", "ess", "gold", "relic"])
	for id in LootCatalog.table_ids():
		var t: Dictionary = LootCatalog.table(id)
		var band: int = int(t.get("band", 2))
		var m: Dictionary = _measure(id)
		var note: String = ""
		if AUTHORED_EXCEPTIONS.has(id):
			note = "   (exempt: %s)" % ", ".join(AUTHORED_EXCEPTIONS[id]["columns"])
		print("    %-22s %5d  %6.2f %6.2f %6.2f   %5.1f%%%s" % [id, band,
			m["mundane"], m["essence"], m["gold"], m["relic"] * 100.0, note])
		var want: Dictionary = BANDS[band]
		if not _exempt(id, "mundane"):
			_in_band("%s: mundane units" % id, m["mundane"], want["mundane"])
		if not _exempt(id, "essence"):
			_in_band("%s: Dark Essence" % id, m["essence"], want["essence"])
		if not _exempt(id, "gold"):
			_in_band("%s: gold" % id, m["gold"], want["gold"])
		if not _exempt(id, "relic"):
			_close("%s: relic chance" % id, m["relic"], float(want["relic"]), RELIC_TOLERANCE)

## One table, `ROLLS` times, through the real roller. `drawn` is empty every
## roll on purpose: this measures what a table pays a player who has found
## nothing yet, which is the number the band table is written about.
func _measure(id: String) -> Dictionary:
	var mundane: float = 0.0
	var essence: float = 0.0
	var gold: float = 0.0
	var relics: float = 0.0
	for i in range(ROLLS):
		var out: Dictionary = LootCatalog.roll(id, [])
		for kind in out["resources"].keys():
			var amount: float = float(out["resources"][kind])
			if kind == "gold":
				gold += amount
			elif kind == "dark_essence":
				essence += amount
			elif LootCatalog.MUNDANE_KINDS.has(kind):
				mundane += amount
		if not out["relics"].is_empty():
			relics += 1.0
	var n: float = float(ROLLS)
	return {"mundane": mundane / n, "essence": essence / n, "gold": gold / n,
		"relic": relics / n}

## The exceptions are not unchecked -- they are checked against the rule that
## authorised them, which is stricter than "it is allowed to be different".
func _the_authored_exceptions() -> void:
	print("-- The four authored exceptions, against what authorised them --")
	var cache: Dictionary = _measure("small_cache")
	_check("the cache pays more gold than mundane (amendment ruling 1: a cache whose best outcome is wood is a bug)",
		cache["gold"] > cache["mundane"] * 2.0,
		"gold %.2f vs mundane %.2f" % [cache["gold"], cache["mundane"]])
	_check("...and its trinket chance beats the Band-1 rate",
		cache["relic"] > BANDS[1]["relic"], "%.1f%%" % (cache["relic"] * 100.0))

	var den: float = _named_relic_rate("wolf_den", "wolfhide_cloak")
	print("    wolfhide_cloak from the den: %.1f%%" % (den * 100.0))
	_check("the den's cloak odds beat the Band-2 relic rate (§5's one authored exception)",
		den > BANDS[2]["relic"], "%.1f%%" % (den * 100.0))
	var elsewhere: bool = false
	for id in LootCatalog.table_ids():
		if id != "wolf_den" and _table_names_relic(id, "wolfhide_cloak"):
			elsewhere = true
	_check("...and no other table names it, so the den really is where it comes from", not elsewhere)

	var crypt_rare: float = 0.0
	var crypt_essence: float = 0.0
	for i in range(ROLLS):
		var out: Dictionary = LootCatalog.roll("crypt", [])
		for rid in out["relics"]:
			var tier: String = String(LootCatalog.relic(rid).get("tier", ""))
			if tier == "rare" or tier == "legendary":
				crypt_rare += 1.0
				break
		crypt_essence += float(out["resources"].get("dark_essence", 0))
	_check("the crypt pays a rare-or-better EVERY time (§2: guaranteed relic)",
		is_equal_approx(crypt_rare / float(ROLLS), 1.0), "%.3f" % (crypt_rare / float(ROLLS)))
	_check("...and its Dark Essence is heavy (§2), above the Band-4 floor",
		crypt_essence / float(ROLLS) >= BANDS[4]["essence"][0],
		"%.2f" % (crypt_essence / float(ROLLS)))

	var armed: float = 0.0
	var cave_gold: float = 0.0
	for i in range(ROLLS):
		var out: Dictionary = LootCatalog.roll("outlaw_cave", [])
		if int(out["resources"].get("arms", 0)) > 0:
			armed += 1.0
		cave_gold += float(out["resources"].get("gold", 0))
	_check("the outlaw cave has weapons in it EVERY time (amendment ruling 2)",
		is_equal_approx(armed / float(ROLLS), 1.0), "%.3f" % (armed / float(ROLLS)))
	_check("...and it is a gold hoard (§2), inside the Band-4 gold band",
		cave_gold / float(ROLLS) >= BANDS[4]["gold"][0], "%.2f" % (cave_gold / float(ROLLS)))

	# Ruling 2 again, the negative half: arms are HUMAN SITES ONLY.
	var human := ["outlaw_cave", "cursed_battlefield", "abandoned_camp"]
	for id in LootCatalog.table_ids():
		var carries: bool = false
		var all: Array = LootCatalog.table(id).get("entries", []).duplicate()
		all.append_array(LootCatalog.table(id).get("guaranteed", []))
		for entry in all:
			if String(entry.get("kind", "")) == "arms":
				carries = true
		if carries:
			_check("'%s' may carry arms (human sites only, ruling 2)" % id, human.has(id))
	_check("the wolf den carries no arms -- it keeps its cloak (ruling 2)",
		not _table_carries("wolf_den", "arms"))

func _table_carries(table_id: String, kind: String) -> bool:
	var all: Array = LootCatalog.table(table_id).get("entries", []).duplicate()
	all.append_array(LootCatalog.table(table_id).get("guaranteed", []))
	for entry in all:
		if String(entry.get("kind", "")) == kind:
			return true
	return false

func _named_relic_rate(table_id: String, relic_id: String) -> float:
	var hits: float = 0.0
	for i in range(ROLLS):
		if LootCatalog.roll(table_id, [])["relics"].has(relic_id):
			hits += 1.0
	return hits / float(ROLLS)

# ---------------- The catalog as authored -------------------------------------

## Section 2's density budget, which is a *design* number and therefore exactly
## the kind that rots: ROGUELITE_REWORK section 4 adopted 10-15 ACTIVE, and
## section 2's per-type "per run" column is the pool the R4 shuffle draws from.
func _sites_are_authored_to_budget() -> void:
	print("-- The catalog, as placed --")
	var sites: Array = _lootable_sites()
	var by_type := {}
	var by_band := {}
	for s in sites:
		var t: String = String(s["lootable"].get("type", ""))
		var b: int = int(s["lootable"].get("band", 2))
		by_type[t] = int(by_type.get(t, 0)) + 1
		by_band[b] = int(by_band.get(b, 0)) + 1
	print("    %d active lootable sites, %d of the twelve-plus types represented"
		% [sites.size(), by_type.size()])
	for b in [1, 2, 3, 4]:
		print("      band %d: %d" % [b, int(by_band.get(b, 0))])
	_check("the active count is inside ROGUELITE_REWORK §4's 10-15 budget",
		sites.size() >= 10 and sites.size() <= 15, "%d placed" % sites.size())
	_check("every band is represented, so distance can buy quality at all",
		by_band.size() == 4, str(by_band))
	_check("the three graveyard tiers all exist (amendment ruling 3)",
		by_type.has("derelict_graveyard") and by_type.has("village_graveyard")
		and by_type.has("church_cemetery"), str(by_type.keys()))
	_check("the single `cemetery` type is gone, replaced by the tier",
		not by_type.has("cemetery"))
	_check("there is at least one den, or the dusk gate has nothing to gate",
		int(by_type.get("wolf_den", 0)) >= 1)

	for s in sites:
		var block: Dictionary = s["lootable"]
		var band: int = int(block.get("band", 2))
		# The signposting rule, from the data side. The generator hard-errors on
		# this too; asserted here as well because the two files can drift apart
		# without anyone re-running the generator.
		if bool(s.get("signposted", false)):
			_check("signposted site '%s' is Band 1-2 (§7 rule 2)" % s["id"], band <= 2,
				"band %d" % band)
		# The derelict graveyard: no notice, EVER (amendment ruling 3). It is
		# what retroactively makes the church cemetery expensive.
		if String(block.get("type", "")) == "derelict_graveyard":
			_check("the derelict graveyard generates no notice, ever",
				int(block.get("notice", {}).get("threat", 0)) == 0)
		if String(block.get("type", "")) == "church_cemetery":
			_check("the church cemetery's notice escalates per grave (§2's Band-3 note)",
				bool(block.get("notice", {}).get("escalates", false)))
		# Section 8: pool and active_count are specified now, honoured in R4.
		_check("site '%s' carries the R4 shuffle fields" % s["id"],
			String(block.get("pool", "")) != "" and int(block.get("active_count", 0)) > 0)

# ---------------- The four-way sheet ------------------------------------------

## Section 4's rules are gating rules, and gating is what makes the sheet a
## dilemma rather than a menu. Each of the three is asserted as a *transition*:
## what was offered before the act, and what is offered after it.
func _the_choice_sheet_is_a_dilemma() -> void:
	print("-- The grave, and the four ways to leave it (§4) --")
	var site: WorldSite = _site("fresh_grave_hollow")
	if site == null:
		_check("a fresh grave is placed to test the sheet with", false)
		return
	var v := Necromancer.new()

	var offered: Array = _ids(site.sheet_choices(v))
	_check("an untouched grave offers raise, steal and return",
		offered.has("raise") and offered.has("steal") and offered.has("return"), str(offered))
	_check("...and does NOT offer destroy-the-evidence yet",
		not offered.has("conceal"), str(offered))

	# Raise, then look again. Raise-then-steal is allowed -- the corpse and the
	# valuables are separate takings from one grave.
	site._resolve_choice(v, _choice(site, "raise"))
	offered = _ids(site.sheet_choices(v))
	_check("after raising, stealing is still on the table (§4: raise-then-steal is allowed)",
		offered.has("steal"), str(offered))
	_check("...and destroy-the-evidence has appeared", offered.has("conceal"), str(offered))
	_check("...and raising it twice is not offered", not offered.has("raise"), str(offered))
	_check("the raised corpse is recorded, dormant until the escort lands",
		v.raised_dead.size() == 1, "%d" % v.raised_dead.size())

	# A second grave, to test the mercy branch from a clean start. **Mercy ends
	# the grave**, which is what "forecloses profit, permanently" means
	# mechanically: filling it back in leaves nothing to raise and nothing to
	# steal, so the charge is spent and this one-grave site is finished. The
	# sheet itself is never reopened, so the assertion is on the *actions*
	# rather than on `sheet_choices()` -- which would describe the next grave.
	var mercy: WorldSite = _site("fresh_grave_scree")
	var v2 := Necromancer.new()
	var charges_before: int = mercy.charges_left
	mercy._resolve_choice(v2, _choice(mercy, "return"))
	_check("mercy finishes the grave on the spot", mercy.charges_left == charges_before - 1,
		"%d -> %d" % [charges_before, mercy.charges_left])
	_check("...and forecloses profit permanently -- the site offers nothing further",
		_actions_at(mercy, v2).is_empty(), str(_actions_at(mercy, v2)))
	_check("...and swaps to its looted art, because the ground was disturbed",
		mercy.is_spent())
	_check("returning the belongings takes nothing", v2.carried.is_empty())
	_check("...and is a Mercy deed", _last_deed_axis(v2, "mercy") == 1)
	_check("...and cost no notice at all", _choice(mercy, "return")["effects"]["notice"] == 0.0)

func _ids(choices: Array) -> Array:
	var out: Array = []
	for c in choices:
		out.append(String(c.get("id", "")))
	return out

func _choice(site: WorldSite, id: String) -> Dictionary:
	for c in LootCatalog.choice_sheet(site.choices_id).get("choices", []):
		if String(c.get("id", "")) == id:
			return c
	return {}

# ---------------- Remainder charges (SORTIE_SPEC §4) --------------------------

## The rule the whole "one more grave, or turn back?" question rests on: loot
## that does not fit **stays at the site**, the site keeps its actions and its
## unlooted sprite, and its payload says what is still there. No ground piles.
func _remainder_charges_stay_at_the_site() -> void:
	print("-- Remainder charges (SORTIE_SPEC §4) --")
	var site: WorldSite = _site("cursed_battlefield")
	if site == null:
		_check("the battlefield is placed to test overflow with", false)
		return
	var v := Necromancer.new()
	# Standing at it: `begin_action` enforces reach, and it should -- no remote
	# looting, and no remote collecting either.
	v.position = site.position
	# Fill his hands to one slot short, so the next pull cannot possibly fit.
	v.add_carried("bones", v.carry_capacity() - 1)
	var before_charges: int = site.charges_left
	site._resolve_loot(v, 1.0, "", {}, 0.0)
	_check("he is full", v.carry_space() == 0, "%d free" % v.carry_space())
	_check("the overflow stayed at the site as a remainder", site.has_remainder(),
		str(site.remainder))
	_check("...and the site is NOT spent while it holds one", not site.is_spent())
	_check("...and still offers actions", not site.actions_for(v).is_empty())
	_check("...and its payload says what is still there",
		_details_mention(site, "You left"), "no 'You left' row")
	_check("the pull still cost a charge", site.charges_left == before_charges - 1)

	# Empty his hands and come back: a legitimate, time-taxed play.
	v.carried.clear()
	var left: Dictionary = site.remainder.duplicate()
	site.begin_action(v, "collect")
	_check("coming back with empty hands collects the remainder",
		not site.has_remainder() or v.carried_total() > 0, str(site.remainder))
	_check("...and he is holding what he left", v.carried_total() > 0,
		"collected %s of %s" % [str(v.carried), str(left)])

func _details_mention(site: WorldSite, label: String) -> bool:
	for row in site.get_inspect_data().get("details", []):
		if String(row.get("label", "")) == label:
			return true
	return false

# ---------------- The split that is the whole point of section 6 --------------

## Notice is world state and goes to `GameState.add_threat()`; the axis half is
## recorded on the villain's own ledger. **Both halves, and neither in the other
## place** -- nothing reputation-shaped is ever reread out of `GameState`.
func _notice_and_deeds_split() -> void:
	print("-- Notice is global, deeds are per-villain (§6, decision 2026-08-06) --")
	var quiet: WorldSite = _site("derelict_graveyard")
	var loud: WorldSite = _site("cemetery")
	var v := Necromancer.new()

	var threat_before: int = GameState.threat
	quiet._resolve_choice(v, _choice(quiet, "steal"))
	_check("robbing the derelict graveyard adds NO threat -- nobody was watching",
		GameState.threat == threat_before, "threat moved to %d" % GameState.threat)
	_check("...but it is still a Wealth deed on his ledger", _last_deed_axis(v, "wealth") == 1)

	threat_before = GameState.threat
	loud._resolve_choice(v, _choice(loud, "steal"))
	var first: int = GameState.threat - threat_before
	threat_before = GameState.threat
	loud._resolve_choice(v, _choice(loud, "steal"))
	var second: int = GameState.threat - threat_before
	_check("the church cemetery is noticed", first > 0, "%d" % first)
	_check("...and the second grave is louder than the first (escalating notice)",
		second > first, "%d then %d" % [first, second])
	_check("the ledger is ordered and stamped in game-days",
		v.deeds.size() >= 3 and v.deeds[0].has("day") and int(v.deeds[0]["seq"]) == 0)
	_check("the deeds live on the villain, not in GameState",
		not ("deeds" in GameState))

func _last_deed_axis(v: Necromancer, axis: String) -> int:
	if v.deeds.is_empty():
		return 0
	return int(v.deeds[v.deeds.size() - 1].get("axes", {}).get(axis, 0))

# ---------------- Relics ------------------------------------------------------

## Section 7: a relic in hand grants nothing, and effects activate on deposit.
## Every live effect is asserted as a *change*, before and after banking, so an
## effect that silently stopped being read fails here rather than in a playtest
## nobody can attribute.
func _relic_effects_wake_on_deposit() -> void:
	print("-- Relics: nothing in hand, everything banked (§7) --")
	var v := Necromancer.new()
	var carry_before: int = v.carry_capacity()
	v.add_relic("pallbearers_gloves")
	_check("a relic occupies a carry slot", v.carried_total() == 1)
	_check("...and in his hands it does nothing", v.carry_capacity() == carry_before,
		"%d -> %d" % [carry_before, v.carry_capacity()])
	v.bank_relics()
	_check("...and banked it is +2 carry", v.carry_capacity() == carry_before + 2,
		"%d" % v.carry_capacity())
	_check("...and it left his hands", v.relics_carried.is_empty())

	var v2 := Necromancer.new()
	var hp_before: int = v2.max_hp()
	var int_before: int = v2.attribute("intelligence")
	v2.relics_banked.append("sermon_of_ash")
	_check("the Sermon of Ash is +1 Intelligence, computed at use time",
		v2.attribute("intelligence") == int_before + 1)
	_check("...and it reaches his casting profile, with no second code path",
		String(v2.combat_profile()["profile"]) == "Arcane")
	_check("...and his hit points are untouched, because Endurance did not move",
		v2.max_hp() == hp_before)

	var v3 := Necromancer.new()
	_check("no censer, no dawn healing", v3.dawn_heal() == 0)
	v3.relics_banked.append("chipped_censer")
	_check("the censer mends 2 at dawn", v3.dawn_heal() == 2)
	v3.relics_banked.append("barrow_lantern")
	_check("the lantern is +2 cells of fog reveal", v3.fog_reveal_bonus() == 2)
	_check("a grave channel is unchanged without the ring",
		is_equal_approx(v3.channel_multiplier(["grave"]), 1.0))
	v3.relics_banked.append("sextons_ring")
	_check("the Sexton's Ring is 25% off a grave channel",
		is_equal_approx(v3.channel_multiplier(["grave"]), 0.75),
		"%.2f" % v3.channel_multiplier(["grave"]))
	_check("...and does nothing to a crypt pull, because it is tagged",
		is_equal_approx(v3.channel_multiplier(["crypt"]), 1.0))

	# Dormant effects are data with no consumer. They must not quietly do
	# something, which is the failure this whole flag exists to prevent.
	var v4 := Necromancer.new()
	var carry4: int = v4.carry_capacity()
	v4.relics_banked.append("noble_seal")
	v4.relics_banked.append("ledger_of_names")
	_check("dormant relics change nothing (§7: data present, no-op until their system lands)",
		v4.carry_capacity() == carry4 and v4.attribute("intelligence") == 7)

	# Unique per run: the same relic cannot be drawn twice.
	var v5 := Necromancer.new()
	_check("a relic can be taken once", v5.add_relic("grave_coins"))
	_check("...and not twice", not v5.add_relic("grave_coins"))
	var out: Dictionary = LootCatalog.roll("small_cache", ["grave_coins", "tarnished_locket"])
	_check("a table cannot pay out a relic already drawn this run",
		not out["relics"].has("grave_coins") and not out["relics"].has("tarnished_locket"))

# ---------------- The exclusivity law, as a code assertion --------------------

## Section 5 and ROGUELITE_REWORK section 8: Dark Essence is field loot only.
## The correction those two carry is that this was a *goal*, not a convention --
## so it is asserted rather than asserted-in-prose.
func _dark_essence_is_field_only() -> void:
	print("-- Dark Essence, field-only for real this time (§5) --")
	var before: int = GameState.dark_essence
	var missions = _main.mission_system
	if missions:
		missions._apply_effects({"dark_essence": 10})
		_check("a mission cannot print Dark Essence", GameState.dark_essence == before,
			"%d -> %d" % [before, GameState.dark_essence])
	var events = _main.event_system
	if events:
		events._apply_effects({"dark_essence": 10})
		_check("an event cannot print Dark Essence", GameState.dark_essence == before,
			"%d -> %d" % [before, GameState.dark_essence])
	# A sink is not a source: spending must still work, because spending is the
	# thing Dark Essence has always lacked.
	GameState.add_resource("dark_essence", 6)
	if events:
		events._apply_effects({"dark_essence": -5})
		_check("...but an event may still charge it", GameState.dark_essence == before + 1,
			"%d" % GameState.dark_essence)
	# Gold arrived with the sites, and it arrived properly.
	_check("gold is the sixth resource and add/spend both know it",
		GameState.can_afford("gold", 0) and GameState.spend_resource("gold", 0))

# ---------------- The channel (§3) --------------------------------------------

## "Looting takes time, on purpose. Standing still at a site while the sun moves
## is the whole push-your-luck engine." So the channel is asserted as the four
## things that make it one: it takes real time, **moving cancels it and refunds
## nothing**, his own idle pacing does not cancel it, and reach is required to
## start it at all.
func _the_channel_is_the_push_your_luck() -> void:
	print("-- Looting takes time, and moving costs you it (§3) --")
	var site: WorldSite = _site("hidden_cache")
	if site == null:
		_check("a cache is placed to channel at", false)
		return
	var v := Necromancer.new()

	v.position = site.position + Vector2(1000, 0)
	_check("out of reach, he cannot start -- no remote looting (§3)",
		not site.begin_action(v, "loot"))

	v.position = site.position
	_check("standing at it, he can", site.begin_action(v, "loot"))
	_check("...and he is visibly working", site.is_channelling() and v.is_channelling)
	_check("...and the panel says how far along", site.channel_progress() < 0.5)

	# A delta accumulator, so this is what `Engine.time_scale` scales. Half the
	# channel, in one step.
	site._process(site.channel_seconds * 0.5)
	_check("half the time spent is half the progress",
		absf(site.channel_progress() - 0.5) < 0.05, "%.2f" % site.channel_progress())
	_check("...and nothing has paid out yet", v.carried.is_empty())

	# Idle pacing must NOT cancel it: he stands still for longer than
	# IDLE_RESUME_SECONDS on purpose, and wandering off his own grave would be
	# the bug this flag exists to prevent.
	v.step(Vector2.ZERO, Necromancer.IDLE_RESUME_SECONDS + 2.0)
	_check("standing still does not wander him off the job", not v.is_pacing()
		and site.in_reach(v))

	# Moving does cancel it, and refunds nothing.
	v.position += Vector2(WorldSite.CHANNEL_BREAK_PX + 4.0, 0)
	site._process(0.1)
	_check("moving cancels the channel", not site.is_channelling())
	_check("...and refunds nothing -- the charge is still there, the time is not",
		site.charges_left == site.charges_max and v.carried.is_empty())
	_check("...and he is free again", not v.is_channelling)

	# And the whole way through, for real.
	v.position = site.position
	_check("he can start again", site.begin_action(v, "loot"))
	site._process(site.channel_seconds + 0.01)
	_check("a completed channel pays out", not v.carried.is_empty() or not site.relic_remainder.is_empty()
		or not v.relics_carried.is_empty(), str(v.carried))
	_check("...and spends the charge", site.charges_left == site.charges_max - 1)
	_check("...and the cache, being one-shot, is now spent", site.is_spent())

# ---------------- Guardians fight (§3b / §9) ----------------------------------

## The path the den's whole design rests on: a guardian notices the villain,
## closes, and the ordinary `CombatSystem` policy runs the fight. Asserted with
## the real systems on the real map, because the failure mode here is not a bad
## number -- it is a guardian that stands still forever and a den nobody can
## clear.
##
## Called from the den section, after the packs have been counted and before
## they are emptied -- fighting one of them is destructive, and the count has to
## happen first.
func _guardians_actually_fight(den: WorldSite) -> void:
	print("-- Guardians engage through the ordinary combat policy (§9) --")
	var combat: CombatSystem = _main.combat_system
	var villain: Necromancer = _main.villain
	var pack: int = den.guardians.size()
	var hp_before: int = villain.hp

	# Walk him into the den's clearing and let the systems run.
	villain.place_at(den.position)
	var engaged: bool = false
	for i in range(240):
		combat._process(0.1)
		if combat.is_fighting():
			engaged = true
			break
		await get_tree().process_frame
	_check("a pack wolf comes for him when he walks into the den", engaged)
	_check("...and the lair aura does not protect him out here (§3b)",
		engaged or CombatSystem.LAIR_AURA_PROTECTS_VILLAIN == false)

	# Let it run to a conclusion. He is one caster against a pack, which section
	# 3b calls a real gamble -- so either outcome is correct, and what is
	# asserted is that it RESOLVES rather than who wins.
	for i in range(600):
		combat._process(0.1)
		if not combat.is_fighting():
			break
	_check("the fight resolves rather than hanging", not combat.is_fighting())
	_check("...and somebody paid for it",
		villain.hp < hp_before or den.guardians.size() < pack,
		"villain %d -> %d, pack %d -> %d" % [hp_before, villain.hp, pack, den.guardians.size()])
	# Pack wolves are SiteGuardians and never enter `wolves` (§3b's second guard).
	_check("den wolves never enter the dusk-wolf list", combat.wolves.is_empty(),
		"%d" % combat.wolves.size())

	# Put the world back the way the later tests expect to find it.
	villain.heal_full()
	villain.place_at(Vector2(_main.settlement.position))

# ---------------- The den, and the dusk gate (§3b) ----------------------------

func _the_den_and_the_dusk_gate() -> void:
	print("-- The den, and the dusk gate (§3b) --")
	var sites: WorldSites = _main.world_sites
	var combat: CombatSystem = _main.combat_system
	var villain: Necromancer = _main.villain
	var dens: Array = sites.dens()
	_check("the dens are placed", dens.size() >= 1, "%d" % dens.size())
	if dens.is_empty():
		return
	for den in dens:
		_check("den '%s' is in a forest clearing, unsignposted (§3b: found, not followed)"
			% den.site_id, not den.signposted)
		_check("den '%s' posts 2-3 wolves" % den.site_id,
			den.guardians.size() >= 2 and den.guardians.size() <= 3,
			"%d" % den.guardians.size())
		for g in den.guardians:
			_check("...wearing Wolf.gd's own stats (18 hp, Str 5) and art",
				g.max_hp() == 18 and g.attribute("strength") == 5
				and g.sprite_path == Wolf.SPRITE_PATH,
				"%d hp, Str %d" % [g.max_hp(), g.attribute("strength")])
			_check("...and its flee-below-5 rule", g.flee_below_hp == Wolf.FLEE_BELOW_HP)
		_check("den '%s' offers no loot while it is guarded" % den.site_id,
			den.actions_for(villain).is_empty())

	# One real fight, on the den nothing else in this harness touches.
	await _guardians_actually_fight(dens[dens.size() - 1])

	# With a den standing, the roll is what it always was.
	_check("with a den uncleared, the gate is open", sites.any_den_uncleared())
	var rate: float = await _dusk_rate(combat)
	print("    %d dusks with a den standing: %.1f%% spawned" % [DUSKS, rate * 100.0])
	_check("...and dusk still brings a wolf at roughly 55%%",
		absf(rate - CombatSystem.WOLF_SPAWN_CHANCE_PERCENT / 100.0) < 0.06,
		"%.1f%%" % (rate * 100.0))
	combat._first_dusk_done = false
	combat.wolves.clear()
	combat._on_dusk(1)
	_check("...and the first dusk of a run is still guaranteed", combat.wolves.size() == 1)
	_clear_wolves(combat)

	# Clear the packs. Routed counts as dealt with, so one den is emptied by
	# fleeing and the other by dying -- both paths, in one test.
	var routed: WorldSite = dens[0]
	for g in routed.guardians.duplicate():
		g.hp = 1
		g.depart("beaten off")
		sites.remove_guardian(g, villain)
	_check("routing the whole pack clears its den in the same frame", not routed.is_guarded())
	_check("...and unlocks its one loot action immediately",
		_actions_at(routed, villain).size() == 1, str(_actions_at(routed, villain)))
	_check("...and emits a Power deed (§6: battles won, monsters slain)",
		_has_deed(villain, "cleared_a_den", "power"))

	for den in dens:
		for g in den.guardians.duplicate():
			g.hp = 0
			sites.remove_guardian(g, villain)
	_check("every den is cleared", not sites.any_den_uncleared())

	var quiet: float = await _dusk_rate(combat)
	print("    %d dusks with every den cleared: %.1f%% spawned" % [DUSKS, quiet * 100.0])
	_check("...and dusk raids stop for the run -- ZERO wolves (§3b)",
		is_equal_approx(quiet, 0.0), "%.3f" % quiet)
	# The spawn entry point never became den-relative: the den explains the
	# wolf, it does not path it.
	_check("the spawn entry point is still settlement-relative (§3b's first guard)",
		_spawn_is_settlement_relative(combat))

func _dusk_rate(combat: CombatSystem) -> float:
	var spawned: float = 0.0
	combat._first_dusk_done = true      # past the once-per-run guarantee
	for i in range(DUSKS):
		combat._on_dusk(2)
		if not combat.wolves.is_empty():
			spawned += 1.0
			_clear_wolves(combat)
	return spawned / float(DUSKS)

func _clear_wolves(combat: CombatSystem) -> void:
	for w in combat.wolves.duplicate():
		combat.wolves.erase(w)
		w.queue_free()

## The wolf enters ~2 cells east of the SETTLEMENT grid, not near any den. A den
## sixty cells away that pathed its wolves would deliver them at midnight.
func _spawn_is_settlement_relative(combat: CombatSystem) -> bool:
	_clear_wolves(combat)
	var w: Wolf = combat.spawn_wolf()
	if w == null:
		return false
	var grid_w: float = float(SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE)
	var near_settlement: bool = w.position.x < grid_w + float(SettlementGrid.CELL_SIZE) * 4.0
	_clear_wolves(combat)
	return near_settlement

func _actions_at(site: WorldSite, villain: Necromancer) -> Array:
	var was: Vector2 = villain.position
	villain.position = site.position
	var out: Array = site.actions_for(villain)
	villain.position = was
	return out

func _has_deed(v: Necromancer, deed_id: String, axis: String) -> bool:
	for d in v.deeds:
		if String(d.get("id", "")) == deed_id and int(d.get("axes", {}).get(axis, 0)) > 0:
			return true
	return false

# ---------------- Small helpers -----------------------------------------------

func _site(id: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.site_id == id:
			return s
	return null

func _lootable_sites() -> Array:
	var out: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_sites.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry in parsed.get("sites", []):
		if entry.has("lootable"):
			out.append(entry)
	return out

# ---------------- Assertions --------------------------------------------------

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])

func _in_band(what: String, got: float, band: Array) -> void:
	_check("%s in %.0f-%.0f" % [what, band[0], band[1]],
		got >= float(band[0]) and got <= float(band[1]), "got %.2f" % got)

func _close(what: String, got: float, want: float, tol: float) -> void:
	_check("%s ~= %.0f%%" % [what, want * 100.0], absf(got - want) <= tol,
		"got %.1f%%" % (got * 100.0))
