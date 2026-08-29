extends Node2D
class_name WorldSite
## A fixed thing standing in the world: a village building, the sealed ritual
## ground, a roadside landmark -- and, since R2a, anything with loot in it.
##
## **Deliberately not a `Building`.** `Building` is a settlement citizen -- it
## has a cost, a catalog entry, a power value, a grid cell, and it emits
## `building_placed`. None of that is true of somebody else's house. A world
## site is a sprite, a position, and an inspection payload; giving it the
## settlement's machinery would mean the player's Power score counted the human
## lord's manor.
##
## Everything it says comes from `data/world_sites.json`, so adding a hamlet is
## a data edit. It implements `get_inspect_data()`, which is the whole contract
## for being clickable (see InspectionPanel.gd).
##
## ## Loot state lives here, on the node
##
## `LOOT_SITES_SPEC.md` section 9 puts charges, choice flags, the remainder and
## the channel timer **on the node**, following the `ResourceNode` precedent:
## its position and appearance *are* its gameplay content, so splitting data
## from view would leave two objects that must agree about a sprite swap.
##
## The documented split trigger is the same wording as the `Laborer` one, and it
## is worth stating because the last two drifts in this project came from
## missing it: **the moment any off-map system needs site state, this splits
## into data + view.** A bounty party that has to know whether the crypt is
## still full, or an R5 save file that has to write the remainder down, is that
## moment. Until then one object is the honest model.
##
## ## The channel is a delta accumulator
##
## Per CLAUDE.md: never `Time.get_ticks_msec()` for gameplay. Looting inherits
## the debug time scale like everything else, which is what makes a 12-second
## crypt pull testable at 60x.

# ---------------- Identity (unchanged from R1) --------------------------------

var site_id: String = ""
var display_name: String = "Ruin"
var subtitle: String = ""
var description: String = ""
var detail_rows: Array = []
var sprite_path: String = ""
## Radius in pixels for click selection, derived from the drawn size.
var pick_radius: float = 32.0

var _sprite: Sprite2D

# ---------------- The lootable block (LOOT_SITES_SPEC section 8) --------------

var lootable: bool = false
var loot_type: String = ""
var band: int = 2
var charges_max: int = 1
var charges_left: int = 0
var channel_seconds: float = 8.0
var loot_table: String = ""
var choices_id: String = ""
var looted_sprite_path: String = ""
## `null`, or `{"kind": String, "count": int}`. A bare string in older drafts
## reads as `{kind, count: 1}` at load, so nothing already written reopens.
var guardian_spec: Dictionary = {}

## The multi-charge sites' own risk (section 2's Risk column): the ruin rolls a
## guardian on **each pull**, and the battlefield's odds **rise per pull**. It is
## still telegraphed rather than a surprise -- the site's details row says so
## before the first pull, which is what section 1.3 asks for.
var guardian_roll: Dictionary = {}
var pulls_taken: int = 0
## Set by `WorldSites`, which owns guardian lifecycle. A Callable rather than a
## back-reference so the site still cannot reach into its container.
var guardian_spawner: Callable = Callable()
## `{"threat": int, "escalates": bool}`. The escalation half of the 2026-08-06
## reputation-ownership decision: notice is world state and goes to
## `GameState.add_threat()`. The reputation half is the villain's deed ledger.
var notice: Dictionary = {}
var signposted: bool = false
## Specified now, honoured in R4 (section 8) -- the shuffle needs somewhere to
## write, and reopening the schema then would be the expensive version.
var pool_id: String = ""
var active_count: int = 1

# ---------------- Run state ---------------------------------------------------

## What did not fit in his hands and stayed here (`SORTIE_SPEC.md` section 4).
## **Not a ground pile**: the site is already a container, and a dropped-loot
## entity on a 144x144 map is a second inventory system and an R5 save problem.
var remainder: Dictionary = {}
var relic_remainder: Array = []

## Guardians posted here. Owned and freed by `WorldSites`; mirrored so the site
## can answer "am I still guarded" without anyone reaching across.
var guardians: Array = []
var cleared: bool = true

