extends Node
class_name SortieSystem

## The return leg: what the party can carry, where the haul becomes real, what
## happens when he puts it down, and what death costs him.
##
## `SORTIE_SPEC.md` section 9. This is the third policy layer in the project,
## beside `WorkerSystem` (the trip loop) and `CombatSystem` (fights), and it
## exists for the same reason they do: the rules about a load belong somewhere
## that is neither the villain nor the sites nor `GameState`.
##
## ## One instance per villain, and it never looks him up
##
## `villain`, `settlement`, `world` and `world_sites` are **fields handed in**.
## Nothing here calls a singleton or searches the tree for a Necromancer
## (ROGUELITE_REWORK section 11) -- a second villain gets a second
## `SortieSystem` with his own Throne, his own escort and his own haul, and the
## only thing they share is `GameState`, which is world state by design.
##
## ## The banking rule, at sortie scale
##
## Nothing is yours until it is home. `WorkerSystem` already proves the shape --
## resources enter `GameState` only on deposit -- and this is the same rule at
## four minutes' range with a much bigger number on the line. Everything about
## the return leg falls out of it: why death costs the haul, why a relic in his
## hands does nothing, and why dropping is a real decision.

## **1.5 cells from the Throne**, borrowed from `CombatSystem`'s throne-repair
## radius rather than invented, so "close enough to the Throne" means one thing
## in this project.
const DEPOSIT_RADIUS_PX: float = CombatSystem.THRONE_REPAIR_RADIUS_PX

## The cache art. A dropped cache reuses the hidden cache's sprite pair -- it is
## the same object in the fiction, a pile of things under something, and the
## looted version is the same empty hole.
const CACHE_SPRITE := "res://assets/placeholder/generated/site_cache.png"
const CACHE_LOOTED_SPRITE := "res://assets/placeholder/generated/site_cache_looted.png"
const CACHE_SIZE_PX: float = 46.0

# ---------------- Wiring (fields, never lookups) ------------------------------
var villain: Necromancer = null
var settlement: SettlementGrid = null
var world: WorldMap = null
## Needed because the 2026-08-29 amendment makes an open-country drop **spawn a
## site**, and sites are that container's business. Not in section 9's field
## list, which predates the ruling that requires it.
var world_sites: WorldSites = null

## How many caches this villain has left lying about, for their names.
var _caches_dropped: int = 0

func _ready() -> void:
	# **Connected here, and this system is built before every other listener.**
	# SORTIE_SPEC section 6 requires the haul cleared "before anything else
	# reads them", and Godot calls handlers in connection order. The harness
	# asserts the ordering rather than trusting the build order.
	EventBus.villain_died.connect(_on_villain_died)
	set_process(true)

func _process(_delta: float) -> void:
	_check_deposit()

# ---------------- Party capacity (section 2) ----------------------------------
#
# The sum lives here rather than on the villain, deliberately (section 9): he
# must not hold his own escort's capacity logic, because that is the seam where
# "the villain knows about the party" turns into "the villain owns the party".

## Villain plus one kind per escort member. A starting sortie is 6; with two
## End-4 skeletons it is 14 -- the spread that makes widening the party a
## settlement decision rather than a level-up.
func party_capacity() -> int:
	if villain == null:
		return 0
	var total: int = villain.carry_capacity()
	for member in villain.escort:
		total += _member_capacity(member)
	return total

func party_carried() -> int:
	if villain == null:
		return 0
	var total: int = villain.carried_total()
	for member in villain.escort:
		total += int(member.carrying_amount)
	return total

func party_space() -> int:
	return maxi(0, party_capacity() - party_carried())

## A skeleton hauls its own Endurance, through the `carrying_kind` /
## `carrying_amount` pair `Laborer` already owns for the trip loop -- **one kind
## per member**, because a skeleton is a pair of arms and not a pack, and
## because reusing those fields means the worker deposit path works on it
## unchanged.
func _member_capacity(member) -> int:
	return maxi(1, member.attribute("endurance")) if member.has_method("attribute") else 0

func _member_space(member) -> int:
	return maxi(0, _member_capacity(member) - int(member.carrying_amount))

