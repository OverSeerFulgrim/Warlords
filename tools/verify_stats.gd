extends Node
## Verifies the C2 stat rework against `COMBAT_SPEC.md` §2-§4 and the workbook.
##
##   godot --headless --path . res://tools/verify_stats.tscn
##
## A **scene**, not `-s`: everything here reads `RaceCatalog`, and `-s` compiles
## before the autoloads register.
##
## **Kept in the repo.** The rework replaced one stat with nine across combat,
## labor and data, and almost all of it is invisible until a number is wrong:
## an export that silently drops a column, an effective-skill formula that
## truncates instead of flooring, a unit left implementing the retired contract.
## The workbook's own Effective skills sheet is the oracle for the spot checks.

## Straight off the workbook's Attributes sheet, so a bad export fails here
## rather than in a playtest three weeks later.
const EXPECTED_PROFILE := {
	"human_peasant": "Melee", "skeleton_worker": "Melee", "orc": "Melee",
	"hobgoblin": "Melee", "ogre": "Melee", "troll": "Melee",
	"gray_dwarf": "Melee", "kobold": "Ranged", "minotaur": "Melee",
	"mountain_dwarf": "Melee", "gnome": "Arcane", "dark_elf": "Ranged",
	"high_elf": "Arcane", "goblin": "Ranged", "gnoll": "Ranged",
	"halfling": "Ranged", "human_outcast": "Melee",
	"necromancer": "Arcane", "wolf": "Melee",
}

## The workbook's tuned walk speeds. Step 4's gate: these must survive the
## export unchanged, because `measure_travel` is calibrated against them.
const EXPECTED_WALK := {
	"necromancer": 1.0, "skeleton_worker": 0.9, "wolf": 1.3,
	"ogre": 0.8, "gnoll": 1.2, "human_peasant": 1.0,
}

## Spot checks copied from the workbook's **Effective skills** sheet.
const EXPECTED_EFFECTIVE := [
	["gray_dwarf", "mining", 9], ["ogre", "mining", 8],
	["skeleton_worker", "woodcutting", 2], ["orc", "woodcutting", 6],
	["gnoll", "foraging", 10], ["gnome", "research", 9],
	["hobgoblin", "leadership", 8], ["troll", "surgeon", 1],
	["ogre", "foraging", 1], ["high_elf", "surgeon", 8],
	["dark_elf", "scouting", 8], ["halfling", "fishing", 7],
]

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== C2 stat rework (COMBAT_SPEC §2-§4) ===\n")
	_data_is_complete()
	_effective_skills()
	_profiles()
	_damage_pairs()
	_hp_and_carry(main)
	_contract_is_current()
	_no_might_survives()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Every race is fully authored -------------------------------

func _data_is_complete() -> void:
	var ids: Array = RaceCatalog.all_ids()
	_check("races.json has 19 rows (17 races + villain + wolf)", ids.size() == 19,
		"%d rows: %s" % [ids.size(), str(ids)])
	_check("the derivation divisor exported", int(RaceCatalog.derivation().get("divisor", 0)) == 2,
		"got %s" % RaceCatalog.derivation())
	_check("six skill templates exported", RaceCatalog.skill_templates().size() == 6,
		"%d templates" % RaceCatalog.skill_templates().size())
	_check("twelve skills in the governing map", RaceCatalog.all_skill_names().size() == 12,
		"%d skills" % RaceCatalog.all_skill_names().size())

	# One governing attribute per skill, never two (COMBAT_SPEC §2.2).
	for skill in RaceCatalog.all_skill_names():
		var gov: String = RaceCatalog.governing_attribute(skill)
		_check("'%s' is governed by an attribute ('%s')" % [skill, gov], gov != "", "empty")

	for id in ids:
		var attrs: Dictionary = RaceCatalog.attributes(id)
		# The Necromancer's Loyalty is deliberately unauthored -- loyalty to
		# whom? Everything else carries all nine.
		var expected: int = 8 if id == "necromancer" else 9
		_check("%s has %d attributes" % [id, expected], attrs.size() == expected,
			"%d: %s" % [attrs.size(), str(attrs.keys())])
		for key in attrs.keys():
			var v: int = int(attrs[key])
			_check("%s.%s is on the 1-10 scale (%d)" % [id, key, v], v >= 1 and v <= 10, "out of range")

	# Skills: every race resolves all twelve. Creature rows deliberately have
	# none -- a wolf does not mine.
	for id in ids:
		if id in ["necromancer", "wolf"]:
			_check("%s has no labor skills, by design" % id,
				RaceCatalog.skill_baselines(id).is_empty(), "it has some")
			continue
		var skills: Dictionary = RaceCatalog.skill_baselines(id)
		_check("%s resolves 12 skills" % id, skills.size() == 12,
			"%d: %s" % [skills.size(), str(skills.keys())])
		for key in skills.keys():
			var e: int = RaceCatalog.effective_skill_for_race(id, key)
			_check("%s.%s resolves to 1-10 (%d)" % [id, key, e], e >= 1 and e <= 10, "out of range")