## How many graves have been disturbed here, for the escalating-notice curve.
var graves_disturbed: int = 0
var _conceals: int = 0

## The grave currently open, when this site offers the four-way sheet. One
## grave at a time: a charge is spent when the grave is *finished*, which is
## what makes raise-then-steal one grave and two acts rather than two graves.
var _grave := {"raised": false, "taken": false, "returned": false, "concealed": false}

## Set by `WorldSites` so a deed can be stamped with the game day without the
## site reaching up for a `DayNightCycle`. Same pattern as `Minimap.units_source`.
var day_provider: Callable = Callable()

# ---------------- The channel -------------------------------------------------

var _channel_left: float = 0.0
var _channel_total: float = 0.0
var _channel_action: String = ""
var _channel_label: String = ""
var _channel_villain = null
var _channel_from: Vector2 = Vector2.ZERO

## How far he may drift before the channel breaks. "Moving cancels" taken
## literally: this is about one frame's stride at walking pace, so a keypress
## ends it and standing still does not.
const CHANNEL_BREAK_PX: float = 8.0

## `size_px` is a **canvas width**, and is deliberately the last place in the
## project that still means that.
##
## Everything on the settlement layer moved to content-height targeting (see
## `Anchoring.scale_for_content_height`), because a canvas width described the
## picture rather than the thing drawn on it. The world map has not, on purpose:
## its sizes are per-entry numbers in `data/world_sites.json`, hand-tuned
## against the R1c travel-time bands, and the rule change is not size-neutral --
## the Kenney tower art puts 310px of tower on a 320px-tall canvas but only
## 100px across, so `"size": 88` currently draws a 213px tower and would become
## an 88px one. Converting means re-tuning every value and re-verifying the
## world map, which is its own pass rather than a side effect of this one.
## `Patrol.TOKEN_SIZE` is held back for the same reason -- patrols and sites
## share a screen, and half-converting it would be worse than not converting it.
##
## **The looted sprite inherits that rule**, which is why
## `check_sprite_scales.tscn` asserts a looted sprite shares its unlooted
## partner's canvas size: under canvas-width scaling, swapping in art on a
## different canvas silently resizes the site.
func setup(data: Dictionary, world_position: Vector2, size_px: float) -> void:
	site_id = String(data.get("id", ""))
	display_name = String(data.get("name", "Ruin"))
	subtitle = String(data.get("subtitle", ""))
	description = String(data.get("description", ""))
	detail_rows = data.get("details", [])
	sprite_path = String(data.get("sprite", ""))
	signposted = bool(data.get("signposted", false))
	position = world_position
	pick_radius = maxf(18.0, size_px * 0.6)

	if data.has("lootable"):
		_setup_lootable(data["lootable"])

	_sprite = Sprite2D.new()
	_sprite.centered = true
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex: Texture2D = load(sprite_path)
		_sprite.texture = tex
		if tex.get_size().x > 0.0:
			_sprite.scale = Vector2.ONE * (size_px / tex.get_size().x)
	else:
		push_warning("WorldSite '%s': sprite not found at %s" % [site_id, sprite_path])
	if data.has("modulate"):
		_sprite.modulate = Color(String(data["modulate"]))
	add_child(_sprite)
	# A house stands on the ground at its position, like everything else. At
	# village sizes a centred sprite buries the lower half of the building.
	Anchoring.foot(_sprite)
	# Under the units (workers are z 0, the villain 5, the wolf 6) but over
	# terrain: a patrol walking past a house should pass in front of it.
	z_index = -1
	set_process(lootable)