## **Filling order: villain first, escort second, remainder third** (section 2).
## Not the reverse -- the villain is who survives, and if the party is going to
## lose someone on the way home it should not be the one holding the haul.
##
## **Takes the villain as a parameter**, and reads the escort off him rather
## than off this system's own field. LOOT_SITES_SPEC section 3's rule is that a
## site answers to the villain who walked up, *passed as a parameter, never
## looked up* -- and the first version of this ignored that, filling whoever
## this system happened to hold. In the game that is the same man; in the loot
## harness, which rolls tables into throwaway villains, it silently filled the
## live one instead and eleven assertions went red.
##
## Returns how much was actually taken, so the caller leaves the rest at the
## site as a remainder charge exactly as `add_carried()` already makes it.
func take_into_party(who, kind: String, amount: int) -> int:
	if who == null:
		return 0
	var taken: int = who.add_carried(kind, amount)
	var left: int = amount - taken
	for member in who.escort:
		if left <= 0:
			break
		# One kind per member: a skeleton already hauling bones cannot also take
		# gold, and that constraint is the escort's whole cost.
		if String(member.carrying_kind) != "" and String(member.carrying_kind) != kind:
			continue
		var room: int = mini(left, _member_space(member))
		if room <= 0:
			continue
		member.carrying_kind = kind
		member.carrying_amount = int(member.carrying_amount) + room
		taken += room
		left -= room
	return taken

# ---------------- The deposit (section 3) -------------------------------------

## **At the Throne, not at the band edge.** `TravelLog` treats the lair band as
## home for *measuring* a journey and that is right; banking is a different
## question. The band is 20x20 and crossing its edge is not an arrival -- making
## him walk the last few cells keeps the final seconds of the return leg real,
## and it is where the fiction puts a hoard anyway.
func at_throne() -> bool:
	if villain == null:
		return false
	var at: Vector2 = throne_position()
	return at != Vector2.INF and villain.position.distance_to(at) <= DEPOSIT_RADIUS_PX

func throne_position() -> Vector2:
	if settlement == null:
		return Vector2.INF
	var throne: Building = settlement.get_main_building()
	if throne == null:
		return Vector2.INF
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	return Vector2(throne.cell.x * SettlementGrid.CELL_SIZE + half,
		throne.cell.y * SettlementGrid.CELL_SIZE + half)

func has_anything_to_bank() -> bool:
	if villain == null:
		return false
	if not villain.carried.is_empty() or not villain.relics_carried.is_empty():
		return true
	for member in villain.escort:
		if int(member.carrying_amount) > 0:
			return true
	return false

## Automatic, no button. The worker trip loop deposits without a prompt and this
## is the same rule at longer range -- a confirmation dialog between the player
## and the thing they walked four minutes for is friction, not tension.
##
## Partial deposits are free: no minimum, no penalty. The tax is the walk, which
## is the only tax the design wants.
func _check_deposit() -> void:
	if villain == null or not villain.is_alive():
		return
	if not at_throne() or not has_anything_to_bank():
		return
	deposit()

## Banks everything the party is holding, in one frame, and wakes the relics.
## Returns what was banked.
func deposit() -> Dictionary:
	var load_out: Dictionary = villain.take_carried()
	for member in villain.escort:
		var amount: int = int(member.carrying_amount)
		if amount <= 0:
			continue
		var kind: String = String(member.carrying_kind)
		load_out[kind] = int(load_out.get(kind, 0)) + amount
		member.carrying_amount = 0
		member.carrying_kind = ""
	for kind in load_out.keys():
		GameState.add_resource(kind, int(load_out[kind]))

	# **Relic effects activate here** (LOOT_SITES_SPEC section 7): banked = real,
	# the banking rule applied to power. A relic in hand grants nothing, which is
	# what keeps "drop it and run" a live choice on the return leg rather than a
	# pure loss.
	var relics: Array = villain.bank_relics()
	for relic_id in relics:
		EventBus.relic_banked.emit(villain, relic_id)

	EventBus.sortie_deposited.emit(villain, load_out, relics)
	return load_out

# ---------------- Dropping (section 5, as amended) ----------------------------

