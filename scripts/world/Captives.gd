class_name Captives
extends Node2D
## **Downed, bound, held** (LIVING_WORLD_SPEC sections 10-11, L3, built
## 2026-09-27). The one place that knows about the bottom of a humanoid's health
## bar and what comes after it.
##
## ## Downed (11.2)
##
## At 0 hp a humanoid -- a villager, an outlaw -- **goes down** instead of dying,
## with a bleed-out window (`data/captives.json`). Wildlife does not down: a wolf
## kills (and a skeleton was dead already). During the window:
##
## - **Bind** him: a prisoner, on a rope behind the Necromancer.
## - **Finish** him: a corpse, a body to raise -- exactly what a kill used to be.
## - **Rescue**: his own side comes for him. The village's guards drag Frank back
##   to his house, where he comes round (`VillageLabor`'s guard duty).
## - Expiry: he dies of it, and the one who put him down owns the death.
##
## **Bind all / Finish all** (11.3) act on every body within a few cells of him,
## or every fight ends in ten clicks.
##
## ## Prisoners (10)
##
## In tow, a prisoner is **unbanked** like any haul: walk him home. At home he
## goes into a **Cell** if there is room (a blueprint, like every building;
## ruling 6). Every prisoner eats one food at dawn and at dusk from the treasury;
## two missed meals and he dies where he is held -- a body to raise.
## What a prisoner is for (10.3): **Search** him once (resources, and the first
## search teaches the Cell), and **sacrifice** him at the Dark Altar for a Ghoul
## (level 2). Trade and hiring need the bandits and the market (L6, L7).
##
## ## Ownership
##
## The rope is per villain (`Necromancer.prisoners`); the Cell's occupants are the
## settlement's (`Settlement.prisoners`, ruling 13's "each settlement owns its
## own"). This node holds the downed list, the clocks and the views, and is
## handed every reference it needs -- nothing is looked up.

const DATA_PATH := "res://data/captives.json"
const TOKEN_HEIGHT := 58.0

var world: WorldMap = null
var world_sites: WorldSites = null
var village = null                  # Village (untyped: no load-order dependency)
var villain: Necromancer = null
var settlement: SettlementGrid = null
var worker_system: WorkerSystem = null
var witnesses = null
var day_provider: Callable = Callable()
## `func(id: String) -> bool`: is this blueprint already known?
var knows_blueprint: Callable = Callable()
## `func() -> int`: his level, for Summon Ghoul.
var level_provider: Callable = Callable()

var downed: Array = []              # Array[Downed]
var _tokens: Dictionary = {}        # Downed / Prisoner -> Node2D
var _data: Dictionary = {}
var _warned_no_room: bool = false
var _was_home: bool = false

## The rope itself, drawn from him to each prisoner in turn.
var _rope: Node2D

func _ready() -> void:
	_load()
	_rope = Node2D.new()
	_rope.name = "Rope"
	_rope.z_index = 3
	_rope.draw.connect(_draw_rope)
	add_child(_rope)
	EventBus.dawn_started.connect(_on_meal)
	EventBus.dusk_started.connect(_on_meal)
	EventBus.villain_died.connect(_on_villain_died)
	set_process(true)

func _load() -> void:
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed

func tunable(key: String, fallback):
	return _data.get(key, fallback)

func bleed_seconds() -> float:
	return float(tunable("bleed_out_seconds", 45.0))

func bind_reach_px() -> float:
	return float(tunable("bind_reach_px", 72.0))

func batch_reach_px() -> float:
	return float(tunable("batch_reach_cells", 5.0)) * float(SettlementGrid.CELL_SIZE)

func rescue_reach_px() -> float:
	return float(tunable("rescue_cells", 14.0)) * float(SettlementGrid.CELL_SIZE)

func _day() -> int:
	return int(day_provider.call()) if day_provider.is_valid() else 1

func _band_at(p: Vector2) -> int:
	return int(world.band_at(p).get("band", 2)) if world else 2

# ================= Downed ======================================================

