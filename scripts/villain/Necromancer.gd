class_name Necromancer
extends RefCounted
## **The villain, as data.** Position, hit points, Might, what he is carrying,
## who walks with him. `NecromancerToken` is a pure view over this object and
## owns nothing -- the same contract `Laborer`/`WorkerToken` already follow.
##
## ## Why this file exists now
##
## The token used to own his position, with a documented exception in CLAUDE.md
## and an equally documented migration trigger: *the moment any other system
## needs to know where he is, split it.* Three systems now do -- the camera
## follows him, `Combat.exchange()` hits him, and the keyboard drives him -- so
## the split has happened. There is exactly one authoritative position again.
##
## ## Per-villain state, not global state
##
## ROGUELITE_REWORK section 11: **no system may assume there is exactly one
## villain on the map.** None of this lives in `GameState` or any other
## autoload, and nothing here is a singleton. `Main` holds a reference to one
## instance; every system that needs "the villain" takes it as a field or a
## parameter (see `CombatSystem.villain`, `VillainController.villain`). That
## discipline is the entire present-day cost of keeping the Demonologist and
## multiplayer possible, and retrofitting it later is the expensive version.
##
## Practical consequence for anything added here: if you catch yourself writing
## `GameState.necromancer_hp` or a static `Necromancer.current`, that's the
## mistake this class exists to prevent.
##
## ## What he is NOT
##
## He is **not a `Laborer`** and must never become one. `WorkerSystem.laborers()`
## is the union of `workers` and `GameState.followers`; he is in neither, so
## there is no path by which he can be handed a gathering trip or counted in
## the workforce summary. That exclusion is structural rather than a flag
## someone has to remember to check. He extends RefCounted directly rather than
## Laborer for exactly this reason -- sharing the trip-loop base class would put
## him one `laborers()` change away from being labour.

## Which villain class this is. A string rather than an enum because the class
## roster is content (ROGUELITE_REWORK section 11 -- the Demonologist is class
## two) and content is data in this project.
const CLASS_ID := "necromancer"

## Commissioned portrait used by the inspection payload and HUD badge.
const PORTRAIT := "res://assets/official/characters/Necromancer_Portrait.png"

## Full-body art used only by the settlement map token.
const MAP_SPRITE := "res://assets/official/characters/Necromancer_Full_Body.png"

# ---------------- Tunables (ROGUELITE_REWORK section 15 lists these as open) --

## Cells per second while the player is holding a movement key. **Tunable.**
## Deliberately faster than a Skeleton Worker's 0.9 (he is the player, and
## trudging is not a fantasy) but not so fast that the settlement reads as small
## -- 1.4 crosses the 12-cell grid in about 8.5 seconds. Speed is in *cells* for
## the same reason walk_speed is (FOUNDATION_SPEC section 4): 1.0 = one grid
## cell per second, literally.
const MOVE_SPEED_CELLS: float = 1.0

## How long without a movement key before the idle pacing resumes. **Tunable.**
const IDLE_RESUME_SECONDS: float = 8.0

## How long a click destination may make no progress before it is abandoned.
## Short enough that walking into a cliff reads as "he stopped", long enough to
## survive the few no-progress frames of scraping around a corner.
const TARGET_STALL_SECONDS: float = 0.5

## The old pacing behaviour, demoted from "what he does" to "what he does when
## you leave him alone". Radius is around wherever he stopped, not around the
## Throne -- he is a unit you park now, not a fixture of the keep.
const IDLE_WANDER_CELLS: float = 2.0
const IDLE_WALK_SPEED_PX: float = 22.0
const IDLE_PAUSE_MIN: float = 2.5
const IDLE_PAUSE_MAX: float = 6.0

# ---------------- State ------------------------------------------------------

var class_id: String = CLASS_ID

## Authoritative map position. The token reads it; nothing else writes it.
var position: Vector2 = Vector2.ZERO

## The nine, loaded from the workbook's villain row via `races.json`
## (COMBAT_SPEC amendment 2026-08-06 note 4 -- the villain is authored beside
## the races, not in code). Endurance 6 keeps hp 20 and carry 6, both R1 values;
## Intelligence 7 is his highest of Str/Dex/Int, so §3.1 rule 3 makes him
## **Arcane with no special case anywhere**.
##
## Loyalty is deliberately absent from the workbook row -- loyalty to whom? --
## so it keeps the 5 default and nothing reads it.
var strength: int = 4
var dexterity: int = 4
var speed: int = 5
var endurance: int = 6
var intelligence: int = 7
var guile: int = 6
var perception: int = 6
var tact: int = 5
var loyalty: int = 5