func _setup_lootable(block: Dictionary) -> void:
	lootable = true
	loot_type = String(block.get("type", ""))
	band = int(block.get("band", 2))
	charges_max = maxi(1, int(block.get("charges", 1)))
	charges_left = charges_max
	channel_seconds = float(block.get("channel_seconds", 8.0))
	loot_table = String(block.get("loot_table", ""))
	choices_id = String(block.get("choices", ""))
	looted_sprite_path = String(block.get("looted_sprite", ""))
	notice = block.get("notice", {})
	pool_id = String(block.get("pool", ""))
	active_count = int(block.get("active_count", 1))
	guardian_roll = block.get("guardian_roll", {})
	var g: Variant = block.get("guardian", null)
	if typeof(g) == TYPE_STRING and String(g) != "":
		guardian_spec = {"kind": String(g), "count": 1}
	elif typeof(g) == TYPE_DICTIONARY and not (g as Dictionary).is_empty():
		guardian_spec = {"kind": String(g.get("kind", "")), "count": maxi(1, int(g.get("count", 1)))}
	cleared = guardian_spec.is_empty()

func hit_radius() -> float:
	return pick_radius

## Reach: touching distance, defaulting to the pick radius (section 3). No
## remote looting -- his physical presence is the point.
func interact_radius() -> float:
	return pick_radius

func in_reach(villain) -> bool:
	return villain != null and villain.position.distance_to(position) <= interact_radius()

# ---------------- State questions --------------------------------------------

func is_guarded() -> bool:
	return not cleared

func has_remainder() -> bool:
	return not remainder.is_empty() or not relic_remainder.is_empty()

## Spent means spent for the run (section 3). A site with a remainder is **not**
## spent: it keeps its actions and its unlooted sprite, because walking home to
## empty your hands and coming back is a legitimate, time-taxed play.
func is_spent() -> bool:
	return lootable and charges_left <= 0 and not has_remainder()

func is_channelling() -> bool:
	return _channel_left > 0.0

func channel_progress() -> float:
	if _channel_total <= 0.0:
		return 0.0
	return clampf(1.0 - _channel_left / _channel_total, 0.0, 1.0)

func is_den() -> bool:
	return loot_type == "wolf_den"

# ---------------- Actions -----------------------------------------------------

## What the inspection panel should offer, in order. Each entry is
## `{id, label, blurb, seconds, enabled, reason}` -- the *panel* renders it, so
## a disabled row can still say why, which is what section 1.3's "the panel says
## what class of trouble it carries before the player commits" needs.
##
## Nothing here mutates. `begin_action()` is the only door.
func actions_for(villain) -> Array:
	var out: Array = []
	if not lootable:
		return out
	if is_guarded():
		return out
	if has_remainder():
		out.append({
			"id": "collect", "label": "Collect what you left",
			"blurb": "Still here: %s." % _remainder_label(),
			"seconds": 0.0, "enabled": true, "reason": "",
		})
	if charges_left <= 0:
		return out
	if choices_id != "" and LootCatalog.has_choice_sheet(choices_id):
		out.append({
			"id": "open_sheet", "label": _sheet_label(),
			"blurb": String(LootCatalog.choice_sheet(choices_id).get("prompt", "")),
			"seconds": 0.0, "enabled": true, "reason": "",
		})
		return out
	out.append({
		"id": "loot", "label": _loot_label(),
		"blurb": "%.0f seconds, standing still." % channel_time_for(villain, []),
		"seconds": channel_time_for(villain, []), "enabled": true, "reason": "",
	})
	return out

func _sheet_label() -> String:
	if charges_max > 1:
		return "Open a grave  (%d of %d left)" % [charges_left, charges_max]
	return "Open the grave"

func _loot_label() -> String:
	if charges_max > 1:
		return "Search it  (%d pull%s left)" % [charges_left, "" if charges_left == 1 else "s"]
	return "Loot it"

