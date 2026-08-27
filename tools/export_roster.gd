extends Node
## Exports `docs/design/stat_rework_roster.xlsx` into `data/races.json`.
##
##   godot --headless --path . res://tools/export_roster.tscn
##
## **The workbook is the editing surface; this JSON is derived.** That is the
## whole point of committing this tool: COMBAT_SPEC §12 step 5 says templates
## and overrides live in the JSON rather than in code, and the Legend sheet's
## order-of-work ends with "export to data/races.json". Hand-editing the stat
## blocks in `races.json` puts the two out of sync silently, and the workbook is
## the one with the formulas that keep 153 attributes and 204 skills coherent.
##
## It reads the `.xlsx` **directly** -- a workbook is a zip of XML, so
## `ZIPReader` plus a little parsing gets there with no conversion step and no
## second copy of the numbers to drift. Re-authoring a race is: edit the
## workbook, run this, commit both.
##
## ## What it owns, and what it leaves alone
##
## Owned (overwritten every run): `attributes`, `skill_template`,
## `skill_overrides`, `walk_speed`, `category`, `alignment`, `rarity`, plus the
## `_skill_templates` / `_governing_attribute` / `_derivation` blocks.
##
## Left alone (merged forward from the existing file): `display_name`, `sprite`,
## `recruitable`, `food_per_meal`, `housing_style`, `housing_note`, `rivalries`
## and every `_comment*`. None of those are in the workbook and none of them are
## this tool's business -- art paths and housing rules are not stats.
##
## A **scene**, not `-s`: `-s` compiles before the autoloads register.

const WORKBOOK := "res://docs/design/stat_rework_roster.xlsx"
const OUT_PATH := "res://data/races.json"

## Sheet file names inside the zip, in workbook order.
const SHEET_ATTRIBUTES := "xl/worksheets/sheet1.xml"
const SHEET_TEMPLATES := "xl/worksheets/sheet2.xml"
const SHEET_RACE_SKILLS := "xl/worksheets/sheet3.xml"

## Column layout, 1-indexed, as the sheets are actually laid out. Read once here
## rather than scattered through the parse so a workbook edit that inserts a
## column is a change in one place.
const ATTR_FIRST_COL := 5      # Strength
const ATTR_WALK_DIVISOR := Vector2i(18, 2)   # col, row
const TEMPLATE_FIRST_COL := 2
const RACE_SKILL_FIRST_COL := 3
const HEADER_ROW := 4

## The nine, in workbook column order. Lower-cased keys are what the game reads.
const ATTRIBUTE_KEYS := ["strength", "dexterity", "speed", "endurance",
	"intelligence", "guile", "perception", "tact", "loyalty"]

## The twelve, in workbook column order.
const SKILL_KEYS := ["woodcutting", "mining", "foraging", "hunting", "fishing",
	"crafting", "trapper", "scouting", "mercantile", "research", "surgeon",
	"leadership"]

## Workbook race labels -> the ids already used in races.json. The workbook is
## written for a designer and the JSON for the loader; this is the one place
## the two vocabularies meet.
const ID_FOR_LABEL := {
	"Human Peasant (ref)": "human_peasant",
	"Skeleton Worker": "skeleton_worker",
	"Orc": "orc",
	"Hobgoblin": "hobgoblin",
	"Ogre": "ogre",
	"Troll": "troll",
	"Gray Dwarf": "gray_dwarf",
	"Kobold": "kobold",
	"Minotaur": "minotaur",
	"Mountain Dwarf": "mountain_dwarf",
	"Gnome": "gnome",
	"Dark Elf": "dark_elf",
	"High Elf": "high_elf",
	"Goblin": "goblin",
	"Gnoll": "gnoll",
	"Halfling": "halfling",
	"Human Outcast": "human_outcast",
	"The Necromancer": "necromancer",
	"Wolf": "wolf",
}

## Rows that are units but not recruitable races. They carry the same nine
## attributes (COMBAT_SPEC amendment 2026-08-06, note 4) and no labor skills --
## a wolf does not mine. They land in the same file so one lookup answers "what
## are this thing's attributes" for every combatant on the map.
const NON_RACE_IDS := ["necromancer", "wolf"]

var _shared: PackedStringArray = PackedStringArray()
var _zip: ZIPReader = null

func _ready() -> void:
	var ok := _run()
	get_tree().quit(0 if ok else 1)