## Current hit points. Initialised by heal_full() below -- see max_hp() for why
## the maximum is never stored.
var hp: int = 1

## What he is hauling, `resource kind -> amount`. A Dictionary rather than the
## single kind/amount pair a Laborer carries, because a sortie brings back a
## mixed load (ROGUELITE_REWORK section 8) while a worker trip is one resource
## by construction. Nothing banks it yet -- that is R2's deposit-at-the-lair
## step -- but the capacity is real and the inspection panel reads it.
var carried: Dictionary = {}

## Who is walking with him. Empty for the whole of R1: the escort arrives in R2
## with the sortie loop, built on the Command Undead order model rather than
## per-unit orders (ROGUELITE_REWORK section 5). It exists now so that every
## system reading "the villain" already sees the field it will eventually need.
var escort: Array = []

## Relics in his hands, by id. A **separate list from `carried`** because
## identity matters for a relic and does not for a unit of bones -- the
## Dictionary is for fungibles (LOOT_SITES_SPEC section 7). Each one occupies a
## carry slot like any resource unit.
var relics_carried: Array = []

## Relics that made it home. **This is the list the effects read.** A relic in
## hand grants nothing; effects activate on deposit at the lair -- the banking
## rule (ROGUELITE_REWORK section 1) applied to power, and what keeps "drop it
## and run" a live choice on the return leg rather than a pure loss. The deposit
## step itself is `SORTIE_SPEC.md`'s (R2c); this list and every reader below are
## here so that pass has nothing to invent.
var relics_banked: Array = []

## **The ledger R3 will read** (LOOT_SITES_SPEC section 6). Ordered and stamped
## in game-days, per-villain, and never in an autoload -- R3 reads notoriety
## from here, never out of `GameState`. R2 consumes none of it beyond a log
## line. It costs a signal and an array now and saves R3 from archaeology later.
var deeds: Array = []

## Corpses raised out of graves, before the escort exists to receive them
## (section 4: "dormant until escort lands, then retroactively live"). Recording
## them is the honest R2a shape -- the alternative was spawning a skeleton with
## nothing to do and no order model to put it under, which R2d would then have
## had to unpick.
var raised_dead: Array = []

## True while he is channelling a site action. **Read by `step()` below**, which
## is the whole reason it lives on him rather than on the site: his idle pacing
## would otherwise wander him out of range of the grave he is digging, eight
## seconds into a twelve-second pull.
var is_channelling: bool = false

## Optional soft fence, set by whoever owns the map. Zero-size means unbounded.
## Belt to `world`'s braces: the world map's blocking rim already stops him at
## the edge, and this catches the case where there is no map at all (tests).
var bounds: Rect2 = Rect2()

## The terrain he walks. A **reference handed in** like everything else about
## him -- he does not look it up, and a second villain on a second map would
## simply hold a different one. Null-safe: with no world he walks on water.
var world: WorldMap = null

## -1 / +1, last horizontal direction of travel. The token flips its sprite on
## it -- facing is simulation state for the same reason position is, since idle
## pacing and player input both change it and only one of them is on screen.
var facing_x: float = 1.0

## True on any frame the player actually drove him. Read by the inspection
## panel's Activity row.
var is_moving: bool = false

## Seconds since the last movement input. Once past IDLE_RESUME_SECONDS the
## pacing below takes over.
var idle_seconds: float = 0.0

## Where a right-click told him to walk, and whether one is outstanding. A
## *destination* is simulation state for the same reason `position` is: it
## survives across frames and exactly one thing may own it.
##
## It does **not** get its own movement code. `VillainController` turns it into
## the same movement vector the keys produce and hands that to `step()` -- so
## facing, terrain speed, blocking-slide, idle-resume and pacing all keep
## working without knowing a click happened. See `target_direction()`.
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false

## Progress bookkeeping for the stall give-up in `target_direction()`.
var _target_stall: float = 0.0
var _target_last_pos: Vector2 = Vector2.ZERO

var _idle_anchor: Vector2 = Vector2.ZERO
var _idle_target: Vector2 = Vector2.ZERO
var _idle_pause: float = 0.0
var _pacing: bool = false