## Which choices of the sheet are offered right now, and why the others are not.
## The gating **is** the dilemma (section 4): return-the-belongings is only ever
## offered while the valuables are intact, so mercy forecloses profit
## permanently; destroy-the-evidence only appears once something has been taken.
func sheet_choices(villain) -> Array:
	var sheet: Dictionary = LootCatalog.choice_sheet(choices_id)
	var out: Array = []
	for choice in sheet.get("choices", []):
		var ok: bool = true
		for token in choice.get("requires", []):
			match String(token):
				"corpse":
					ok = ok and not _grave["raised"] and not _grave["returned"]
				"valuables":
					ok = ok and not _grave["taken"] and not _grave["returned"]
				"disturbed":
					ok = ok and (_grave["raised"] or _grave["taken"]) and not _grave["concealed"]
				_:
					push_warning("WorldSite '%s': unknown requires token '%s'" % [site_id, token])
		if ok:
			out.append(choice)
	return out

## Seconds this action will take him, after the relics he has banked. The
## Sexton's Ring is a channel multiplier tagged `grave`, so a relic that makes
## grave work faster needs data and no code (section 7).
func channel_time_for(villain, tags: Array, override_seconds: float = -1.0) -> float:
	var base: float = channel_seconds if override_seconds < 0.0 else override_seconds
	if villain != null and villain.has_method("channel_multiplier"):
		base *= villain.channel_multiplier(tags)
	return maxf(0.1, base)

# ---------------- Beginning and cancelling ------------------------------------

## Starts an action. `choice` is the sheet entry for `open_sheet` resolutions
## and `{}` otherwise. Returns false if the action is not currently available --
## the caller does not get to bypass the gate by knowing an id.
func begin_action(villain, action_id: String, choice: Dictionary = {}) -> bool:
	if not lootable or villain == null or not in_reach(villain):
		return false
	if is_guarded():
		return false
	if is_channelling():
		return false

	if action_id == "collect":
		_collect_remainder(villain)
		return true

	var seconds: float = 0.0
	var label: String = ""
	if action_id == "choice":
		if choice.is_empty():
			return false
		seconds = channel_time_for(villain, choice.get("channel_tags", []),
			float(choice.get("channel_seconds", channel_seconds)))
		label = String(choice.get("label", "Working"))
	elif action_id == "loot":
		if charges_left <= 0:
			return false
		seconds = channel_time_for(villain, [])
		label = _loot_label()
	else:
		return false

	_channel_action = action_id
	_channel_label = label
	_channel_villain = villain
	_channel_from = villain.position
	_channel_total = seconds
	_channel_left = seconds
	_pending_choice = choice
	if villain.has_method("set_channelling"):
		villain.set_channelling(true)
	return true

var _pending_choice: Dictionary = {}

## Moving cancels and refunds nothing (section 3). Also called by `WorldSites`
## when a guardian wakes up mid-pull, which is the crypt's whole personality.
func cancel_channel(reason: String) -> void:
	if not is_channelling():
		return
	var villain = _channel_villain
	_clear_channel()
	if villain != null and villain.has_method("set_channelling"):
		villain.set_channelling(false)
	EventBus.travel_noted.emit("%s — interrupted (%s)." % [display_name, reason], 0.0)

func _clear_channel() -> void:
	_channel_left = 0.0
	_channel_total = 0.0
	_channel_action = ""
	_channel_label = ""
	_channel_villain = null
	_pending_choice = {}

func _process(delta: float) -> void:
	if not is_channelling():
		return
	var villain = _channel_villain
	if villain == null or not villain.is_alive() or not in_reach(villain):
		cancel_channel("he walked away")
		return
	if villain.position.distance_to(_channel_from) > CHANNEL_BREAK_PX:
		cancel_channel("he moved")
		return
	# A delta accumulator, so `Engine.time_scale` scales looting along with
	# every other clock in the project (CLAUDE.md).
	_channel_left -= delta
	if _channel_left > 0.0:
		return
	var action: String = _channel_action
	var choice: Dictionary = _pending_choice
	_clear_channel()
	if villain.has_method("set_channelling"):
		villain.set_channelling(false)
	if action == "choice":
		_resolve_choice(villain, choice)
	else:
		_resolve_loot(villain, 1.0, "loot_the_site", {"wealth": 1}, 1.0)

# ---------------- Resolution --------------------------------------------------

func _day() -> int:
	return int(day_provider.call()) if day_provider.is_valid() else 1