## A villager hit 0 hp. He stays the village's man -- a job, a house, a name on
## his building -- until he dies, is taken, or is carried home.
func down_villager(v: Villager, killer) -> Downed:
	if v == null or v.dead or v.captured or v.downed:
		return null
	if village:
		village.drop_duty(v)
	v.downed = true
	v.hp = 0
	v.abandon_trip()
	v.in_combat = false
	v.panicked = false
	# A witness who goes down tells nobody: run the man down before the gate.
	v.runner_to = Vector2.ZERO
	v.report = {}
	if village:
		village.set_token_visible(v, false)
	var d := Downed.new()
	d.display_name = v.label()
	d.race_id = Villager.RACE_ID
	d.faction = "human"
	d.origin = village.display_name if village else ""
	d.sprite_path = village.sprite_path_for(v) if village else ""
	d.position = v.position
	d.person = v
	d.killer = killer
	_add_downed(d)
	return d

## A site guardian that downs (an outlaw) hit 0 hp. The guardian leaves its site
## as it would have on dying -- the cave is cleared of him -- and what is left is
## a man on the ground.
func down_guardian(g: SiteGuardian, killer) -> Downed:
	var d := Downed.new()
	d.display_name = g.display_name
	d.race_id = g.race_id
	d.faction = g.kind
	d.origin = g.site.display_name if g.site else ""
	d.sprite_path = g.sprite_path
	d.position = g.position
	d.killer = killer
	if world_sites:
		world_sites.remove_guardian(g, killer)
	else:
		g.queue_free()
	_add_downed(d)
	return d

func _add_downed(d: Downed) -> void:
	d.bleed_total = bleed_seconds()
	d.bleed_left = d.bleed_total
	downed.append(d)
	_make_token(d, true)
	EventBus.unit_downed.emit(d, d.killer)

func _remove_downed(d: Downed) -> void:
	downed.erase(d)
	_free_token(d)

## He can act on this man from where he stands.
func in_reach(d: Downed, by) -> bool:
	return by != null and by.is_alive() and downed.has(d) \
		and by.position.distance_to(d.position) <= bind_reach_px()

## Every body close enough for Bind all / Finish all.
func downed_near(by) -> Array:
	if by == null or not by.is_alive():
		return []
	var reach: float = batch_reach_px()
	return downed.filter(func(d: Downed): return by.position.distance_to(d.position) <= reach)

func bind(d: Downed, by) -> Prisoner:
	if not in_reach(d, by):
		return null
	return _bind(d, by)

func finish(d: Downed, by) -> bool:
	if not in_reach(d, by):
		return false
	_die(d, by, "finished")
	return true

func bind_all(by) -> int:
	var n: int = 0
	for d in downed_near(by):
		if _bind(d, by) != null:
			n += 1
	return n

func finish_all(by) -> int:
	var list: Array = downed_near(by)
	for d in list:
		_die(d, by, "finished")
	return list.size()

func _bind(d: Downed, by) -> Prisoner:
	_remove_downed(d)
	var p := Prisoner.new()
	p.display_name = d.display_name
	p.race_id = d.race_id
	p.faction = d.faction
	p.origin = d.origin
	p.sprite_path = d.sprite_path
	p.person = d.person
	p.position = d.position
	if d.person != null and village:
		village.on_villager_captured(d.person, by)
		p.display_name = d.person.villager_name
	by.prisoners.append(p)
	_make_token(p, false)
	if by is Necromancer:
		by.record_deed("took_a_prisoner", {"cruelty": 1}, _day(), _band_at(d.position))
	if witnesses and by == villain:
		witnesses.witness("taking %s prisoner" % p.display_name, d.position, d.person,
			"bind_%d" % d.get_instance_id())
	EventBus.prisoner_taken.emit(by, p)
	return p

## He dies: bled out, or finished. A villager's death is the village's to read
## (his body, the restaffing, the deed against whoever put him down); an outlaw
## leaves a body to raise.
func _die(d: Downed, killer, how: String) -> void:
	_remove_downed(d)
	if d.person != null and village:
		d.person.downed = false
		d.person.position = d.position
		village.on_villager_killed(d.person, killer)
	elif world_sites:
		world_sites.spawn_body(d.position, d.display_name)
	EventBus.downed_died.emit(d, killer, how)

# ---------------- Rescue (called by the village's guards) ----------------

## The nearest downed man of `faction` within rescue reach that nobody is
## already going for.
func rescue_target(faction: String, from: Vector2) -> Downed:
	var best: Downed = null
	var best_d: float = rescue_reach_px()
	for d in downed:
		if d.faction != faction or d.rescuer != null or d.is_carried():
			continue
		var dist: float = from.distance_to(d.position)
		if dist < best_d:
			best_d = dist
			best = d
	return best