func _run() -> bool:
	_zip = ZIPReader.new()
	if _zip.open(WORKBOOK) != OK:
		push_error("export_roster: cannot open %s" % WORKBOOK)
		return false
	_shared = _read_shared_strings()
	print("export_roster: %d shared strings" % _shared.size())

	var attributes: Dictionary = _sheet_grid(SHEET_ATTRIBUTES)
	var templates_grid: Dictionary = _sheet_grid(SHEET_TEMPLATES)
	var race_skills: Dictionary = _sheet_grid(SHEET_RACE_SKILLS)
	# Before the close, not after: the divisor lives on a fourth sheet, and
	# reading it from a shut zip is a warning plus a silent fallback -- which
	# would export a different balance knob than the workbook shows.
	var divisor: int = _derivation_divisor()
	_zip.close()
	var walk_divisor: float = float(_num(attributes, ATTR_WALK_DIVISOR.y, ATTR_WALK_DIVISOR.x))
	if walk_divisor <= 0.0:
		push_error("export_roster: walk divisor missing or zero")
		return false

	var templates: Dictionary = _read_templates(templates_grid)
	var governing: Dictionary = _read_governing(templates_grid)
	if templates.is_empty() or governing.size() != SKILL_KEYS.size():
		push_error("export_roster: templates/governing map incomplete")
		return false

	var existing: Dictionary = _read_existing()
	var out: Dictionary = {}
	# Documentation keys first, so the file still reads top-down.
	for key in existing.keys():
		if key.begins_with("_"):
			out[key] = existing[key]
	out["_generated_by"] = "tools/export_roster.gd from docs/design/stat_rework_roster.xlsx -- do not hand-edit the stat blocks"
	out["_derivation"] = {
		"formula": "effective_skill = clamp(skill + floor((governing_attribute - 5) / divisor), min, max)",
		"divisor": divisor,
		"min": 1,
		"max": 10,
	}
	out["_governing_attribute"] = governing
	out["_skill_templates"] = templates

	var written: int = 0
	var creatures: int = 0
	for row in range(HEADER_ROW + 1, 200):
		var label: String = _str(attributes, row, 1)
		if label == "":
			continue
		if not ID_FOR_LABEL.has(label):
			continue
		var id: String = ID_FOR_LABEL[label]
		var entry: Dictionary = (existing.get(id, {}) as Dictionary).duplicate(true)
		entry["display_name"] = entry.get("display_name", label)
		entry["category"] = _str(attributes, row, 2)
		entry["alignment"] = _str(attributes, row, 3)
		entry["rarity"] = _str(attributes, row, 4)

		var attrs: Dictionary = {}
		for i in range(ATTRIBUTE_KEYS.size()):
			var raw: String = _str(attributes, row, ATTR_FIRST_COL + i)
			# The Necromancer's Loyalty is authored as an em-dash: loyalty to
			# whom? Kept out of the block entirely rather than faked as a
			# number, so anything reading it has to decide what that means.
			if raw == "" or raw == "—" or raw == "-":
				continue
			attrs[ATTRIBUTE_KEYS[i]] = int(raw)
		entry["attributes"] = attrs

		# Walk speed is derived, not copied: the workbook shows it as a formula
		# of Speed, and re-deriving here means the JSON cannot disagree with the
		# attribute it came from.
		entry["walk_speed"] = snappedf(
			1.0 + float(attrs.get("speed", 5) - 5) / walk_divisor, 0.01)

		if id in NON_RACE_IDS:
			entry.erase("skill_template")
			entry.erase("skill_overrides")
			entry.erase("labor")
			entry.erase("stats")
			creatures += 1
		else:
			var srow: int = _find_row(race_skills, label)
			if srow < 0:
				push_error("export_roster: '%s' has no Race skills row" % label)
				return false
			var tname: String = _str(race_skills, srow, 2)
			if not templates.has(tname):
				push_error("export_roster: '%s' uses unknown template '%s'" % [label, tname])
				return false
			entry["skill_template"] = tname
			# Only what actually differs from the template is written out. That
			# is the workbook's own shape (its shaded cells) and it keeps a
			# template edit moving every race that did not opt out.
			var overrides: Dictionary = {}
			for i in range(SKILL_KEYS.size()):
				var v: int = _num(race_skills, srow, RACE_SKILL_FIRST_COL + i)
				if v != int(templates[tname][SKILL_KEYS[i]]):
					overrides[SKILL_KEYS[i]] = v
			entry["skill_overrides"] = overrides
			# The retired four-stat model. Erased rather than left to rot: a
			# stale `might` alongside live `attributes` is exactly the kind of
			# half-migration Combat.is_combatant() exists to catch.
			entry.erase("stats")
			entry.erase("labor")
			written += 1
		out[id] = entry

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("export_roster: cannot write %s" % OUT_PATH)
		return false
	f.store_string(JSON.stringify(out, "  ") + "\n")
	f.close()
	print("export_roster: wrote %s -- %d races, %d creature/villain rows, %d templates, divisor /%d"
		% [OUT_PATH, written, creatures, templates.size(), divisor])
	return true

# ---------------- Workbook reading -------------------------------------------

