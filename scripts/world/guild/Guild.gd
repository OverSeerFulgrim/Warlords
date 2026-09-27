class_name Guild
extends Node2D
## **The Adventurers' Guild** (LIVING_WORLD_SPEC section 4, L2, built
## 2026-09-26). A neutral hall on the road that posts the region's bounties and
## takes coin from anyone -- including a Necromancer it does not recognise yet.
##
## - **The board is generated from world state** (section 4.2), never
##   hand-authored: every den still standing posts "clear the den"; a village
##   running short of wood or food posts a delivery. If nothing in the world is
##   wrong, the board is thin -- that is correct.
## - **Standing** (section 4.1) lives on the villain (`Necromancer.standing`),
##   per run, and only moves one way. Unknown: full pay. Suspected: the board
##   still pays, at a fraction, and lists "strange sightings". Known: the doors
##   are shut (ruling 5).
## - **Pay goes into his hands.** A bounty's gold is his when he banks it at the
##   Throne, like anything else he carries -- the banking rule applies to wages.
##
## One guild, holding the things it needs as fields -- never a lookup.

const DATA_PATH := "res://data/guild.json"
const FACTION := "guild"

var world: WorldMap = null
var world_sites: WorldSites = null
var village = null                  # Village (untyped: no load-order dependency)
var day_provider: Callable = Callable()
## `func(who, kind, amount) -> int`, how much went into his party's hands.
var party_filler: Callable = Callable()

var display_name: String = "The Adventurers' Guild"
var bounties: Array = []            # Array[Dictionary] -- see _post()
var _data: Dictionary = {}
var _sprite: Sprite2D
var _refresh_left: float = 0.0
var _next_id: int = 1

func build(p_world: WorldMap) -> bool:
	world = p_world
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("Guild: no %s." % DATA_PATH)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Guild: %s did not parse." % DATA_PATH)
		return false
	_data = parsed
	display_name = String(_data.get("name", display_name))
	var c: Array = _data.get("cell", [0, 0])
	position = world.cell_centre_px(Vector2i(int(c[0]), int(c[1]))) if world else Vector2.ZERO
	name = "Guild"
	return true

func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	var path: String = String(_data.get("sprite", ""))
	if path != "" and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_sprite.texture = tex
		_sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, float(_data.get("size", 92.0)))
		Anchoring.foot(_sprite)
	refresh_board()

func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 1.0
		refresh_board()

# ---------------- Queries ----------------

func reach_px() -> float:
	return float(_data.get("reach_cells", 2.5)) * float(SettlementGrid.CELL_SIZE)

func in_reach(v) -> bool:
	return v != null and v.position.distance_to(position) <= reach_px()

func open_to(v) -> bool:
	return v != null and v.standing_with(FACTION) < Necromancer.Standing.KNOWN

## Attention range in pixels right now (ruling 15): longer by day.
func attention_px(is_day: bool) -> float:
	var a: Dictionary = _data.get("attention_cells", {})
	return float(a.get("day" if is_day else "night", 8.0 if is_day else 4.0)) * float(SettlementGrid.CELL_SIZE)

## The keeper's, from the doorway -- shorter than a villager's (guild.json).
func keeper_attention_px(is_day: bool) -> float:
	var a: Dictionary = _data.get("keeper_attention_cells", {})
	return float(a.get("day" if is_day else "night", 5.0 if is_day else 3.0)) * float(SettlementGrid.CELL_SIZE)

## The cell the hall stands on, and the square of ground around it that is
## known from the start (a public building; nobody has to find it).
func cell() -> Vector2i:
	var c: Array = _data.get("cell", [0, 0])
	return Vector2i(int(c[0]), int(c[1]))

func known_ground() -> Rect2i:
	var r: int = int(_data.get("reveal_cells", 3))
	return Rect2i(cell() - Vector2i(r, r), Vector2i(r * 2 + 1, r * 2 + 1))

func report_threat() -> int:
	return int(_data.get("report_threat", 5))

func visible_bounties() -> Array:
	return bounties.filter(func(b): return ["open", "taken", "done"].has(String(b["state"])))

func taken_by(v) -> Array:
	return bounties.filter(func(b): return b.get("taker") == v and ["taken", "done"].has(String(b["state"])))

func hit_radius() -> float:
	if _sprite == null or _sprite.texture == null:
		return 36.0
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(28.0, maxf(drawn.x, drawn.y) * Anchoring.HIT_RADIUS_FRACTION)

func hit_centre() -> Vector2:
	if _sprite == null or _sprite.texture == null:
		return position
	return position - Vector2(0, Anchoring.drawn_content_size(_sprite).y * 0.5)

func pick_at(pos: Vector2) -> bool:
	return hit_centre().distance_to(pos) <= hit_radius()

# ---------------- The board (section 4.2) ----------------