## Death is announced once. `take_damage` is the only route to zero hp and
## Combat.exchange() will happily land another swing on a corpse in the same
## frame, so without this the signal fires twice.
var _death_announced: bool = false

func _init(start_position: Vector2 = Vector2.ZERO) -> void:
	position = start_position
	_idle_anchor = start_position
	_idle_target = start_position
	heal_full()

## Places him without any of the movement bookkeeping thinking he walked there.
func place_at(p: Vector2) -> void:
	position = p
	_reset_idle(p)
	clear_move_target()

# ---------------- Movement ---------------------------------------------------

## Pixels per second under player control. Same cells-per-second convention as
## `Laborer.walk_speed_px()`.
##
## Banked relics multiply it. The Wolf-Hide Cloak is `off_road: true`, so it
## reads the ground he is standing on through the same `speed_multiplier()` the
## movement itself uses -- a road bonus is a road bonus, and the cloak is for
## everywhere else.
func move_speed_px() -> float:
	return MOVE_SPEED_CELLS * float(SettlementGrid.CELL_SIZE) * _relic_speed_multiplier()

func _relic_speed_multiplier() -> float:
	if relics_banked.is_empty():
		return 1.0
	var on_road: bool = terrain_speed() > 1.0
	var mult: float = 1.0
	for id in relics_banked:
		for effect in LootCatalog.relic(id).get("effects", []):
			if bool(effect.get("dormant", false)) or String(effect.get("kind", "")) != "move_speed_mult":
				continue
			if bool(effect.get("off_road", false)) and on_road:
				continue
			mult *= float(effect.get("value", 1.0))
	return mult

## One frame of movement. `move_dir` is the raw (unnormalised) direction vector
## from whoever is reading input -- `Vector2.ZERO` when he is not being driven.
##
## Both halves of "hold to move" and "idle pacing resumes" live here rather than
## in the controller, because both write `position` and position has exactly one
## owner. The controller decides *what the player asked for*; this decides where
## he ends up.
##
## **A right-click destination arrives through this same parameter**, converted
## by `target_direction()` in the controller. It is not a second movement path
## and must never become one: everything below -- pacing cancellation, facing,
## terrain speed, the blocking slide -- would then need doing twice, and the two
## copies would drift. If you are adding a new way to move him, produce a vector
## and hand it here.
func step(move_dir: Vector2, delta: float) -> void:
	is_moving = false
	if move_dir != Vector2.ZERO:
		# Any input cancels pacing instantly -- no easing out of it, no walking
		# the last step of a wander first. The player pressed a key; he moves.
		_reset_idle(position)
		var motion: Vector2 = move_dir.normalized() * move_speed_px() * terrain_speed() * delta
		_move_by(motion)
		is_moving = true
		return

	# Standing still on purpose is not standing still by accident. A channel is
	# the one state where "he has not moved for a while" must NOT resume the
	# pacing -- see `is_channelling`.
	if is_channelling:
		return

	idle_seconds += delta
	if idle_seconds < IDLE_RESUME_SECONDS:
		return
	if not _pacing:
		# Around wherever he was left standing, not around the Throne.
		_pacing = true
		_idle_anchor = position
		_pick_idle_target()
	_advance_pacing(delta)

# ---------------- Click destination ------------------------------------------

## Send him walking to `p`. Straight line, no pathfinding -- `_move_by` still
## slides him along blocking terrain, so a wall deflects him rather than
## stopping him dead, and `terrain_speed()` still applies exactly as it does to
## a held key.
func set_move_target(p: Vector2) -> void:
	move_target = p
	has_move_target = true
	_target_stall = 0.0
	_target_last_pos = position

func clear_move_target() -> void:
	has_move_target = false
	_target_stall = 0.0