func claim(d: Downed, by) -> void:
	d.rescuer = by

func release(d: Downed) -> void:
	if d == null:
		return
	d.rescuer = null
	d.carrier = null

func pick_up(d: Downed, by) -> void:
	d.rescuer = by
	d.carrier = by

## Carried home and brought round. The village gets its man back, shaken.
func revive(d: Downed) -> void:
	if not downed.has(d):
		return
	var by = d.carrier
	_remove_downed(d)
	if d.person != null and village:
		village.revive(d.person, d.position, float(tunable("revive_hp_fraction", 0.35)))
	EventBus.downed_rescued.emit(d, by)

func _carrier_ok(c) -> bool:
	return c != null and c.is_alive() and not c.downed and not c.dead and not c.captured and not c.panicked

# ================= Prisoners ===================================================

func held() -> Array:
	return GameState.player_settlement.prisoners

func in_tow(by = null) -> Array:
	var v = by if by != null else villain
	return v.prisoners if v != null else []

func all_prisoners() -> Array:
	var out: Array = held().duplicate()
	if villain:
		out.append_array(villain.prisoners)
	return out

func cell_buildings() -> Array:
	if settlement == null:
		return []
	return settlement.cells.values().filter(func(b): return b.building_id == "cell")

func cell_capacity() -> int:
	var n: int = 0
	for b in cell_buildings():
		n += maxi(0, int(b.capacity))
	return n

func cell_room() -> int:
	return maxi(0, cell_capacity() - held().size())

func throne_position() -> Vector2:
	if settlement == null:
		return Vector2.INF
	var t: Building = settlement.get_main_building()
	return _building_centre(t) if t else Vector2.INF

func _building_centre(b: Building) -> Vector2:
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	return Vector2(b.cell.x * SettlementGrid.CELL_SIZE + half, b.cell.y * SettlementGrid.CELL_SIZE + half)

func is_home(by = null) -> bool:
	var v = by if by != null else villain
	var t: Vector2 = throne_position()
	if v == null or t == Vector2.INF:
		return false
	return v.position.distance_to(t) <= float(tunable("home_cells", 6.0)) * float(SettlementGrid.CELL_SIZE)

## A prisoner he can put his hands on: on his rope, or in the Cell while he is home.
func can_reach_prisoner(p: Prisoner, by) -> bool:
	if by == null or not by.is_alive():
		return false
	if by.prisoners.has(p):
		return true
	return held().has(p) and is_home(by)

func _cell_slot(i: int) -> Vector2:
	var cells: Array = cell_buildings()
	if cells.is_empty():
		return throne_position()
	var b: Building = cells[mini(int(i / 4), cells.size() - 1)]
	var c: Vector2 = _building_centre(b)
	var k: int = i % 4
	return c + Vector2(-24.0 + 16.0 * k, 34.0)

## Home, with prisoners on the rope: into the Cell while there is room.
func _check_home() -> void:
	if villain == null or not villain.is_alive():
		return
	var home: bool = is_home()
	if home and not villain.prisoners.is_empty():
		var moved: int = 0
		while cell_room() > 0 and not villain.prisoners.is_empty():
			var p: Prisoner = villain.prisoners.pop_front()
			p.in_cell = true
			held().append(p)
			p.position = _cell_slot(held().size() - 1)
			moved += 1
		if moved > 0:
			EventBus.prisoners_delivered.emit(villain, moved, held().size())
		if not villain.prisoners.is_empty() and not _warned_no_room:
			_warned_no_room = true
			EventBus.prisoners_no_room.emit(villain, villain.prisoners.size(), cell_capacity())
	if not home:
		_warned_no_room = false
	_was_home = home

## Two meals a day, one food each, for every prisoner he holds -- in a Cell or
## on the rope. Fed resets the count; short, and the count climbs.
func _on_meal(_day_n: int) -> void:
	var per: int = int(tunable("food_per_meal", 1))
	var starve_at: int = int(tunable("starve_after_missed_meals", 2))
	for p in all_prisoners():
		if GameState.spend_resource("food", per):
			p.missed_meals = 0
		else:
			p.missed_meals += 1
			if p.missed_meals >= starve_at:
				_starve(p)
			else:
				EventBus.prisoner_hungry.emit(p)

func _starve(p: Prisoner) -> void:
	_drop_prisoner(p)
	if world_sites:
		world_sites.spawn_body(p.position, p.display_name)
	EventBus.prisoner_died.emit(p, "starved")