## The one place loot moves from a table into his hands. Everything rolls
## through `Necromancer.add_carried()` and **respects its return value**: what
## does not fit stays here as a remainder charge (section 5), which is the rule
## the whole "one more grave, or turn back?" question is built on.
func _resolve_loot(villain, fraction: float, deed_id: String, axes: Dictionary,
		notice_mult: float) -> void:
	var rolled: Dictionary = LootCatalog.roll(loot_table, villain.drawn_relic_ids(), fraction)
	var taken := {}
	var left := {}
	for kind in rolled["resources"].keys():
		var amount: int = int(rolled["resources"][kind])
		var got: int = villain.add_carried(kind, amount)
		if got > 0:
			taken[kind] = got
		if amount - got > 0:
			left[kind] = amount - got
	for id in rolled["relics"]:
		if villain.add_relic(id):
			EventBus.relic_found.emit(villain, id)
		else:
			relic_remainder.append(id)
	for kind in left.keys():
		remainder[kind] = int(remainder.get(kind, 0)) + int(left[kind])

	charges_left = maxi(0, charges_left - 1)
	pulls_taken += 1
	_apply_notice(villain, notice_mult)
	if deed_id != "":
		villain.record_deed(deed_id, axes, _day())
	_refresh_sprite()
	EventBus.site_looted.emit(villain, self, taken)
	_roll_guardian(villain)

## The per-pull guardian roll. Rolled **after** the loot has landed in his
## hands, deliberately: the pull pays out and *then* something objects, which is
## the sequence that makes "one more pull?" a real question rather than a coin
## flip you lose before you win anything.
func _roll_guardian(villain) -> void:
	if guardian_roll.is_empty() or is_guarded() or not guardian_spawner.is_valid():
		return
	var chance: float = float(guardian_roll.get("chance", 0.0))
	if bool(guardian_roll.get("escalates", false)):
		chance *= float(maxi(1, pulls_taken))
	if randf() > chance:
		return
	guardian_spawner.call(self, String(guardian_roll.get("kind", "")),
		maxi(1, int(guardian_roll.get("count", 1))))
	EventBus.site_guardian_engaged.emit(villain, self)

## The four-way sheet, resolved (section 4).
func _resolve_choice(villain, choice: Dictionary) -> void:
	var effects: Dictionary = choice.get("effects", {})
	var deed_id: String = String(effects.get("deed", ""))
	var axes: Dictionary = effects.get("axes", {})
	var notice_mult: float = float(effects.get("notice", 0.0))
	var consumed_charge: bool = false

	if effects.has("raise_corpse"):
		_grave["raised"] = true
		graves_disturbed += 1
		villain.raise_corpse_at(position, int(effects["raise_corpse"]))
	if bool(effects.get("consume_valuables", false)):
		# Mercy forecloses profit, permanently: the valuables are gone, and the
		# grave is finished on the spot.
		_grave["taken"] = true
		_grave["returned"] = true
	if bool(effects.get("conceal", false)):
		_grave["concealed"] = true
		_conceals += 1
		# "Removes this grave's notice" -- a negative multiplier on the site's
		# own notice size, so how much it buys back stays authored per site.
	if effects.has("loot_table"):
		var fraction: float = float(effects.get("loot_fraction", 1.0))
		var table_id: String = loot_table
		if typeof(effects["loot_table"]) == TYPE_STRING:
			table_id = String(effects["loot_table"])
		_grave["taken"] = true
		graves_disturbed += 1
		_take_into_hands(villain, table_id, fraction)

	_apply_notice(villain, notice_mult)
	if deed_id != "":
		villain.record_deed(deed_id, axes, _day())
	EventBus.site_choice_resolved.emit(villain, self, String(choice.get("id", "")))

	if _grave_finished():
		charges_left = maxi(0, charges_left - 1)
		consumed_charge = true
		_grave = {"raised": false, "taken": false, "returned": false, "concealed": false}
	_refresh_sprite()
	if consumed_charge and charges_left <= 0 and not has_remainder():
		EventBus.travel_noted.emit("%s — nothing left to take." % display_name, 0.0)