## The movement vector this frame's outstanding click destination implies, or
## `Vector2.ZERO` when there is nothing to walk to. Clears the target on arrival.
##
## This is the *only* thing the click target does: it produces a vector, and
## `step()` consumes it identically to a keyed one. That is what keeps "where is
## he going" a single question with a single answer -- facing, idle-resume and
## pacing all keep working because none of them can tell a click from a key.
##
## **Arrival reuses the epsilon the idle pacing uses** (`maxf(stride, 2.0)`),
## because it is the same problem: a target closer than one frame's stride would
## be overshot and then chased back and forth forever.
##
## **And it gives up when wedged.** A straight line into a cliff corner slides
## to a halt with the target still outstanding, and without this he would walk
## on the spot, `is_moving` true, until the player pressed a key. Progress is
## measured in position rather than intent, so half a second of getting nowhere
## ends it.
func target_direction(delta: float) -> Vector2:
	if not has_move_target:
		return Vector2.ZERO
	var to_target: Vector2 = move_target - position
	var stride: float = move_speed_px() * terrain_speed() * delta
	if to_target.length() <= maxf(stride, 2.0):
		position = move_target
		clear_move_target()
		return Vector2.ZERO
	if position.distance_to(_target_last_pos) < stride * 0.25:
		_target_stall += delta
		if _target_stall >= TARGET_STALL_SECONDS:
			clear_move_target()
			return Vector2.ZERO
	else:
		_target_stall = 0.0
	_target_last_pos = position
	return to_target

## True while he has fallen back to the slow wander. Purely informational --
## the panel says so, and the smoke test asserts on it.
func is_pacing() -> bool:
	return _pacing

func _reset_idle(anchor: Vector2) -> void:
	idle_seconds = 0.0
	_pacing = false
	_idle_anchor = anchor
	_idle_target = anchor
	_idle_pause = 0.0

func _advance_pacing(delta: float) -> void:
	if _idle_pause > 0.0:
		_idle_pause -= delta
		return
	var to_target: Vector2 = _idle_target - position
	var stride: float = IDLE_WALK_SPEED_PX * delta
	if to_target.length() <= maxf(stride, 2.0):
		position = _idle_target
		_pick_idle_target()
		return
	_move_by(to_target.normalized() * stride)

func _pick_idle_target() -> void:
	var r: float = IDLE_WANDER_CELLS * float(SettlementGrid.CELL_SIZE)
	# Rejection-free polar pick, so he favours no particular direction. The sqrt
	# keeps the distribution even over the disc instead of clumping at the
	# centre.
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * r
	_idle_target = _idle_anchor + Vector2(cos(angle), sin(angle)) * dist
	_idle_pause = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)

## What the ground under him does to his pace: 1.0 on open ground, more on a
## road. Roads being faster is the map doc's §9 tradeoff -- worth a detour, and
## worth the exposure that arrives with patrols in R3.
func terrain_speed() -> float:
	return world.speed_multiplier(position) if world else 1.0

## Blocking terrain is refused, but **slid along rather than stuck against**
## (see WorldMap.slide) -- walking a diagonal into a cliff should scrape past
## it, not stop you dead. Idle pacing goes through here too, so he can't drift
## into a lake while brooding.
func _move_by(motion: Vector2) -> void:
	if world:
		position = world.slide(position, motion)
	else:
		position += motion
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		position = position.clamp(bounds.position, bounds.position + bounds.size)
	if absf(motion.x) > 0.01:
		facing_x = signf(motion.x)

# ---------------- Carrying ---------------------------------------------------

## Carry capacity = **Endurance**, the same rule every other unit follows
## (COMBAT_SPEC section 2.1). One rule, not two: giving the villain a bespoke
## carry stat would mean two places to look when a sortie comes home light. His
## Endurance 6 keeps the carry 6 that R1 shipped.
## Endurance plus whatever the Pallbearer's Gloves are worth, once they are
## home. Capacity is a **rule** (`SORTIE_SPEC.md` section 10: tune the yield,
## not the capacity), and a banked relic is the one sanctioned way to move it.
func carry_capacity() -> int:
	return maxi(1, attribute("endurance") + _relic_sum("carry_delta"))

## Resource units plus relics: **a relic occupies one carry slot** like any
## other unit (LOOT_SITES_SPEC section 7), which is what makes arriving at a
## crypt with full hands a real problem and `Drop` (R2c) a real answer.
func carried_total() -> int:
	var total: int = 0
	for amount in carried.values():
		total += int(amount)
	return total + relics_carried.size()

func carry_space() -> int:
	return maxi(0, carry_capacity() - carried_total())

## Takes as much of `amount` as will fit and returns how much was actually
## taken, so the caller can log the real number and leave the rest on the
## ground. Nothing calls this until R2's loot; the capacity exists now so the
## field and the panel agree from the start.
func add_carried(kind: String, amount: int) -> int:
	var taken: int = mini(maxi(0, amount), carry_space())
	if taken > 0:
		carried[kind] = int(carried.get(kind, 0)) + taken
	return taken