# ---------------- The derivation formula -------------------------------------

func _effective_skills() -> void:
	for row in EXPECTED_EFFECTIVE:
		var got: int = RaceCatalog.effective_skill_for_race(row[0], row[1])
		_check("%s %s effective = %d (workbook)" % [row[0], row[1], row[2]],
			got == row[2], "got %d" % got)

	# The formula's own edges, stated rather than inferred from the roster.
	_check("floor is mathematical, not truncating: attr 2 gives -2",
		RaceCatalog.effective_skill(5, 2) == 3, "got %d" % RaceCatalog.effective_skill(5, 2))
	_check("attr 4 gives -1", RaceCatalog.effective_skill(5, 4) == 4,
		"got %d" % RaceCatalog.effective_skill(5, 4))
	_check("attr 5 gives 0", RaceCatalog.effective_skill(5, 5) == 5,
		"got %d" % RaceCatalog.effective_skill(5, 5))
	_check("attr 6 gives 0 (the lumpiness is intended)",
		RaceCatalog.effective_skill(5, 6) == 5, "got %d" % RaceCatalog.effective_skill(5, 6))
	_check("attr 10 gives +2", RaceCatalog.effective_skill(5, 10) == 7,
		"got %d" % RaceCatalog.effective_skill(5, 10))
	_check("clamped at 10", RaceCatalog.effective_skill(10, 10) == 10,
		"got %d" % RaceCatalog.effective_skill(10, 10))
	# Not cosmetic: gather time is 4.0s * 5 / skill, so 0 divides by zero.
	_check("floored at 1, which stops a divide-by-zero in gather time",
		RaceCatalog.effective_skill(1, 1) == 1, "got %d" % RaceCatalog.effective_skill(1, 1))

# ---------------- Profiles fall out of the rule ------------------------------

func _profiles() -> void:
	for id in EXPECTED_PROFILE.keys():
		var a: Dictionary = RaceCatalog.attributes(id)
		var p: Dictionary = Combat.profile_for(
			int(a.get("strength", 5)), int(a.get("dexterity", 5)), int(a.get("intelligence", 5)))
		_check("%s is %s (workbook profile column)" % [id, EXPECTED_PROFILE[id]],
			p["profile"] == EXPECTED_PROFILE[id], "got %s" % p["profile"])

	# The tie rule, which the roster happens not to exercise.
	_check("ties resolve to Strength", Combat.profile_for(6, 6, 6)["profile"] == Combat.PROFILE_MELEE,
		"got %s" % Combat.profile_for(6, 6, 6)["profile"])
	_check("Dex beats an equal Int", Combat.profile_for(1, 6, 6)["profile"] == Combat.PROFILE_RANGED,
		"got %s" % Combat.profile_for(1, 6, 6)["profile"])

	# Walk speeds -- step 4's gate. measure_travel is calibrated against these.
	for id in EXPECTED_WALK.keys():
		var w: float = RaceCatalog.walk_speed(id)
		_check("%s walks at %.2f cells/sec" % [id, EXPECTED_WALK[id]],
			is_equal_approx(w, EXPECTED_WALK[id]), "got %.3f" % w)

# ---------------- damage_roll reads the right pair ---------------------------

