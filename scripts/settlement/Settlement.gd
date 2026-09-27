class_name Settlement
extends RefCounted
## **One settlement model for everyone** (LIVING_WORLD_SPEC section 2, rulings
## 13-14, 2026-09-26). The player's town is a settlement whose owner is the
## villain; the human village is a settlement whose owner is the lordship. Same
## class, same stockpile, same deposit rule.
##
## ## What lives here
##
## - **The stockpile** (ruling 13): every resource kind, per settlement. The
##   player's lives here too -- `GameState` is a *facade* over the player's
##   settlement, so the HUD and every existing caller still read `GameState.wood`
##   and are really reading this.
## - **Followers / population and Power** (ruling 13). `GameState.followers` and
##   `GameState.power` are this settlement's fields for the player's town.
## - **The deposit rule** (ruling 14): a load banked at a building is multiplied
##   by that building's *integrity*. The player's Throne is always 1.0, so the
##   player's economy is unchanged; a damaged mill banks less of every trip.
##
## ## What does not live here
##
## The trip loop. Production is still agents walking out and back
## (`WorkerSystem`, and `VillageLabor` for the village). The section 5.2 formula
## `output = base x staffed_fraction x integrity` is what that loop *adds up
## to* -- `production_readout()` prints it; nothing computes income from it.

signal stockpile_changed

## Every kind a stockpile can hold. The order is the HUD's order.
const KINDS := ["wood", "stone", "food", "bones", "dark_essence", "gold", "arms"]

## Who owns it. `"villain"` for the player's town (the villain object is held by
## the systems that need him -- never looked up from here); a faction id such as
## `"human"` for everyone else.
var owner: String = "villain"
var id: String = ""
var display_name: String = ""

var stockpile: Dictionary = {}

## Population. For the player's town this is the recruit roster (`Follower`s --
## the skeletons are the WorkerSystem's roster and eat nothing); for the village
## it is every living villager.
var followers: Array = []

## **Prisoners held in this settlement's Cells** (LIVING_WORLD L3, ruling 6):
## `Prisoner`s. They eat from this stockpile. `Captives` manages them.
var prisoners: Array = []

## Derived score -- see GameState.recompute_power for the player's formula.
var power: int = 0

## Where loads are banked when a unit has no job building of its own.
var home_position: Vector2 = Vector2.ZERO

## Fractional deposits carried per kind, so an 80%-integrity mill banks 4 of
## every 5 logs over time rather than rounding each 1-log trip to 0 or 1.
var _deposit_carry: Dictionary = {}

func _init(p_id: String = "", p_owner: String = "villain", p_name: String = "") -> void:
	id = p_id
	owner = p_owner
	display_name = p_name
	for k in KINDS:
		stockpile[k] = 0

func is_players() -> bool:
	return owner == "villain"

# ---------------- The stockpile --------------------------------------------------

func amount(kind: String) -> int:
	return int(stockpile.get(kind, 0))

## Direct write, for the facade's setters and for seeding. Clamped at zero: a
## negative stockpile is a bug somewhere else, and hiding it as -3 wood on the HUD
## would only move the symptom.
func set_amount(kind: String, value: int) -> void:
	if not stockpile.has(kind):
		push_warning("Settlement '%s': unknown kind '%s'" % [id, kind])
		return
	stockpile[kind] = maxi(0, value)
	stockpile_changed.emit()

func add(kind: String, n: int) -> bool:
	if not stockpile.has(kind):
		push_warning("Settlement '%s': unknown kind '%s'" % [id, kind])
		return false
	stockpile[kind] = maxi(0, int(stockpile[kind]) + n)
	stockpile_changed.emit()
	return true

func can_afford(kind: String, n: int) -> bool:
	return stockpile.has(kind) and int(stockpile[kind]) >= n

func can_afford_cost(cost: Dictionary) -> bool:
	for k in cost.keys():
		if not can_afford(String(k), int(cost[k])):
			return false
	return true

func spend(kind: String, n: int) -> bool:
	if not can_afford(kind, n):
		return false
	stockpile[kind] = int(stockpile[kind]) - n
	stockpile_changed.emit()
	return true

## **The deposit rule** (ruling 14). A load of `n` banked at a building with
## `integrity` (0-1) adds `n x integrity`, fractions carried to the next load.
## Returns what actually entered the stockpile this time.
func deposit(kind: String, n: int, integrity: float = 1.0) -> int:
	if n <= 0:
		return 0
	var exact: float = float(n) * clampf(integrity, 0.0, 1.0) + float(_deposit_carry.get(kind, 0.0))
	var whole: int = int(floor(exact + 0.000001))
	_deposit_carry[kind] = exact - float(whole)
	if whole > 0:
		add(kind, whole)
	return whole

## One line for a panel: "12 food, 30 wood". Zero kinds are left out.
func stock_line() -> String:
	var parts: Array = []
	for k in KINDS:
		var a: int = amount(k)
		if a > 0:
			parts.append("%d %s" % [a, String(k).replace("_", " ")])
	return ", ".join(parts) if not parts.is_empty() else "empty"