## Hands the whole load over and empties him -- the deposit half of the banking
## rule (ROGUELITE_REWORK section 1). Returns what he was holding.
func take_carried() -> Dictionary:
	var load_out: Dictionary = carried.duplicate()
	carried.clear()
	return load_out

## Human-readable load, for logs and the panel. "nothing" when empty.
func carried_label() -> String:
	var parts: Array = []
	for kind in carried.keys():
		parts.append("%d %s" % [int(carried[kind]), String(kind).capitalize().replace("_", " ")])
	for id in relics_carried:
		parts.append(String(LootCatalog.relic(id).get("name", id)))
	if parts.is_empty():
		return "nothing"
	return ", ".join(parts)

# ---------------- Relics (LOOT_SITES_SPEC section 7) -------------------------

## Everything this run has already turned up, in hand or banked. Handed to
## `LootCatalog.roll()` so relics stay unique per run **without the catalog
## holding run state** -- it is an autoload, and a second villain would draw
## from the same tables with his own set.
func drawn_relic_ids() -> Array:
	var out: Array = relics_carried.duplicate()
	out.append_array(relics_banked)
	return out

## Takes a relic if there is a slot for it. Returns false when there is not, and
## the caller leaves it at the site as a remainder charge -- the same rule
## `add_carried()` follows, for the same reason (`SORTIE_SPEC.md` section 4).
func add_relic(id: String) -> bool:
	if id == "" or drawn_relic_ids().has(id):
		return false
	if carry_space() <= 0:
		return false
	relics_carried.append(id)
	return true

## The deposit half, for R2c to call. Banking is what turns a relic from cargo
## into an effect.
func bank_relics() -> Array:
	var banked: Array = relics_carried.duplicate()
	relics_banked.append_array(banked)
	relics_carried.clear()
	return banked

## Sum of one numeric effect kind across banked relics. Effects are additive and
## unstacked in R2 -- relics are unique per run, so a second copy of anything
## cannot drop and there is nothing to stack.
func _relic_sum(kind: String) -> int:
	var total: int = 0
	for id in relics_banked:
		for effect in LootCatalog.relic(id).get("effects", []):
			if bool(effect.get("dormant", false)):
				continue
			if String(effect.get("kind", "")) == kind:
				total += int(effect.get("value", 0))
	return total

## Multiplier applied to a channel carrying any of `tags`. The Sexton's Ring is
## `{"kind": "channel_mult", "tags": ["grave"], "value": 0.75}` and nothing in
## code knows what a sexton is, which is the test a relic effect has to pass.
func channel_multiplier(tags: Array) -> float:
	var mult: float = 1.0
	for id in relics_banked:
		for effect in LootCatalog.relic(id).get("effects", []):
			if bool(effect.get("dormant", false)) or String(effect.get("kind", "")) != "channel_mult":
				continue
			var wanted: Array = effect.get("tags", [])
			if wanted.is_empty():
				mult *= float(effect.get("value", 1.0))
				continue
			for tag in tags:
				if wanted.has(tag):
					mult *= float(effect.get("value", 1.0))
					break
	return mult

## Extra cells of fog the Barrow Lantern reveals. Read by `Main._fog_sources()`.
func fog_reveal_bonus() -> int:
	return _relic_sum("fog_reveal_delta")

## Hit points the Chipped Censer restores at dawn. Read by `Main` on
## `dawn_started`, where the other dawn work already is.
func dawn_heal() -> int:
	return _relic_sum("heal_at_dawn")

# ---------------- Deeds (LOOT_SITES_SPEC section 6) --------------------------

## Records one deed and announces it. **Both halves in one call**, so there is
## no path by which the ledger and the signal disagree about what happened.
##
## `axes` is R3's five (`{"wealth": 1}`), written now and consumed later; R2
## reads none of it beyond the log line. The entry is stamped with the game day
## because R3 may replay the ledger rather than subscribe, and an unordered
## ledger is archaeology.
func record_deed(deed_id: String, axes: Dictionary, day: int) -> void:
	if deed_id == "":
		return
	deeds.append({"id": deed_id, "axes": axes.duplicate(), "day": day, "seq": deeds.size()})
	EventBus.deed_committed.emit(self, deed_id, axes)