func _drop_prisoner(p: Prisoner) -> void:
	held().erase(p)
	if villain:
		villain.prisoners.erase(p)
	_free_token(p)

## Search him, once (section 10.3 use 3). Resources go into his pack; a blueprint
## is learned on the spot. Returns `{loot, blueprint}`, or {} if refused.
func search(p: Prisoner, by) -> Dictionary:
	if p == null or p.searched or not can_reach_prisoner(p, by):
		return {}
	p.searched = true
	var spec: Dictionary = tunable("search", {})
	var loot: Dictionary = {}
	var res: Dictionary = spec.get("resources", {})
	for k in res.keys():
		var r: Array = res[k]
		var n: int = randi_range(int(r[0]), int(r[1]))
		if n > 0:
			loot[String(k)] = n
			by.add_carried(String(k), n)
	var bp: String = ""
	if knows_blueprint.is_valid():
		var first: String = String(spec.get("first_blueprint", ""))
		if first != "" and not bool(knows_blueprint.call(first)):
			bp = first
		elif randf() < float(spec.get("blueprint_chance", 0.0)):
			var unknown: Array = []
			for id in spec.get("blueprints", []):
				if not bool(knows_blueprint.call(String(id))):
					unknown.append(String(id))
			if not unknown.is_empty():
				bp = unknown[randi() % unknown.size()]
	if bp != "":
		EventBus.blueprint_found.emit(by, bp, p.display_name)
	if by is Necromancer:
		by.record_deed("search_a_prisoner", {"wealth": 1}, _day(), 0)
	EventBus.prisoner_searched.emit(by, p, loot, bp)
	return {"loot": loot, "blueprint": bp}

# ---------------- Summon Ghoul (ROGUELITE_REWORK 17.5) ----------------

func altar() -> Building:
	if settlement == null:
		return null
	for b in settlement.cells.values():
		if b.building_id == "dark_altar":
			return b
	return null

## The prisoners he could sacrifice right now: the Cell and his rope, while he
## is home. The Altar is in the lair; the sacrifice happens there.
func sacrificeable(by) -> Array:
	if by == null or not is_home(by):
		return []
	var out: Array = held().duplicate()
	out.append_array(by.prisoners)
	return out

## Why Summon Ghoul cannot be cast, in words -- or "" when it can.
func ghoul_blocker(by) -> String:
	var need: int = int((tunable("ghoul", {}) as Dictionary).get("min_level", 2))
	if level_provider.is_valid() and int(level_provider.call()) < need:
		return "He has not learned it yet: Summon Ghoul comes at level %d." % need
	if altar() == null:
		return "It is cast at a Dark Altar."
	if all_prisoners().is_empty():
		return "It needs a living sacrifice — a prisoner. Put a man down, stand over him and bind him."
	if not is_home(by):
		return "He has to be at home, by the Altar, with the prisoner."
	return ""

func summon_ghoul(p: Prisoner, by) -> Laborer:
	if ghoul_blocker(by) != "" or not sacrificeable(by).has(p):
		return null
	var at: Vector2 = _building_centre(altar()) + Vector2(0, 40)
	if world:
		at = world.nearest_walkable(at)
	_drop_prisoner(p)
	var race: String = String((tunable("ghoul", {}) as Dictionary).get("race_id", "ghoul"))
	var unit: Laborer = null
	if worker_system:
		var ghoul_name: String = "%s the Ghoul" % p.display_name if p.person != null \
			else "Ghoul #%d" % (worker_system.workers.filter(func(w): return w.inspect_race_id() == race).size() + 1)
		unit = worker_system.raise_unit_at(at, ghoul_name, race)
	if by is Necromancer:
		by.record_deed("summon_a_ghoul", {"forbidden_knowledge": 1, "cruelty": 1}, _day(), 0)
	EventBus.ghoul_summoned.emit(by, p, unit)
	return unit

# ---------------- He fell ----------------

## The rope goes slack. A villager walks home; anyone else is gone. The Cell is
## at home and stays shut.
func _on_villain_died(v, _cause: String) -> void:
	if v == null or v != villain:
		return
	var freed: int = v.prisoners.size()
	for p in v.prisoners.duplicate():
		_free_token(p)
		if p.person != null and village:
			village.on_villager_freed(p.person, p.position)
	v.prisoners.clear()
	if freed > 0:
		EventBus.prisoners_freed.emit(v, freed)