## Posts what the world needs and closes what it no longer does. Cheap enough to
## run every second: a handful of dens and two village stocks.
func refresh_board() -> void:
	var changed: bool = false
	if world_sites:
		for den in world_sites.dens():
			var b: Dictionary = _bounty_for("den", den.site_id)
			if not den.cleared and b.is_empty():
				_post({"kind": "den", "key": den.site_id, "site": den, "band": den.band,
					"title": "Clear the den: %s, %s of here" % [den.display_name, compass(den.position - position)],
					"blurb": "A pack is killing stock on the road. Kill or drive off every wolf there, then come back for your pay.",
					"gold": int(_data.get("den_gold_per_band", 6)) * maxi(1, den.band)})
				changed = true
			elif den.cleared and not b.is_empty():
				match String(b["state"]):
					"open":
						b["state"] = "closed"      # cleared by nobody who took the job
						changed = true
					"taken":
						b["state"] = "done"
						changed = true
	if village:
		for d in _data.get("deliveries", []):
			var key: String = String(d.get("id", ""))
			var b: Dictionary = _bounty_for("deliver", key)
			var low: bool = village.settlement.amount(String(d["kind"])) < int(d.get("when_below", 0))
			if low and b.is_empty():
				_post({"kind": "deliver", "key": key, "band": 1, "res": String(d["kind"]),
					"amount": int(d.get("amount", 10)),
					"title": String(d.get("title", "%s needs supplies")) % village.display_name,
					"blurb": String(d.get("blurb", "")), "gold": int(d.get("gold", 5))})
				changed = true
			elif not low and not b.is_empty() and String(b["state"]) == "open":
				b["state"] = "closed"
				changed = true
	if changed:
		EventBus.guild_board_changed.emit(self)

## "south-west" and friends -- two dens share a name, and the board is read
## standing at the door, so the door is where the direction is from.
static func compass(d: Vector2) -> String:
	if d.length() < 1.0:
		return "here"
	var names: Array = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var i: int = int(round(fposmod(d.angle(), TAU) / (TAU / 8.0))) % 8
	return names[i]

func _bounty_for(kind: String, key: String) -> Dictionary:
	for b in bounties:
		if String(b["kind"]) == kind and String(b["key"]) == key and String(b["state"]) != "closed" \
				and String(b["state"]) != "paid":
			return b
	return {}

func _post(b: Dictionary) -> void:
	b["id"] = _next_id
	_next_id += 1
	b["state"] = "open"
	b["taker"] = null
	b["owed"] = 0
	bounties.append(b)

func bounty(id: int) -> Dictionary:
	for b in bounties:
		if int(b["id"]) == id:
			return b
	return {}

## Takes a job. Refused at Known, out of reach, or with too many in hand.
func take(v, id: int) -> bool:
	var b: Dictionary = bounty(id)
	if b.is_empty() or String(b["state"]) != "open" or not in_reach(v) or not open_to(v):
		return false
	if taken_by(v).size() >= int(_data.get("max_taken", 2)):
		return false
	b["state"] = "taken"
	b["taker"] = v
	EventBus.guild_board_changed.emit(self)
	return true

## A delivery is done at the counter: the goods come out of his stores and go
## on to the village (settlement to settlement), and the job is ready to pay.
func deliver(v, id: int) -> bool:
	var b: Dictionary = bounty(id)
	if b.is_empty() or String(b["kind"]) != "deliver" or String(b["state"]) != "taken" or b["taker"] != v:
		return false
	if not in_reach(v) or not GameState.spend_resource(String(b["res"]), int(b["amount"])):
		return false
	if village:
		village.settlement.add(String(b["res"]), int(b["amount"]))
	b["state"] = "done"
	return turn_in(v, id)

## Pays a finished job into his party's hands. Whatever will not fit stays owed
## at the counter -- come back with empty hands.
func turn_in(v, id: int) -> bool:
	var b: Dictionary = bounty(id)
	if b.is_empty() or String(b["state"]) != "done" or b["taker"] != v or not in_reach(v) or not open_to(v):
		return false
	var pay: int = int(b["owed"]) if int(b["owed"]) > 0 else _pay_for(v, b)
	var got: int = int(party_filler.call(v, "gold", pay)) if party_filler.is_valid() else 0
	if got <= 0:
		b["owed"] = pay
		return false
	var first_time: bool = int(b["owed"]) == 0
	b["owed"] = pay - got
	if int(b["owed"]) <= 0:
		b["state"] = "paid"
	if first_time:
		v.record_deed("guild_bounty", {"wealth": 1}, _day(), int(b.get("band", 1)))
	EventBus.guild_bounty_paid.emit(v, b, got)
	EventBus.guild_board_changed.emit(self)
	return true

func _pay_for(v, b: Dictionary) -> int:
	var gold: float = float(b["gold"])
	if v.standing_with(FACTION) == Necromancer.Standing.SUSPECTED:
		gold *= float(_data.get("suspected_pay", 0.5))
	return maxi(1, int(round(gold)))

func _day() -> int:
	return int(day_provider.call()) if day_provider.is_valid() else 1

# ---------------- Inspection ----------------

func _open_count() -> int:
	return bounties.filter(func(b): return String(b["state"]) == "open").size()

func get_inspect_data() -> Dictionary:
	return {
		"title": display_name,
		"subtitle": "A neutral hall on the road",
		"sprite": String(_data.get("sprite", "")),
		"description": "Takes coin from anyone, asks nothing, posts the region's troubles on a board by the door. It does not know what he is. Yet.",
		"details": [{"label": "On the board", "value": "%d %s" % [_open_count(), "job" if _open_count() == 1 else "jobs"]}],
	}