## The four-way sheet's "raise the corpse", before there is an escort to hand it
## to (section 4: dormant until the escort lands, then retroactively live).
## Recorded rather than spawned -- a skeleton with no order model to stand under
## is a unit R2d would have to unpick.
func raise_corpse_at(at: Vector2, count: int = 1) -> void:
	for i in range(maxi(1, count)):
		raised_dead.append({"at": at, "dormant": true})

## The channel flag's one writer. A method rather than a bare assignment so the
## site can set it duck-typed, the same way everything else about him is reached.
func set_channelling(active: bool) -> void:
	is_channelling = active
	if active:
		# Cancels pacing outright rather than pausing it: he is working, and he
		# should not resume a half-finished wander when he stands up.
		_reset_idle(position)
		clear_move_target()

# ---------------- Escort -----------------------------------------------------

func escort_count() -> int:
	return escort.size()

# ---------------- Combat (the Combatant contract -- see Combat.gd) -----------
#
# All six methods, so `Combat.exchange()` and `Combat.is_combatant()` work on him
# with no special casing anywhere. He is a combatant like any other now; the
# only thing that treats him differently is CombatSystem's lair-aura rule, and
# that is a named flag rather than a hole in this contract.

## `max_hp = 8 + Might * 2`. **Computed, never stored**, same as every other
## combatant -- a stored copy goes stale the moment anything changes Might, and
## the run frame will change it (levels grant options rather than numbers, but
## relics and the Blacksmith already touch Might). The constants come from
## `Laborer` rather than being restated, so there is exactly one hp formula in
## the project.
func max_hp() -> int:
	return Laborer.HP_BASE + maxi(1, attribute("endurance")) * Laborer.HP_PER_ENDURANCE

func heal_full() -> void:
	hp = max_hp()
	_death_announced = false

func combat_name() -> String:
	return "The Necromancer"

## Arcane, and **not because anything here says so**: Intelligence 7 is simply
## his highest of Strength / Dexterity / Intelligence, and COMBAT_SPEC section
## 3.1 rule 3 does the rest. If this ever needed a hand-written profile, the
## rule would be wrong rather than the villain special.
func combat_profile() -> Dictionary:
	return Combat.profile_for(attribute("strength"), attribute("dexterity"),
		attribute("intelligence"))

func combat_defence(key: String) -> int:
	return attribute(key)

## Any of the nine by name, **plus whatever banked relics add to it**. Same
## shape and same average-rather-than-zero fallback as Laborer.attribute() -- he
## is not a Laborer (and structurally must never become one), so the nine lines
## are restated rather than inherited.
##
## Relic deltas land here rather than on the nine vars, which is what makes
## "effective, computed at use time, never stored" (CLAUDE.md) survive the Sermon
## of Ash: `max_hp()`, `combat_profile()` and `carry_capacity()` all read through
## this, so a +1 Intelligence relic changes his casting without a second code
## path and a +1 Endurance one would change his hit points and his hands at once.
func attribute(key: String) -> int:
	return _base_attribute(key) + _relic_attribute_delta(key)

func _base_attribute(key: String) -> int:
	match key:
		"strength": return strength
		"dexterity": return dexterity
		"speed": return speed
		"endurance": return endurance
		"intelligence": return intelligence
		"guile": return guile
		"perception": return perception
		"tact": return tact
		"loyalty": return loyalty
		_:
			push_warning("Necromancer: unknown attribute '%s'" % key)
			return RaceCatalog.REFERENCE_VALUE

func _relic_attribute_delta(key: String) -> int:
	if relics_banked.is_empty():
		return 0
	var total: int = 0
	for id in relics_banked:
		for effect in LootCatalog.relic(id).get("effects", []):
			if bool(effect.get("dormant", false)) or String(effect.get("kind", "")) != "attribute":
				continue
			if String(effect.get("attribute", "")) == key:
				total += int(effect.get("delta", 0))
	return total

func is_alive() -> bool:
	return hp > 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(1, max_hp()))

## Returns the damage actually applied, like every other Combatant.
##
## **Death is emitted from here, not from a policy layer**, precisely so that
## anything that can reduce his hp announces it: `Combat.exchange()` does not
## know who it is hitting, and a run-ending event that only fired when
## CombatSystem happened to be the caller would be a trap for every later
## damage source (traps, the crusade, a rival villain).
func take_damage(amount: int) -> int:
	var before: int = hp
	hp = maxi(0, hp - maxi(0, amount))
	var dealt: int = before - hp
	if hp <= 0 and not _death_announced:
		_death_announced = true
		EventBus.villain_died.emit(self, "slain")
	return dealt