## The pair is the point of the whole rework: melee Str-vs-End, ranged
## Dex-vs-Speed, arcane Int-vs-Int. Asserted through the profile dictionary
## rather than by reading damage numbers, because the d3 makes those noisy.
func _damage_pairs() -> void:
	var melee: Dictionary = Combat.profile_for(8, 2, 2)
	_check("melee attacks with Strength", melee["attack_attr"] == 8, "got %s" % melee["attack_attr"])
	_check("melee is defended by Endurance", melee["defence_key"] == "endurance",
		"got %s" % melee["defence_key"])
	var ranged: Dictionary = Combat.profile_for(2, 8, 2)
	_check("ranged attacks with Dexterity", ranged["attack_attr"] == 8, "got %s" % ranged["attack_attr"])
	_check("ranged is defended by Speed", ranged["defence_key"] == "speed",
		"got %s" % ranged["defence_key"])
	var arcane: Dictionary = Combat.profile_for(2, 2, 8)
	_check("arcane attacks with Intelligence", arcane["attack_attr"] == 8, "got %s" % arcane["attack_attr"])
	_check("arcane is defended by Intelligence", arcane["defence_key"] == "intelligence",
		"got %s" % arcane["defence_key"])

	# Reach, which nothing consumes yet but the contract carries.
	_check("melee reaches 1 cell", is_equal_approx(melee["reach_px"], float(SettlementGrid.CELL_SIZE)),
		"got %s" % melee["reach_px"])
	_check("ranged and arcane reach 5 cells",
		is_equal_approx(ranged["reach_px"], 5.0 * float(SettlementGrid.CELL_SIZE))
		and is_equal_approx(arcane["reach_px"], 5.0 * float(SettlementGrid.CELL_SIZE)),
		"got %s / %s" % [ranged["reach_px"], arcane["reach_px"]])

	# The formula itself is unchanged in shape: min 1, and the d3 range.
	var lo: int = 999
	var hi: int = -1
	for i in range(400):
		var d: int = Combat.damage_roll(5, 4)
		lo = mini(lo, d)
		hi = maxi(hi, d)
	# 5 + d3 - floor(4/2) = 5 + (1..3) - 2 = 4..6.
	_check("damage_roll(5, 4) spans 4..6 (attack + d3 - floor(def/2))", lo == 4 and hi == 6,
		"got %d..%d" % [lo, hi])
	_check("MIN_DAMAGE still floors a hopeless swing", Combat.damage_roll(1, 10) >= 1, "got 0")

# ---------------- hp and carry, before and after ------------------------------

## Step 5's promise: the roster was authored so no shipped number moves. These
## are the three that would be noticed immediately.
func _hp_and_carry(main) -> void:
	var worker = null
	for w in main.worker_system.workers:
		worker = w
		break
	_check("a skeleton worker exists", worker != null, "none on the roster")
	if worker != null:
		_check("skeleton hp is still 16 (End 4)", worker.max_hp() == 16, "got %d" % worker.max_hp())
		_check("skeleton carries 4 (End 4)", worker.carry_capacity() == 4,
			"got %d" % worker.carry_capacity())
		_check("skeleton walks at 0.9", is_equal_approx(worker.walk_speed, 0.9),
			"got %.3f" % worker.walk_speed)
		_check("skeleton is Melee", worker.combat_profile()["profile"] == Combat.PROFILE_MELEE,
			"got %s" % worker.combat_profile()["profile"])

	var villain: Necromancer = main.villain
	_check("villain hp is still 20 (End 6)", villain.max_hp() == 20, "got %d" % villain.max_hp())
	_check("villain carries 6 (End 6)", villain.carry_capacity() == 6,
		"got %d" % villain.carry_capacity())
	_check("villain is Arcane, by the rule and not a special case",
		villain.combat_profile()["profile"] == Combat.PROFILE_ARCANE,
		"got %s" % villain.combat_profile()["profile"])
	_check("villain attacks with Intelligence 7",
		villain.combat_profile()["attack_attr"] == 7,
		"got %s" % villain.combat_profile()["attack_attr"])

	var wolf: Wolf = main.combat_system.spawn_wolf(villain.position + Vector2(600.0, 0.0))
	_check("a wolf spawned", wolf != null, "spawn_wolf returned null")
	if wolf != null:
		_check("wolf hp is still 18 (End 5)", wolf.max_hp() == 18, "got %d" % wolf.max_hp())
		_check("wolf is Melee", wolf.combat_profile()["profile"] == Combat.PROFILE_MELEE,
			"got %s" % wolf.combat_profile()["profile"])
		_check("wolf Intelligence is 2 -- the arcane-vs-beast knob",
			wolf.combat_defence("intelligence") == 2, "got %d" % wolf.combat_defence("intelligence"))
		# COMBAT_SPEC §7: Speed 8 -> 1.3 cells/sec, up from the hand-set 78 px/s.
		_check("wolf chase speed derives from Speed 8 (83 px/s)",
			is_equal_approx(wolf.chase_speed_px(), 1.3 * float(SettlementGrid.CELL_SIZE)),
			"got %.1f" % wolf.chase_speed_px())
		wolf.depart("test over")