## Puts `amount` of `kind` down. Returns the site it landed in, or null if there
## was nothing to drop.
##
## **The asymmetry is the design**, and the 2026-08-29 amendment changed which
## half is which. Dropping while standing at a site returns the units to *that
## site's* remainder -- reorganising your haul. Dropping in open country now
## leaves a `dropped_cache` rather than destroying the load: the cost is the
## time-taxed walk back for it, and from R3 the risk that a scavenger found it
## first.
func drop(kind: String, amount: int) -> WorldSite:
	if villain == null or amount <= 0:
		return null
	var held: int = int(villain.carried.get(kind, 0))
	var moving: int = mini(amount, held)
	if moving <= 0:
		return null
	villain.carried[kind] = held - moving
	if int(villain.carried[kind]) <= 0:
		villain.carried.erase(kind)

	var site: WorldSite = _drop_target()
	site.remainder[kind] = int(site.remainder.get(kind, 0)) + moving
	site.refresh_after_remainder_change()
	EventBus.sortie_load_dropped.emit(villain, kind, moving, site)
	return site

## Same for a relic, which is identity-bearing and so moves one at a time.
##
## Relics stay droppable on purpose (section 10): "drop it and run" is the whole
## tension the deposit-activation rule exists to create, and taking the option
## away would make it theatre.
func drop_relic(relic_id: String) -> WorldSite:
	if villain == null or not villain.relics_carried.has(relic_id):
		return null
	villain.relics_carried.erase(relic_id)
	var site: WorldSite = _drop_target()
	site.relic_remainder.append(relic_id)
	site.refresh_after_remainder_change()
	EventBus.sortie_load_dropped.emit(villain, relic_id, 1, site)
	return site

## The site a drop lands in: the one he is standing at, or a new cache.
##
## Note that a cache **is** a lootable site, so dropping beside your own cache
## adds to it through the in-reach path rather than littering a second one. That
## falls out of the amendment's "full reuse of the site machinery" rather than
## needing a rule of its own.
func _drop_target() -> WorldSite:
	var here: WorldSite = world_sites.lootable_in_reach(villain) if world_sites else null
	if here != null:
		return here
	return _spawn_cache()

func _spawn_cache() -> WorldSite:
	_caches_dropped += 1
	var cache: WorldSite = world_sites.spawn_dropped_cache(villain.position,
		"cache_%d" % _caches_dropped, CACHE_SPRITE, CACHE_LOOTED_SPRITE, CACHE_SIZE_PX)
	EventBus.sortie_cache_created.emit(villain, cache)
	return cache

# ---------------- Death (section 6) -------------------------------------------

## **The load is lost.** `carried`, `relics_carried` and every escort member's
## load are cleared before anything else can read them -- this is the banking
## rule at sortie scale, and it has to be true from the first commit, because
## shipping a version where death is free teaches the player the opposite of the
## lesson the whole run frame depends on.
##
## R2 has no run lifecycle: he respawns at the Throne at full hp, the log is
## loud, and R4 owns the rest. Moved here from `CombatSystem` in R2c, which is
## exactly what that file's comment said would happen.
func _on_villain_died(who, _cause: String) -> void:
	# Only our own. `villain_died` is a global signal and every villain emits
	# it; respawning somebody else's at *our* Throne is the mistake section 11
	# exists to prevent, and the harness simulates enough deaths to prove it.
	if who == null or who != villain:
		return
	who.carried.clear()
	who.relics_carried.clear()
	for member in who.escort:
		member.carrying_amount = 0
		member.carrying_kind = ""
	var at: Vector2 = throne_position()
	if at != Vector2.INF:
		who.place_at(at)
	who.heal_full()

# ---------------- Readouts ----------------------------------------------------

## "6 / 6 — full", for the HUD. One place, so the strip and the panel cannot
## describe the same hands differently.
func carry_label() -> String:
	var carried: int = party_carried()
	var capacity: int = party_capacity()
	var text: String = "%d / %d" % [carried, capacity]
	if carried >= capacity and capacity > 0:
		text += " — full"
	return text

func is_full() -> bool:
	return party_space() <= 0