# ================= Frame ======================================================

func _process(delta: float) -> void:
	for d in downed.duplicate():
		if d.carrier != null:
			if not _carrier_ok(d.carrier):
				release(d)
			else:
				d.position = d.carrier.position + Vector2(10, 4)
				continue
		if d.rescuer != null and not _carrier_ok(d.rescuer):
			d.rescuer = null
		d.bleed_left -= delta
		if d.bleed_left <= 0.0:
			_die(d, d.killer, "bled out")
	_tick_tow(delta)
	_check_home()
	_update_tokens()
	_rope.queue_redraw()

## On the rope: each walks after the one in front, `tow_gap_px` apart. They keep
## up with him -- the rope does not slow him down.
func _tick_tow(delta: float) -> void:
	if villain == null:
		return
	var gap: float = float(tunable("tow_gap_px", 30.0))
	var speed: float = villain.move_speed_px() * 1.2
	var lead: Vector2 = villain.position
	for p in villain.prisoners:
		var dist: float = p.position.distance_to(lead)
		if dist > 12.0 * float(SettlementGrid.CELL_SIZE):
			p.position = lead + Vector2(-gap, 6)
		elif dist > gap:
			var to: Vector2 = lead + (p.position - lead).normalized() * gap
			p.position = Roaming.step(p.position, to, speed, delta, world)
		lead = p.position

# ---------------- Views ----------------

func _draw_rope() -> void:
	if villain == null or villain.prisoners.is_empty():
		return
	var from: Vector2 = villain.position + Vector2(0, -20)
	for p in villain.prisoners:
		var to: Vector2 = p.position + Vector2(0, -22)
		_rope.draw_line(from, to, Color(0.55, 0.42, 0.28, 0.9), 2.0, true)
		from = to

func _make_token(obj, lying: bool) -> void:
	var t := Node2D.new()
	t.z_index = 4
	var s := Sprite2D.new()
	s.name = "Sprite"
	s.centered = true
	if obj.sprite_path != "" and ResourceLoader.exists(obj.sprite_path):
		var tex: Texture2D = load(obj.sprite_path)
		s.texture = tex
		s.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, TOKEN_HEIGHT)
	if lying:
		s.rotation = -PI * 0.5
		s.position = Vector2(0, -12)
		s.modulate = Color(0.85, 0.7, 0.7)
	else:
		Anchoring.foot(s)
		s.modulate = Color(0.75, 0.72, 0.8)
	t.add_child(s)
	var l := Label.new()
	l.name = "Tag"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(-30, -TOKEN_HEIGHT - 18.0) if not lying else Vector2(-30, -48)
	t.add_child(l)
	if lying:
		var back := ColorRect.new()
		back.name = "BleedBack"
		back.color = Color("3a2230")
		back.size = Vector2(36, 4)
		back.position = Vector2(-18, -30)
		t.add_child(back)
		var fill := ColorRect.new()
		fill.name = "Bleed"
		fill.color = Color("d8604f")
		fill.size = Vector2(36, 4)
		back.add_child(fill)
	t.position = obj.position
	add_child(t)
	_tokens[obj] = t

func _free_token(obj) -> void:
	var t: Node2D = _tokens.get(obj)
	if t:
		t.queue_free()
	_tokens.erase(obj)

func _update_tokens() -> void:
	for obj in _tokens.keys():
		var t: Node2D = _tokens[obj]
		t.position = obj.position
		var tag: Label = t.get_node("Tag")
		if obj is Downed:
			tag.text = "carried" if obj.is_carried() else "down · %ds" % int(ceil(obj.bleed_left))
			var fill: ColorRect = t.get_node_or_null("BleedBack/Bleed")
			if fill:
				fill.size.x = 36.0 * clampf(obj.bleed_left / maxf(1.0, obj.bleed_total), 0.0, 1.0)
		else:
			tag.text = "bound" if not obj.in_cell else ""
			var s: Sprite2D = t.get_node("Sprite")
			if villain and not obj.in_cell:
				s.flip_h = villain.position.x < obj.position.x

## Click picking: the nearest downed man or prisoner under `pos`.
func pick_at(pos: Vector2):
	var best = null
	var best_d: float = 30.0
	for obj in _tokens.keys():
		var p: Vector2 = obj.position + (Vector2(0, -12) if obj is Downed else Vector2(0, -24))
		var d: float = pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = obj
	return best