## A grave is done when mercy ended it, when the evidence is gone, or when both
## the body and the valuables have been taken. Raise-then-steal is one grave.
func _grave_finished() -> bool:
	return _grave["returned"] or _grave["concealed"] or (_grave["raised"] and _grave["taken"])

func _take_into_hands(villain, table_id: String, fraction: float) -> void:
	var rolled: Dictionary = LootCatalog.roll(table_id, villain.drawn_relic_ids(), fraction)
	var taken := {}
	for kind in rolled["resources"].keys():
		var amount: int = int(rolled["resources"][kind])
		var got: int = villain.add_carried(kind, amount)
		if got > 0:
			taken[kind] = got
		if amount - got > 0:
			remainder[kind] = int(remainder.get(kind, 0)) + (amount - got)
	for id in rolled["relics"]:
		if villain.add_relic(id):
			EventBus.relic_found.emit(villain, id)
		else:
			relic_remainder.append(id)
	EventBus.site_looted.emit(villain, self, taken)

## Notice: the escalation half of the split. **World state, so it goes to
## `GameState.add_threat()`** and nowhere near the villain -- the reputation
## half is the deed ledger, and nothing reputation-shaped is ever reread out of
## `GameState` (reputation-ownership decision, 2026-08-06).
##
## The church cemetery escalates per grave, which is what makes the third grave
## in one sortie a genuinely reckless act; the derelict graveyard is authored
## with no notice at all and this stays a no-op there, forever.
func _apply_notice(villain, multiplier: float) -> void:
	var base: int = int(notice.get("threat", 0))
	if base <= 0 or is_equal_approx(multiplier, 0.0):
		return
	var scale: float = 1.0
	if bool(notice.get("escalates", false)):
		scale = float(maxi(1, graves_disturbed))
	var amount: int = int(round(float(base) * scale * multiplier))
	if amount == 0:
		return
	GameState.add_threat(amount)

## Called by `WorldSites` when the last guardian is dead or gone.
func mark_cleared(villain) -> void:
	if cleared:
		return
	cleared = true
	if is_den():
		# Section 3b: clearing a den is a **Power deed** ("battles won, monsters
		# slain") and modest notice -- wolves have no lord, but a silenced
		# forest gets talked about.
		villain.record_deed("cleared_a_den", {"power": 1}, _day())
		_apply_notice(villain, 1.0)
		EventBus.travel_noted.emit("%s — the pack is finished. That is one den fewer." % display_name, 0.0)
	else:
		villain.record_deed("cleared_a_site", {"power": 1}, _day())
		EventBus.travel_noted.emit("%s — nothing left standing in your way." % display_name, 0.0)
	_refresh_sprite()

## Everything he left behind, handed back in one go. No channel: picking your
## own haul back up is not a second robbery.
func _collect_remainder(villain) -> void:
	var taken := {}
	for kind in remainder.keys().duplicate():
		var got: int = villain.add_carried(kind, int(remainder[kind]))
		if got > 0:
			taken[kind] = got
			remainder[kind] = int(remainder[kind]) - got
			if int(remainder[kind]) <= 0:
				remainder.erase(kind)
	for id in relic_remainder.duplicate():
		if villain.add_relic(id):
			relic_remainder.erase(id)
			EventBus.relic_found.emit(villain, id)
	_refresh_sprite()
	EventBus.site_looted.emit(villain, self, taken)

# ---------------- Appearance --------------------------------------------------