## The divisor lives on the Effective skills sheet, which is otherwise entirely
## formulas. Must be called before the zip is closed; falls back to COMBAT_SPEC
## §2.3's stated /2 only if the cell itself is unreadable.
func _derivation_divisor() -> int:
	var grid: Dictionary = _sheet_grid("xl/worksheets/sheet4.xml")
	var v: int = _num(grid, 3, 2)
	return v if v > 0 else 2

func _read_templates(grid: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for row in range(HEADER_ROW + 1, 40):
		var name: String = _str(grid, row, 1)
		if name == "" or name.begins_with("Governing"):
			continue
		if name == "governed by":
			break
		var skills: Dictionary = {}
		for i in range(SKILL_KEYS.size()):
			skills[SKILL_KEYS[i]] = _num(grid, row, TEMPLATE_FIRST_COL + i)
		out[name] = skills
	return out

## The one-governing-attribute-per-skill map (COMBAT_SPEC §2.2). Exported rather
## than hardcoded so the "one each, never two" rule stays a data fact.
func _read_governing(grid: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var row: int = _find_row(grid, "governed by")
	if row < 0:
		return out
	for i in range(SKILL_KEYS.size()):
		out[SKILL_KEYS[i]] = _str(grid, row, TEMPLATE_FIRST_COL + i).to_lower()
	return out

func _read_existing() -> Dictionary:
	if not FileAccess.file_exists(OUT_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OUT_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _find_row(grid: Dictionary, label: String) -> int:
	for row in grid.keys():
		if _str(grid, row, 1) == label:
			return row
	return -1

# ---------------- xlsx internals ---------------------------------------------
#
# A worksheet is `<row r="N"><c r="A1" t="s"><v>12</v></c>...</row>`, where
# `t="s"` means the value is an index into sharedStrings.xml rather than a
# number. Parsed row-by-row rather than by scanning for `<c>` across the whole
# file, so a cell can never be filed under the wrong row.

func _read_shared_strings() -> PackedStringArray:
	var out := PackedStringArray()
	var xml: String = _zip.read_file("xl/sharedStrings.xml").get_string_from_utf8()
	var si := RegEx.create_from_string("<si>(.*?)</si>")
	var t := RegEx.create_from_string("<t[^>]*>(.*?)</t>")
	for m in si.search_all(xml):
		var text := ""
		for tm in t.search_all(m.get_string(1)):
			text += tm.get_string(1)
		out.append(_unescape(text))
	return out

## `{row: {col: String}}`, 1-indexed, only for cells that carry a value.
func _sheet_grid(path: String) -> Dictionary:
	var xml: String = _zip.read_file(path).get_string_from_utf8()
	var row_re := RegEx.create_from_string("<row[^>]*?\\br=\"(\\d+)\"[^>]*>(.*?)</row>")
	var cell_re := RegEx.create_from_string("<c\\b([^>]*?)(?:/>|>(.*?)</c>)")
	var ref_re := RegEx.create_from_string("\\br=\"([A-Z]+)\\d+\"")
	var type_re := RegEx.create_from_string("\\bt=\"([^\"]+)\"")
	var v_re := RegEx.create_from_string("<v>(.*?)</v>")
	var t_re := RegEx.create_from_string("<t[^>]*>(.*?)</t>")
	var grid: Dictionary = {}
	for rm in row_re.search_all(xml):
		var row: int = int(rm.get_string(1))
		var cells: Dictionary = {}
		for cm in cell_re.search_all(rm.get_string(2)):
			var attrs: String = cm.get_string(1)
			var body: String = cm.get_string(2)
			var ref := ref_re.search(attrs)
			if ref == null:
				continue
			var col: int = _col_index(ref.get_string(1))
			var tm := type_re.search(attrs)
			var type: String = tm.get_string(1) if tm != null else "n"
			var value := ""
			if type == "inlineStr":
				for im in t_re.search_all(body):
					value += im.get_string(1)
				value = _unescape(value)
			else:
				var vm := v_re.search(body)
				if vm != null:
					value = vm.get_string(1)
					if type == "s":
						var idx: int = int(value)
						value = _shared[idx] if idx >= 0 and idx < _shared.size() else ""
					else:
						value = _unescape(value)
			cells[col] = value
		grid[row] = cells
	return grid

## "A" -> 1, "AA" -> 27.
func _col_index(letters: String) -> int:
	var n: int = 0
	for i in range(letters.length()):
		n = n * 26 + (letters.unicode_at(i) - 64)
	return n

func _str(grid: Dictionary, row: int, col: int) -> String:
	return String((grid.get(row, {}) as Dictionary).get(col, "")).strip_edges()

func _num(grid: Dictionary, row: int, col: int) -> int:
	var s: String = _str(grid, row, col)
	return int(s) if s.is_valid_float() else 0

## `&amp;` last: unescaping it first would turn `&amp;lt;` into `<`.
func _unescape(s: String) -> String:
	s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
	s = s.replace("&apos;", "'").replace("&#39;", "'")
	return s.replace("&amp;", "&")