# ---------------- The contract is current ------------------------------------

## `Combat.is_combatant()` exists to make a half-migrated unit fail loudly. It
## can only do that job if its method list moved with the contract -- so this
## asserts it rejects exactly the shape the rework retired.
func _contract_is_current() -> void:
	_check("is_combatant rejects null", not Combat.is_combatant(null))
	_check("is_combatant rejects a unit still implementing only combat_might()",
		not Combat.is_combatant(_LegacyCombatant.new()),
		"the retired contract still passes -- a half-migrated unit would fight silently wrong")
	_check("is_combatant accepts the widened contract",
		Combat.is_combatant(_ModernCombatant.new()), "the current contract fails")

## The C1 shape, kept here and nowhere else, purely so the check above has
## something authentic to reject.
class _LegacyCombatant:
	var hp: int = 10
	func combat_name() -> String: return "legacy"
	func combat_might() -> int: return 5
	func max_hp() -> int: return 10
	func take_damage(n: int) -> int: return n
	func is_alive() -> bool: return true
	func hp_fraction() -> float: return 1.0

class _ModernCombatant:
	var hp: int = 10
	func combat_name() -> String: return "modern"
	func combat_profile() -> Dictionary: return Combat.profile_for(5, 1, 1)
	func combat_defence(_key: String) -> int: return 5
	func max_hp() -> int: return 10
	func take_damage(n: int) -> int: return n
	func is_alive() -> bool: return true
	func hp_fraction() -> float: return 1.0

# ---------------- Nothing named Might survives -------------------------------

## Step 7's grep, as an assertion.
##
## Comments **and string literals** are stripped first, and both exclusions earn
## their place: several headers legitimately explain what Might used to be and
## why it went, which is history worth keeping, and ThreatSystem's escalation
## flavor text contains the ordinary English "a witch hunter might sniff
## around". What is being asserted is that no *identifier* named might or
## influence survives.
func _no_might_survives() -> void:
	var offenders: Array = []
	for path in _all_scripts("res://scripts"):
		var code: String = _strip_strings(_strip_comments(FileAccess.get_file_as_string(path)))
		for banned in ["might", "influence"]:
			if code.to_lower().contains(banned):
				offenders.append("%s (%s)" % [path.get_file(), banned])
	_check("no live code mentions might or influence", offenders.is_empty(),
		str(offenders))

	# The data half of the same sweep.
	for path in ["res://data/races.json", "res://data/recruitment.json",
			"res://data/missions.json"]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		_check("%s has no \"might\" key" % path.get_file(),
			not text.contains("\"might\""), "it does")

func _all_scripts(dir: String) -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_all_scripts(dir + "/" + d))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	return out

## Double-quoted literals only -- GDScript has no single-quoted alternative in
## this codebase, and this is enough for a source sweep.
##
## Split-and-rejoin rather than a character loop: appending to a String one
## character at a time is quadratic in GDScript, and the first version of this
## took Main.gd's 80KB past a ten-minute timeout. Odd-indexed segments are the
## insides of the quotes.
func _strip_strings(src: String) -> String:
	var parts: PackedStringArray = src.split("\"")
	var kept: PackedStringArray = PackedStringArray()
	for i in range(parts.size()):
		if i % 2 == 0:
			kept.append(parts[i])
	return " ".join(kept)

func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var i: int = line.find("#")
		out += (line if i < 0 else line.substr(0, i)) + "\n"
	return out

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