## The spent-site swap. Destroy-the-evidence **replaces it with the undisturbed
## art** (section 4), which is the whole point of paying a second channel for it
## -- so a site every disturbed grave of which was concealed never swaps.
func _refresh_sprite() -> void:
	if _sprite == null or looted_sprite_path == "":
		return
	var want_looted: bool = is_spent() and not _fully_concealed()
	var want: String = looted_sprite_path if want_looted else sprite_path
	if want == "" or not ResourceLoader.exists(want):
		return
	if _sprite.texture and _sprite.texture.resource_path == want:
		return
	var previous_width: float = _sprite.texture.get_size().x if _sprite.texture else 0.0
	var tex: Texture2D = load(want)
	_sprite.texture = tex
	# Canvas-width sizing (see setup): keeping the drawn width means keeping the
	# scale, so a looted sprite on a different canvas would resize the site.
	# `check_sprite_scales` asserts the two canvases match; this keeps the drawn
	# size correct even if one ever does not.
	if previous_width > 0.0 and tex.get_size().x > 0.0:
		_sprite.scale = Vector2.ONE * (_sprite.scale.x * previous_width / tex.get_size().x)
	Anchoring.foot(_sprite)

func _fully_concealed() -> bool:
	return graves_disturbed > 0 and _conceals >= graves_disturbed

func _remainder_label() -> String:
	var parts: Array = []
	if not remainder.is_empty():
		parts.append(LootCatalog.describe(remainder))
	for id in relic_remainder:
		parts.append(String(LootCatalog.relic(id).get("name", id)))
	return ", ".join(parts) if not parts.is_empty() else "nothing"

# ---------------- Inspection --------------------------------------------------

func get_inspect_data() -> Dictionary:
	var rows: Array = []
	for row in detail_rows:
		rows.append({"label": String(row.get("label", "")), "value": String(row.get("value", "")),
			"muted": bool(row.get("muted", false))})
	if lootable:
		rows.append_array(_loot_rows())
	return {
		"title": display_name,
		"subtitle": subtitle,
		"sprite": _sprite.texture.resource_path if _sprite and _sprite.texture else sprite_path,
		"description": _past_tense_description() if is_spent() else description,
		"details": rows,
	}

## Danger is telegraphed and chosen (section 1.3): the payload says what class
## of trouble a site carries **before** the player commits, and it says what is
## still lying here after he has been.
func _loot_rows() -> Array:
	var rows: Array = []
	rows.append({"label": "Danger", "value": "Band %d — %s" % [band, _band_word()]})
	if is_guarded():
		rows.append({"label": "Guarded", "value": "%d %s still standing" % [
			_living_guardians(), "guardian" if _living_guardians() == 1 else "guardians"],
			"color": Color(1.0, 0.55, 0.45)})
	elif guardian_spec.size() > 0:
		rows.append({"label": "Guarded", "value": "Cleared."})
	if is_channelling():
		rows.append({"label": "Working", "value": "%s — %d%%" % [
			_channel_label, roundi(channel_progress() * 100.0)]})
	if charges_left > 0:
		rows.append({"label": "Left here", "value": "%d of %d" % [charges_left, charges_max]})
	elif is_spent():
		rows.append({"label": "Left here", "value": "Nothing. Spent for the run.", "muted": true})
	if has_remainder():
		rows.append({"label": "You left", "value": _remainder_label(),
			"color": Color(0.95, 0.85, 0.45)})
	var threat: int = int(notice.get("threat", 0))
	if threat <= 0:
		rows.append({"label": "Notice", "value": "Nobody comes here. Nobody would know."})
	elif bool(notice.get("escalates", false)):
		rows.append({"label": "Notice", "value": "Rising — each grave is louder than the last",
			"color": Color(1.0, 0.6, 0.5)})
	else:
		rows.append({"label": "Notice", "value": "Someone would notice this"})
	return rows

func _band_word() -> String:
	match band:
		1: return "the ground you know"
		2: return "contested wilderness"
		3: return "somebody's land"
		_: return "nobody goes this far"

func _living_guardians() -> int:
	var n: int = 0
	for g in guardians:
		if is_instance_valid(g) and g.is_alive() and not g.has_left():
			n += 1
	return n

func _past_tense_description() -> String:
	if _fully_concealed():
		return "%s Whatever happened here, the ground does not say." % description
	return "Emptied. Whatever was worth taking is in your hands or on the road home."