func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(max_hp(), hp + maxi(0, amount))
	return hp - before

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------
#
# The data half only. Actions (Command Undead, camera follow) stay in Main, and
# the *camera follow state* row is appended by NecromancerToken, because where
# the camera is pointing is a view concern and has no business being state on
# the villain. See NecromancerToken.get_inspect_data().

func _hp_row() -> Dictionary:
	var row := {"label": "Health", "value": "%d / %d hp" % [hp, max_hp()]}
	if not is_alive():
		row["value"] = "Fallen"
		row["color"] = Color(1.0, 0.35, 0.35)
	elif hp_fraction() < Combat.FLEE_HP_FRACTION:
		row["color"] = Color(1.0, 0.45, 0.45)
	elif hp < max_hp():
		row["color"] = Color(0.95, 0.70, 0.40)
	return row

## What he is standing on, and what it is doing to his pace. Reads as flavour
## and works as a debug readout: "am I actually faster on this road" is
## answerable by clicking him.
func _ground_row() -> Dictionary:
	if world == null:
		return {"label": "Ground", "value": "—", "muted": true}
	var speed: float = terrain_speed()
	var value: String = world.terrain_name(position)
	if speed > 1.0:
		value += "  —  %d%% pace" % roundi(speed * 100.0)
	return {"label": "Ground", "value": value}

func activity_label() -> String:
	if not is_alive():
		return "Fallen"
	if is_channelling:
		return "Working at something"
	if is_moving:
		return "Walking his domain"
	if _pacing:
		return "Surveying his domain"
	return "Standing still"

## The two relic rows, and only when there is something to say. A relic in hand
## says out loud that it is doing nothing yet -- section 7's deposit rule is a
## real trade-off on the return leg, and the panel has to be honest about it or
## the player never feels it.
func _relic_rows() -> Array:
	var rows: Array = []
	if not relics_carried.is_empty():
		var names: Array = []
		for id in relics_carried:
			names.append(String(LootCatalog.relic(id).get("name", id)))
		rows.append({"label": "In hand", "value": ", ".join(names),
			"color": Color(0.95, 0.85, 0.45)})
		rows.append({"label": "", "value": "Carried relics do nothing. They wake when you get them home.", "muted": true})
	if not relics_banked.is_empty():
		var names: Array = []
		for id in relics_banked:
			names.append(String(LootCatalog.relic(id).get("name", id)))
		rows.append({"label": "Banked", "value": ", ".join(names)})
	return rows

func get_inspect_data() -> Dictionary:
	var rows: Array = [
		{"label": "Activity", "value": activity_label()},
		_hp_row(),
		{"label": "Profile", "value": "%s — Intelligence %d vs Intelligence" % [
			combat_profile()["profile"], attribute("intelligence")]},
		{"label": "Physical", "value": "Str %d   Dex %d   Spd %d   End %d" % [
			attribute("strength"), attribute("dexterity"), attribute("speed"), attribute("endurance")]},
		{"label": "Social", "value": "Int %d   Gui %d   Per %d   Tac %d" % [
			attribute("intelligence"), attribute("guile"), attribute("perception"), attribute("tact")]},
		_ground_row(),
		{"label": "Carrying", "value": "%d / %d — %s" % [carried_total(), carry_capacity(), carried_label()]},
	]
	rows.append_array(_relic_rows())
	rows.append({"label": "Escort", "value": "None — he walks alone" if escort.is_empty()
		else "%d following" % escort_count()})
	if not raised_dead.is_empty():
		rows.append({"label": "Raised", "value": "%d, waiting — they follow when you can lead them"
			% raised_dead.size(), "muted": true})
	if not deeds.is_empty():
		rows.append({"label": "Deeds", "value": "%d this run" % deeds.size(), "muted": true})
	rows.append({"label": "", "value": "He does not gather, and never counts toward your workforce.", "muted": true})
	return {
		"title": "The Necromancer",
		"subtitle": "Master of the Settlement",
		"sprite": PORTRAIT,
		"description": "He walks the bone-strewn yard at all hours, counting what the living owe him. The dead do not need counting. They simply obey.",
		"details": rows,
	}
