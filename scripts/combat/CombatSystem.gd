extends Node
class_name CombatSystem
## Everything about the wolf that isn't the wolf: when one turns up, what it
## picks on, and what happens to whoever loses.
##
## The split matters. `Combat` is the formula (reusable, knows nothing).
## `Engagement` is a fight's clock (reusable, knows nothing). `Wolf` is a
## creature that moves and bleeds. **This** is the policy layer -- targeting,
## the emergent-defence rule, and the four consequence rules -- and it is the
## only one of the four that a Stage-4 bounty would need to replace. Building
## wolf-specific damage logic inline was the failure mode worth avoiding here.
##
## It also owns hit-point *maintenance*, because HP is a combat concern and
## there was no better home for it: skeletons repairing at the Throne live here.
## The living side of regen (+2 per meal) is in MoraleSystem, where the meal
## loop already is.

# ---------------- Design rules, stated once ----------------
#
# 1. **Skeleton Workers can be destroyed.** No bones refunded, no body left.
#    Replaceable for the usual 5 Bones. Losses sting; necromancers shrug.
# 2. **Living recruits are never killed by wildlife.** Below FLEE_HP_FRACTION
#    they break off, run home, and are Injured until healed to full. -1 morale.
# 3. **A deer taken by a wolf is a pure economic loss** -- the food is gone, the
#    wolf is fed and stands down for the night. This is the common case.
# 4. **Wolves will not approach the Necromancer INSIDE HIS OWN LAIR BAND.** He
#    is a real Combatant (he implements the whole contract on `Necromancer`, and
#    Combat.exchange() hits him with no special casing), and this is a *lair*
#    rule rather than an invulnerability. See `aura_protects_villain()`.
# 5. **He fights when the player walks him into it** -- engage close, cast far
#    (NECROMANCER_SPEC section 3). There is no attack button and there is no
#    auto-seek; walking in is attacking and walking out is disengaging.

## **The lair aura, as geography.**
##
## This was `LAIR_AURA_PROTECTS_VILLAIN`, a global bool, and its own header
## predicted this prompt: ROGUELITE_REWORK section 15 carried "whether a
## protective aura applies inside his own lair" as an open tunable, and
## NECROMANCER_SPEC section 5 answers it -- **the aura holds while he stands in
## `world.lair_band`, and nowhere else.** One band edge, one rule, no flag.
##
## The flag is deleted rather than left set to false, per section 8: a dead flag
## beside a live rule is how the next reader flips the wrong one.
##
## The position test itself is `Necromancer.is_in_lair_band()` -- a fact about
## his position, which he owns -- and it has **three consumers reading the same
## line**: this aura, his membership in `_prey_candidates()`, and his
## regeneration rate. That the amendment's regen ruling reuses this exact test
## is the whole of its implementation.
##
## Consequence worth stating out loud: the lair band is now *mechanically* home.
## Fleeing a botched sortie back across the band edge is reaching sanctuary.
func aura_protects_villain() -> bool:
	return villain != null and villain.is_alive() and villain.is_in_lair_band()

## **One "close enough to start a fight" number in the whole game.** Taken from
## the wolf rather than restated, because a second engage radius that drifted
## from this one would be invisible until a playtest could not explain why a
## fight started early.
##
## Note this is only the *opening* distance. Once engaged he exchanges at his
## Arcane profile reach -- five cells, from `Combat`'s C2 profile table, not a
## constant here. Section 3's split: starting a fight is deliberate and close;
## running one rewards positioning.
const VILLAIN_ENGAGE_PX: float = Wolf.ENGAGE_RADIUS_PX

## Out-of-combat regeneration (NECROMANCER_SPEC amendment 2026-08-29, ruling 1).
## One hit point per this many seconds while nothing is fighting him.
##
## **Tuned by one constraint:** the field trickle must never let a den fight be
## reset by circling the clearing. At 24 seconds a hit point, clawing back the
## ~12 hp a pack costs is five minutes of a thirty-minute day standing still --
## a real trade of daylight for health, which is the push-your-luck dial the
## amendment asks for, rather than a free reset.
const VILLAIN_REGEN_FIELD_SECONDS: float = 24.0
## How much faster it is at home. Same position test as the aura: one test, two
## consequences. 6x puts a full heal at roughly a minute inside the band, which
## is what makes limping home worth doing.
const VILLAIN_REGEN_LAIR_MULTIPLIER: float = 6.0

## Only one wolf at a time for now.
const MAX_WOLVES: int = 1

## Chance a wolf turns up on any given dusk *after the first*. Not every night:
## a guaranteed nightly wolf becomes a chore to plan around rather than a thing
## that happens to you.
const WOLF_SPAWN_CHANCE_PERCENT: float = 55.0

## **The first dusk of a run always brings a wolf.** Leaving the introduction to
## a 55% roll meant a player could finish a whole session having never met the
## creature -- which is exactly what happened in playtest, twice, because a
## session tends to end on the first night. A mechanic gets to introduce itself
## deterministically; it can be a gamble afterwards.
var _first_dusk_done: bool = false

## Radius, in pixels, for both halves of the emergent-defence rule: fighters
## inside it join, everyone else inside it runs. 3 grid cells.
const ASSIST_RADIUS_PX: float = 3.0 * float(SettlementGrid.CELL_SIZE)

## A recruit counts as "strong enough to be useful" -- and so wades in rather
## than running -- at this **Strength** or above, regardless of category.
## Warriors always qualify.
##
## Reworded from Might to Strength by COMBAT_SPEC section 6.2, which asks for
## exactly this and nothing more: the *shape* of the rule is unchanged, and the
## judgement/guidance layer that eventually replaces the threshold is C3.
const ASSIST_STRENGTH_THRESHOLD: int = 6

## Necromantic maintenance: an idle Skeleton Worker standing at the Throne
## knits itself back together at one hit point per this many seconds. Slow on
## purpose -- a mauled skeleton is out of the workforce for a while, which is
## most of what makes losing the fight cost anything when the unit itself is
## replaceable for 5 bones.
const THRONE_REPAIR_SECONDS: float = 6.0
const THRONE_REPAIR_RADIUS_PX: float = 1.5 * float(SettlementGrid.CELL_SIZE)

## Bones left by a killed wolf. Deliberately better than a seeded animal carcass
## (5): map bones are finite and the whole point of Stage 4's harvest bounties
## is that they run out, so a predator that walks into your settlement and pays
## out more than it costs is a small, welcome pressure valve -- and it makes
## keeping a warrior around something other than pure insurance.
const WOLF_CARCASS_BONES: int = 9

# ---------------- Wiring (set by Main, same convention as the other systems) --
var settlement: SettlementGrid = null
var worker_system: WorkerSystem = null
var resource_field: ResourceField = null
## The villain this settlement belongs to. A **reference passed in**, not a
## lookup and not a singleton -- ROGUELITE_REWORK section 11. It reads his
## `position` off the data object rather than off his token, which is the same
## view-is-a-frame-stale correctness the click hit-test already learned.
var villain: Necromancer = null
## Terrain, handed to each wolf so it prowls around mountains and lakes rather
## than through them.
var world: WorldMap = null
var day_night: DayNightCycle = null
## The site layer, for **the dusk gate** (LOOT_SITES_SPEC section 3b) and for
## the guardians it owns. A reference passed in like every other system here;
## null-safe, so a smoke test with no world map still spawns dusk wolves.
var world_sites: WorldSites = null

var wolves: Array = []          # Array[Wolf]
var _engagements: Array = []    # Array[Engagement]
var _repair_timer: float = 0.0
## Debounces the Necromancer flavor line so a wolf loitering near the Throne
## doesn't spam the log every frame.
var _necro_fear_cooldown: float = 0.0

func _ready() -> void:
	EventBus.dusk_started.connect(_on_dusk)
	EventBus.dawn_started.connect(_on_dawn)
	# **Connected first, on purpose.** SORTIE_SPEC section 6 requires the haul to
	# be cleared "before anything else reads them", and Godot calls handlers in
	# connection order -- this system is built in `_build_systems()`, well before
	# `Main._connect_signals()`, so this handler runs before the log line does.
	# The harness asserts the ordering rather than trusting the build order.
	EventBus.villain_died.connect(_on_villain_died)
	set_process(true)

## His zero (NECROMANCER_SPEC section 6, SORTIE_SPEC section 6). The *emission*
## stays on the data object -- `Necromancer.take_damage()` announces it, so that
## anything able to hurt him announces it, not just this file -- and this is the
## consequence half.
##
## R2: the unbanked haul is lost, he respawns at the Throne at full hp, the log
## is loud. **The run ending is R4's**, and the escort's own loads are R2d's.
## This handler is where `SortieSystem` will take over rather than reinvent.
##
## Losing the load has to be true from the first commit: shipping a version
## where death is free teaches exactly the opposite of the lesson the run frame
## depends on.
func _on_villain_died(v, _cause: String) -> void:
	# **Only our own.** `villain_died` is a global signal and every villain on
	# the map emits it; this system belongs to exactly one of them, and
	# respawning somebody else's villain at *our* Throne is the precise mistake
	# ROGUELITE_REWORK section 11 exists to prevent.
	#
	# Not hypothetical: the harness simulates a thousand fights with throwaway
	# `Necromancer` objects, and without this line the death handler healed them
	# back to full mid-fight and the win rates it reported were fiction.
	if v == null or v != villain:
		return
	# Cleared before anything else can read it -- including the log line that
	# would otherwise report a haul he no longer has.
	v.carried.clear()
	v.relics_carried.clear()
	_end_engagements_with_defender(v)
	var throne_at: Vector2 = _throne_position()
	if throne_at != Vector2.INF:
		v.place_at(throne_at)
	v.heal_full()

func _end_engagements_with_defender(unit) -> void:
	for e in _engagements.duplicate():
		if e.defenders.has(unit):
			e.remove_defender(unit)
			if not e.has_defenders():
				if e.attacker and is_instance_valid(e.attacker):
					e.attacker.clear_target()
				_finish(e)

func _throne_position() -> Vector2:
	if settlement == null:
		return Vector2.INF
	var throne: Building = settlement.get_main_building()
	if throne == null:
		return Vector2.INF
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	return Vector2(throne.cell.x * SettlementGrid.CELL_SIZE + half,
		throne.cell.y * SettlementGrid.CELL_SIZE + half)

func _process(delta: float) -> void:
	_necro_fear_cooldown = maxf(0.0, _necro_fear_cooldown - delta)
	for wolf in wolves.duplicate():
		_advance_wolf(wolf, delta)
	if world_sites:
		for g in world_sites.live_guardians():
			_advance_guardian(g)
	# Before the engagements, so a villain who has walked out of reach is off the
	# defender list by the time this frame's exchanges are rolled -- which is
	# what "walking beyond his reach stops his swings the next interval" means.
	_advance_villain()
	for e in _engagements.duplicate():
		_advance_engagement(e, delta)
	_tick_throne_repair(delta)
	_tick_villain_regen(delta)

# ---------------- Spawning ----------------

## Wolves come at dusk, from the treeline. The forest is the east edge of the
## map, which is also where your woodcutters and your carcass-gatherers are --
## so the creature arrives where the work is, without any code aiming it there.
##
## **The dusk gate** (LOOT_SITES_SPEC section 3b). While at least one den still
## stands the roll is exactly what it always was, first-dusk guarantee included;
## when the last den is cleared, dusk raids stop for the run. The fiction and
## the mechanics finally agree about where the wolves have been coming from.
##
## Asked **before the first-dusk guarantee**, deliberately: a player who spent
## day one clearing every den has earned a quiet first night, and a guaranteed
## wolf from a forest with nothing in it would be the version of this feature
## that does not work.
##
## The two guards from the spec, restated because both are easy to lose:
## the spawn **entry point stays settlement-relative** (see `spawn_wolf` -- a
## wolf that had to walk 60 cells from its den would arrive at midnight or
## never; the den explains the wolf, it does not path it), and den pack wolves
## are `SiteGuardian`s that never enter `wolves`.
func _on_dusk(_day: int) -> void:
	if world_sites and not world_sites.any_den_uncleared():
		return
	if wolves.size() >= MAX_WOLVES:
		return
	var guaranteed: bool = not _first_dusk_done
	_first_dusk_done = true
	if not guaranteed and randf() * 100.0 > WOLF_SPAWN_CHANCE_PERCENT:
		return
	spawn_wolf()

## **The breadcrumb** (designer ruling, 2026-08-30 playtest: finding a den felt
## like a chore). The direction of the nearest den still standing, from the
## settlement, in plain words.
##
## **At dawn, as tracks** (placement approved 2026-08-30). It was briefly in the
## dusk handler, which put an arrival's verb on a departure's sentence: at dusk
## nothing has gone anywhere yet, and the thing a player can actually read off
## the snow is where the wolves *went*. Dawn is also when the raid resolves,
## which is what the ruling asked for in the first place.
##
## A hint in a sentence. Not a marker, not a path, and **not** a change to the
## spawn: the wolf still enters settlement-relative, and nothing is ever pathed
## from a den. Silent once the last den is cleared, because at that point there
## is nothing to point at and the quiet is the whole reward.
func _note_the_tracks() -> void:
	if world_sites == null or settlement == null:
		return
	var home: Vector2 = _settlement_centre()
	var den: WorldSite = world_sites.nearest_uncleared_den(home)
	if den == null:
		return
	EventBus.travel_noted.emit("Tracks in the snow lead toward %s."
		% _compass_phrase(home, den.position), 0.0)

func _settlement_centre() -> Vector2:
	var cell: float = float(SettlementGrid.CELL_SIZE)
	return Vector2(SettlementGrid.GRID_WIDTH * cell, SettlementGrid.GRID_HEIGHT * cell) * 0.5

## Eight sectors, in words a person would actually use. Screen space, so +y is
## south -- the same convention the HUD's orientation readout uses.
const COMPASS_PHRASES := [
	"the eastern woods", "the woods south-east of here", "the south woods",
	"the woods south-west of here", "the western woods", "the woods north-west of here",
	"the north woods", "the woods north-east of here",
]

func _compass_phrase(from: Vector2, to: Vector2) -> String:
	var offset: Vector2 = to - from
	# Sector 0 is due east and they run clockwise (south is +y on screen), each
	# 45 degrees wide, so the +22.5 offset centres each word on its bearing.
	var degrees: float = fposmod(rad_to_deg(offset.angle()) + 22.5, 360.0)
	return COMPASS_PHRASES[int(degrees / 45.0) % COMPASS_PHRASES.size()]

## Dawn clears the board: any wolf still around slinks off. Keeps "max 1 alive"
## honest without needing a despawn timer, and means a wolf the player never
## dealt with doesn't accumulate into a permanent resident.
func _on_dawn(_day: int) -> void:
	# Whether the night actually brought anything, checked before they are sent
	# off: tracks are what a raid leaves behind, so a quiet night leaves none and
	# says nothing.
	var raided: bool = not wolves.is_empty()
	for wolf in wolves:
		if wolf.state != Wolf.State.LEAVING:
			wolf.depart("driven off by the light")
	if raided:
		_note_the_tracks()

## Public so a smoke test (or a future event) can force one. `at` overrides the
## spawn point; leave it null-ish (Vector2.INF) for the default treeline entry.
func spawn_wolf(at: Vector2 = Vector2.INF) -> Wolf:
	if resource_field == null or settlement == null:
		push_warning("CombatSystem: cannot spawn a wolf before wiring is complete.")
		return null
	var grid_w: float = float(SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE)
	var grid_h: float = float(SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE)
	var cell: float = float(SettlementGrid.CELL_SIZE)

	# East of the grid, level with the forest. Deliberately only ~2 cells out:
	# it used to enter 5.5 cells past the edge, which at the default 0.72 zoom
	# put it right on the rim of the viewport -- playtest reported "the wolf
	# spawned but I didn't see it" even with the alert firing. It has to arrive
	# somewhere the player is actually looking.
	#
	# **This stayed correct when the world grew to 144x144**, and it is worth
	# knowing why rather than re-deriving it: every number here is a multiple of
	# the *settlement grid's* size, and the settlement kept the engine origin
	# when the world map was slid in around it (see WorldMap's header). So the
	# entry point is ~12 cells from the Throne on a 144-cell map exactly as it
	# was on a 10-cell one. Anything added here must stay relative to grid_w /
	# grid_h for the same reason -- a wolf that spawned relative to the *world*
	# would arrive two minutes' walk away and never be seen.
	var entry := Vector2(grid_w + cell * 2.0, grid_h * 0.35)
	var spawn_at: Vector2 = entry if at == Vector2.INF else at

	var wolf := Wolf.new()
	wolf.name = "Wolf"
	settlement.add_child(wolf)
	# The prowl area covers the settlement and its surroundings; the exit is the
	# way it came in.
	wolf.setup(spawn_at, Rect2(Vector2(-cell * 2.0, -cell * 2.0),
		Vector2(grid_w + cell * 6.0, grid_h + cell * 4.0)), entry, world, villain)
	wolves.append(wolf)
	EventBus.wolf_spawned.emit(wolf)
	return wolf

func _despawn(wolf: Wolf) -> void:
	_end_engagements_with(wolf)
	wolves.erase(wolf)
	EventBus.wolf_departed.emit(wolf, wolf.leave_reason)
	wolf.queue_free()

# ---------------- Wolf behaviour ----------------

func _advance_wolf(wolf: Wolf, _delta: float) -> void:
	if wolf.state == Wolf.State.LEAVING:
		if wolf.has_left():
			_despawn(wolf)
		return
	if wolf.state == Wolf.State.FIGHT:
		return  # the Engagement owns it until the fight resolves

	_check_necromancer_fear(wolf)

	# A fed wolf still wanders -- visibly still out there, which is the point of
	# it *standing down* rather than vanishing -- and takes nothing else until
	# dawn moves it on. Same gate covers the post-spawn prowl period.
	if not wolf.may_hunt():
		wolf.clear_target()
		return

	var target = wolf.current_target()
	if target == null or not _is_valid_target(target):
		target = _find_prey(wolf)
		wolf.set_target(target)
		if target == null:
			return

	if not wolf.is_within_engage_range():
		return

	# Reached it. A deer is eaten outright -- no fight, no exchange -- because a
	# wolf killing a deer is a foraging event, not a battle, and modelling it as
	# combat would mean giving deer a Might value that means nothing.
	if _is_deer(target):
		_take_deer(wolf, target)
		return
	_begin_fight(wolf, target)

# ---------------- The villain's own fight (NECROMANCER_SPEC section 3) -------

## **Engage close, cast far**, run once a frame.
##
## Two radii doing two different jobs, and both halves are load-bearing:
##
## - **Opening** a fight needs `VILLAIN_ENGAGE_PX` (26px). Walking in is
##   attacking. There is no attack button, no target cursor, no auto-seek: the
##   input model stays "WASD drives him, the world reacts".
## - **Running** one happens at his Arcane profile reach, five cells, read off
##   `combat_profile()` rather than a constant here -- so the escort closes to
##   melee while he casts over their shoulders, produced by C2's profile table
##   with no bespoke code.
##
## **Why not simply auto-engage at five cells?** Section 3 answers it: he would
## snipe every wolf that wandered past, "he never auto-seeks" would be a lie,
## and stealth-by-default would stop being the fiction's resting state. Starting
## a fight has to cost the walk into biting distance; only *running* one rewards
## positioning.
##
## **He is never rooted.** No `in_combat` on him -- his membership is the
## `Engagement` this function adds him to and removes him from, and the player
## can drive him out of it at any moment without asking.
func _advance_villain() -> void:
	if villain == null or not villain.is_alive():
		_announce_villain_engagement("")
		return
	var current: Engagement = _villain_engagement()
	if current != null:
		# Walking out is disengaging. Measured against the attacker he is
		# actually fighting, so falling back *behind* an escort keeps him in the
		# fight while walking away from it ends it.
		var foe = current.attacker
		if foe == null or not is_instance_valid(foe) or not foe.is_alive():
			return   # the engagement's own resolution will clean this up
		if villain.position.distance_to(foe.position) > _villain_reach_px():
			current.remove_defender(villain)
			_announce_villain_engagement("", "out of reach")
			return
		_announce_villain_engagement(foe.combat_name())
		return

	_announce_villain_engagement("", "the fight ended")

	# Not fighting. Inside his own band nothing starts -- the aura is a rule
	# about the ground he is standing on, and it protects both ways: nothing
	# hunts him there, and closing on something there opens nothing either.
	if aura_protects_villain():
		return
	for foe in _hostiles():
		if villain.position.distance_to(foe.position) <= VILLAIN_ENGAGE_PX:
			# `engage()` joins an existing fight if the foe is already in one --
			# the same pile-in rule three rallied skeletons follow, which is what
			# makes "fighting while escorted is one fight" true for free.
			engage(foe, villain)
			_announce_villain_engagement(foe.combat_name())
			return

## Announces **the transition**, not the cause.
##
## The first version emitted `villain_engaged` only on the walk-in path, which
## silently missed every fight he did not start -- and section 4's retaliation
## is precisely the case where he is engaged without touching a key. Since the
## wolf's own policy runs before this in `_process`, a wolf that closes on him
## opens the fight first and the walk-in branch is never reached.
##
## So the signal is driven off the membership changing, whoever changed it. One
## place, both directions, no way for the HUD to miss half of them.
var _villain_foe: String = ""

func _announce_villain_engagement(foe_name: String, reason: String = "") -> void:
	if foe_name == _villain_foe:
		return
	var was: String = _villain_foe
	_villain_foe = foe_name
	if was != "":
		EventBus.villain_disengaged.emit(villain, was,
			reason if reason != "" else "the fight ended")
	if foe_name != "":
		EventBus.villain_engaged.emit(villain, foe_name)

## Everything on the map that would fight him. Wolves and site guardians today;
## anything with the Combatant contract and a hostile policy later.
func _hostiles() -> Array:
	var out: Array = []
	for w in wolves:
		if is_instance_valid(w) and w.is_alive() and w.state != Wolf.State.LEAVING:
			out.append(w)
	if world_sites:
		out.append_array(world_sites.live_guardians())
	return out

## Five cells, from the C2 profile table. **Not a constant in this file** -- his
## reach is a property of being Arcane, and a second copy here would be the
## first thing to drift if a relic ever changed his profile.
func _villain_reach_px() -> float:
	return float(villain.combat_profile()["reach_px"])

func _villain_engagement() -> Engagement:
	for e in _engagements:
		if e.defenders.has(villain):
			return e
	return null

## Read by the inspection panel through `Necromancer.foe_provider`, which is a
## Callable precisely so that this stays the only place that knows.
func villain_foe_name() -> String:
	var e: Engagement = _villain_engagement()
	if e == null or e.attacker == null or not is_instance_valid(e.attacker):
		return ""
	return e.attacker.combat_name()

func villain_is_engaged() -> bool:
	return _villain_engagement() != null

# ---------------- Regeneration (amendment 2026-08-29, ruling 1) --------------

## A slow trickle afield, greatly increased at home, **suppressed entirely while
## anything is fighting him** -- and driven by the same position test as the
## aura, which is the whole of the implementation the amendment asks for.
##
## The constraint that sets the rate is not "how fast should healing be" but
## "waiting must cost daylight the player feels": a den fight must not be
## resettable by circling the clearing. See `VILLAIN_REGEN_FIELD_SECONDS`.
##
## A delta accumulator, so it scales with `Engine.time_scale` like every other
## clock in the project (CLAUDE.md).
func _tick_villain_regen(delta: float) -> void:
	if villain == null or not villain.is_alive() or villain.hp >= villain.max_hp():
		_regen_timer = 0.0
		return
	if villain_is_engaged():
		# Not "slowed while fighting" -- stopped. Healing through an exchange
		# would blunt every threshold section 6 exists to announce.
		_regen_timer = 0.0
		return
	var seconds: float = VILLAIN_REGEN_FIELD_SECONDS
	if villain.is_in_lair_band():
		seconds /= maxf(1.0, VILLAIN_REGEN_LAIR_MULTIPLIER)
	_regen_timer += delta
	while _regen_timer >= seconds and villain.hp < villain.max_hp():
		_regen_timer -= seconds
		_show_hp_change(villain, villain.heal(1), "heal")

var _regen_timer: float = 0.0

# ---------------- Site guardians (LOOT_SITES_SPEC section 3b / 9) ------------

## A guardian objects to whoever walks into the disc it is guarding, closes on
## them, and fights. Same three states and the same `Engagement` as the wolf --
## this is the policy layer's whole point, and a raider or a bounty monster gets
## the identical treatment for free.
##
## **The lair aura does not apply out here.** `LAIR_AURA_PROTECTS_VILLAIN` is a
## rule about his own domain (see the flag's header), and a den whose wolves
## refused to face him would be a den nobody could ever clear.
func _advance_guardian(g: SiteGuardian) -> void:
	if g.state == SiteGuardian.State.FIGHT:
		return
	var target = g.current_target()
	if target == null or not _is_live(target):
		target = _find_intruder(g)
		g.set_target(target)
		if target == null:
			return
	if not g.is_within_engage_range():
		return
	_begin_fight(g, target)
	if g.site and villain and target == villain:
		EventBus.site_guardian_engaged.emit(villain, g.site)

## The villain first, then anything of his standing in the way. Nearest wins,
## same as the wolf -- and the villain outranks his own units because he is the
## reason the guardian woke up.
func _find_intruder(g: SiteGuardian):
	if villain != null and villain.is_alive() and g.notices(villain.position):
		return villain
	var best = null
	var best_dist: float = INF
	if worker_system:
		for l in worker_system.all_units():
			if not _is_live(l) or not g.notices(l.position):
				continue
			var d: float = g.position.distance_to(l.position)
			if d < best_dist:
				best_dist = d
				best = l
	return best

func _is_live(t) -> bool:
	return t != null and is_instance_valid(t) and t.has_method("is_alive") and t.is_alive()

## Nearest living recruit, worker or deer inside the hunt radius. No preference
## between them -- see Wolf's header for why "nearest" is sufficient.
func _find_prey(wolf: Wolf):
	var best = null
	var best_dist: float = Wolf.HUNT_RADIUS_PX
	for candidate in _prey_candidates():
		var d: float = wolf.position.distance_to(candidate.position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

## all_units() rather than laborers(): a skeleton standing guard at a rally
## point is out of the workforce but very much still on the map, and a wolf that
## couldn't see it would walk straight past the thing sent to stop it.
func _prey_candidates() -> Array:
	var out: Array = []
	if worker_system:
		for l in worker_system.all_units():
			if _is_valid_target(l):
				out.append(l)
	if resource_field:
		for n in resource_field.nodes:
			if n.node_type == "deer" and not n.is_depleted():
				out.append(n)
	# **Outside the band he is prey** (NECROMANCER_SPEC section 4). The line the
	# old comment block said was missing -- "he is not in `_prey_candidates()` at
	# all" -- is this one. A dusk wolf, a den pack and a site guardian now all
	# hunt him like anyone else, and danger-from-choices holds because he had to
	# walk there.
	#
	# `villain` is the **reference handed to this system**, never a lookup and
	# never a singleton (ROGUELITE_REWORK section 11): a second villain's wolves
	# would be hunting a different man.
	if villain != null and villain.is_alive() and not aura_protects_villain():
		out.append(villain)
	return out

## Excludes anyone standing in the Necromancer's shadow (rule 4) and any recruit
## already injured -- they're holed up at home, and re-targeting them would put
## a below-threshold unit straight back into a fight it must immediately flee,
## which loops.
func _is_valid_target(t) -> bool:
	if t == null:
		return false
	if _is_deer(t):
		return not t.is_depleted()
	if not t.is_alive():
		return false
	# **The villain is not a Laborer** and has no `is_injured` -- he has no
	# injured state at all, deliberately (section 6: he does not flee, the player
	# decides). What takes him off the menu is stepping back inside his own band,
	# which the shadow test below already answers.
	if t is Necromancer:
		return not aura_protects_villain()
	if t.is_injured:
		return false
	if _near_necromancer(t.position):
		return false
	return true

func _is_deer(t) -> bool:
	return t is ResourceNode and t.node_type == "deer"

## Standing in his shadow -- and only while the shadow exists, which is now a
## place rather than a switch. Outside the band this is false for everyone,
## including him, which is exactly how he becomes prey.
func _near_necromancer(pos: Vector2) -> bool:
	if not aura_protects_villain():
		return false
	return pos.distance_to(villain.position) <= Wolf.NECROMANCER_FEAR_RADIUS_PX

## Rule 4, as behaviour rather than a hard wall: a wolf that drifts too close to
## the Necromancer turns around. Flavor-logged the first time, then debounced.
## No-ops entirely once he steps outside his own band -- see `aura_protects_villain()`.
func _check_necromancer_fear(wolf: Wolf) -> void:
	if not _near_necromancer(wolf.position):
		return
	wolf.clear_target()
	# Push it back out the way it came.
	wolf.position += (wolf.position - villain.position).normalized() * 12.0
	if _necro_fear_cooldown <= 0.0:
		_necro_fear_cooldown = 20.0
		EventBus.necromancer_feared.emit("wolf")

## Rule 3. The deer is emptied outright rather than damaged -- the wolf takes the
## whole animal exactly as a hunter would (ResourceNode.make_deer's
## yield_per_action is the same 8), the food never reaches the player, and the
## wolf stands down for the night.
##
## It does **not** leave. An earlier version had it depart on the spot, which
## read cleanly in the log and terribly on screen: the wolf was off the map
## seconds after arriving and the player never saw it. "Stops hunting for the
## rest of the day" is also what the design actually asked for. It slinks off at
## dawn like any other wolf (see _on_dawn).
func _take_deer(wolf: Wolf, deer) -> void:
	deer.take(deer.remaining)
	wolf.is_fed = true
	wolf.clear_target()
	EventBus.deer_taken_by_predator.emit(deer, "wolf")

# ---------------- Fights ----------------

## Public entry point for "this unit and that wolf are now fighting", whoever
## started it. Adds to the existing fight if one is already running against that
## wolf, so three rallied skeletons converging on the same wolf produce one
## three-defender Engagement rather than three separate duels.
##
## Called by UndeadCommand when a bound skeleton closes on a wolf -- the roles
## are nominally reversed there (the skeleton is the aggressor) but combat is
## symmetric, both sides swing, so the Engagement doesn't care who is filed as
## the attacker.
func engage(attacker, unit) -> void:
	if attacker == null or unit == null or not is_instance_valid(attacker):
		return
	var existing := _engagement_for(attacker)
	if existing:
		if existing.add_defender(unit):
			_enter_combat(unit)
		return
	_begin_fight(attacker, unit)

func _engagement_for(attacker) -> Engagement:
	for e in _engagements:
		if e.attacker == attacker:
			return e
	return null

## **Not every defender is a Laborer.** The villain is a full Combatant and has
## neither `in_combat` nor a trip to abandon, so the two bookkeeping calls that
## used to be inline are behind a property check. That is the whole cost of the
## fight loop no longer being wolf-and-worker only.
func _enter_combat(unit) -> void:
	if "in_combat" in unit:
		unit.in_combat = true
	if unit.has_method("abandon_trip"):
		unit.abandon_trip()

func _leave_combat(unit) -> void:
	if unit != null and is_instance_valid(unit) and "in_combat" in unit:
		unit.in_combat = false

func _begin_fight(attacker, defender) -> void:
	if not Combat.is_combatant(attacker) or not Combat.is_combatant(defender):
		push_warning("CombatSystem: refusing to start a fight with a non-Combatant.")
		return
	var e := Engagement.new(attacker)
	e.add_defender(defender)
	_enter_combat(defender)
	if attacker is Wolf:
		attacker.state = Wolf.State.FIGHT
	elif attacker is SiteGuardian:
		attacker.state = SiteGuardian.State.FIGHT
	_engagements.append(e)
	EventBus.combat_started.emit(attacker.combat_name(), defender.combat_name())
	_rally_and_scatter(attacker, e)

## The emergent-defence rule, and the reason this is worth building before
## guard posts exist: **nobody is ordered to fight.** Any Warrior-category or
## Might >= 6 recruit close enough to see it wades in on their own; everyone
## else drops what they're carrying and runs. The player's only lever is who
## they recruited and where those people happen to be -- which is the Majesty
## indirect-control pillar applied to defence.
func _rally_and_scatter(attacker, e: Engagement) -> void:
	if worker_system == null:
		return
	for l in worker_system.all_units():
		if l.in_combat or not l.is_alive():
			continue
		if l.position.distance_to(attacker.position) > ASSIST_RADIUS_PX:
			continue
		# Skeletons neither rally nor scatter (see _will_fight) -- and a rallied
		# one is under standing orders that outrank a panic, so it is skipped
		# entirely rather than being told to run.
		if not (l is Follower):
			continue
		if _will_fight(l):
			e.add_defender(l)
			_enter_combat(l)
			EventBus.combat_joined.emit(l, attacker.combat_name())
		else:
			l.begin_flee()

## Skeleton Workers are never volunteers -- they have no self-preservation to
## override and, unless the Necromancer has bound them to a rally point, no
## orders to act on either. They neither rally nor scatter; they carry on until
## something bites them. Only living recruits react on their own.
##
## (Caller already excludes non-Followers, so this is the same rule stated
## twice on purpose -- it is the sort of thing a later edit gets wrong.)
func _will_fight(l) -> bool:
	if not (l is Follower):
		return false
	return l.category == "Warrior" or l.strength >= ASSIST_STRENGTH_THRESHOLD

## One fight, advanced. **Attacker-agnostic since R2a**: a dusk wolf and a den's
## pack wolf and a crypt's dead sentinel all run through this, because the
## consequence rules are policy and policy is what this file is. The only two
## places the kind still matters are what a corpse leaves behind and who owns
## the despawn -- both dispatched in `_remove_attacker`.
func _advance_engagement(e: Engagement, delta: float) -> void:
	var attacker = e.attacker
	if attacker == null or not is_instance_valid(attacker):
		_finish(e)
		return

	for result in e.tick(delta):
		var defender = result["defender"]
		# Both halves of the swap become floating numbers. This is a **read** of
		# the result Dictionary the exchange already returns -- `Engagement` is
		# not asked for anything new and `Combat` is not touched at all, which
		# is the whole point of the policy layer owning the announcements.
		#
		# Before the consequence checks below, deliberately: a unit that dies on
		# this exchange must still show the number that killed it, and
		# `_resolve_defeat` may remove it from the engagement.
		_show_hp_change(defender, result["damage_to_b"], "damage")
		_show_hp_change(attacker, result["damage_to_a"], "damage")
		# Consequences are checked per exchange, not per frame, so a unit can
		# never take two lethal hits before anyone notices.
		if not defender.is_alive():
			_resolve_defeat(defender, attacker)
			e.remove_defender(defender)
		elif defender is Follower and defender.hp_fraction() < Combat.FLEE_HP_FRACTION:
			_injure_and_flee(defender, attacker)
			e.remove_defender(defender)

	if not attacker.is_alive():
		# **Killed outright**, which is the good outcome and now pays for itself:
		# the body is left on the map as a carcass any labourer can gather. It
		# reuses the ordinary carcass node, so hauling a dead wolf home is the
		# same trip as hauling any other bones -- no new mechanic, and the
		# reward for defending the settlement is a real one. A den's pack wolves
		# leave one each too, at the *site's* location: a long carry from home,
		# which is the escort's problem to enjoy (LOOT_SITES_SPEC section 3b).
		for d in e.defenders:
			_leave_combat(d)
		if _leaves_a_carcass(attacker):
			_leave_carcass(attacker)
		attacker.leave_reason = "killed"
		_remove_attacker(attacker)
		_finish(e)
		return

	if attacker.should_flee():
		# Hurt but alive: it breaks off and leaves. No body, no bones -- driving
		# it away is the cheap win and killing it is the paying one. A pack wolf
		# that flees is gone for the run and its den counts it as dealt with,
		# which is what makes attrition across two visits a real tactic.
		for d in e.defenders:
			_leave_combat(d)
		attacker.depart("beaten off")
		if attacker is SiteGuardian:
			_remove_attacker(attacker)
		_finish(e)
		return

	if not e.has_defenders():
		# Everyone it was fighting is gone -- back to prowling, unless the fight
		# was the last thing it needed.
		attacker.clear_target()
		_finish(e)

## Only a corpse that was flesh leaves one. The wolf and a den's pack wolves do;
## a skeleton sentinel that was already dead has nothing left to gather, and an
## outlaw's body is Era-III business rather than a bone pile.
func _leaves_a_carcass(attacker) -> bool:
	if attacker is Wolf:
		return true
	return attacker is SiteGuardian and attacker.kind == "wolf"

## Who owns the despawn. The one place the attacker's kind still matters, and it
## is bookkeeping rather than policy: a dusk wolf leaves `wolves`, a guardian
## leaves its site -- and clearing the last one is what unlocks the den.
func _remove_attacker(attacker) -> void:
	if attacker is SiteGuardian:
		if world_sites:
			world_sites.remove_guardian(attacker, villain)
		else:
			attacker.queue_free()
		return
	_despawn(attacker)

## Drops a gatherable carcass where the wolf fell. Added to ResourceField the
## same way the seeded ones are, so the priority list, the crowding rules and
## the inspection panel all pick it up with no special casing -- a dead wolf is
## simply another pile of bones that happens to have arrived late.
func _leave_carcass(attacker) -> void:
	if resource_field == null:
		return
	var carcass := ResourceNode.make_carcass(attacker.position)
	carcass.capacity = WOLF_CARCASS_BONES
	carcass.remaining = WOLF_CARCASS_BONES
	# Drawn at the same size as the seeded carcasses, from their constant rather
	# than a literal: sizes are content heights now, and a bare 28.0 here was a
	# leftover canvas-width number that would have quietly meant something else.
	resource_field.add_node(carcass, ResourceField.SPRITE_CARCASS, "", ResourceField.NODE_SIZE_CARCASS)
	EventBus.wolf_killed.emit(attacker.position, WOLF_CARCASS_BONES)

func _finish(e: Engagement) -> void:
	e.finished = true
	for d in e.defenders:
		_leave_combat(d)
	_engagements.erase(e)

func _end_engagements_with(attacker) -> void:
	for e in _engagements.duplicate():
		if e.attacker == attacker:
			_finish(e)

## Rule 1. Only ever reached by a Worker -- a Follower is pulled out at 30% by
## _injure_and_flee well before hp hits zero, which is what makes "living
## recruits are never killed by wildlife" true by construction rather than by a
## check at the moment of death.
func _resolve_defeat(unit, attacker) -> void:
	_leave_combat(unit)
	if unit is Worker:
		unit.abandon_trip()
		worker_system.remove_worker(unit)
		EventBus.worker_destroyed.emit(unit, attacker.combat_name())
		return
	if unit is Necromancer:
		# **The branch that used to be missing.** Rule 4's header said outright
		# that there was no branch here for a villain losing a fight, and that
		# it would be "the run ends" when R4 arrived. Out in the world a
		# guardian can now actually kill him, so there has to be one -- and this
		# is deliberately all of it: `Necromancer.take_damage()` already emitted
		# `villain_died` (from the data object, so *anything* that can hurt him
		# announces it), Main logs it loudly, and the run lifecycle stays R4's.
		# `SORTIE_SPEC.md` section 6 owns clearing the unbanked haul, in R2c.
		return
	# Defensive: a Follower should never get here. If one does, treat it as an
	# injury rather than a death, so the design rule holds even if a future
	# caller skips the flee check.
	push_warning("CombatSystem: a Follower reached 0 hp -- injuring instead of killing.")
	unit.hp = 1
	_injure_and_flee(unit, attacker)

## Rule 2.
func _injure_and_flee(f, attacker) -> void:
	f.in_combat = false
	f.is_injured = true
	f.adjust_morale(-1)
	f.begin_flee()
	EventBus.morale_changed.emit(f, f.morale)
	EventBus.recruit_injured.emit(f, attacker.combat_name())

# ---------------- Hit-point maintenance ----------------

## Necromantic repair. Idle skeletons standing near the Throne slowly knit back
## together; living recruits heal from meals instead (MoraleSystem), which is
## the mechanical shape of "the undead don't eat" cutting both ways -- free to
## run, but they can only be mended at home.
func _tick_throne_repair(delta: float) -> void:
	if worker_system == null or settlement == null:
		return
	_repair_timer += delta
	if _repair_timer < THRONE_REPAIR_SECONDS:
		return
	_repair_timer -= THRONE_REPAIR_SECONDS
	var throne: Building = settlement.get_main_building()
	if throne == null:
		return
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	var throne_pos := Vector2(throne.cell.x * SettlementGrid.CELL_SIZE + half,
		throne.cell.y * SettlementGrid.CELL_SIZE + half)
	for w in worker_system.workers:
		if w.in_combat or w.hp >= w.max_hp():
			continue
		if w.stage != Laborer.TripStage.IDLE:
			continue
		if w.position.distance_to(throne_pos) <= THRONE_REPAIR_RADIUS_PX:
			# heal() returns what it actually restored, so a worker already at
			# max never floats a +0 -- the guard in _show_hp_change catches it
			# either way, but taking the real number is what makes that true.
			_show_hp_change(w, w.heal(1), "heal")

## The one place this system announces an hp change for the floating numbers
## (`CombatFeedback.gd`, COMBAT_FEEDBACK_SPEC §2).
##
## Funnelled through a single guard rather than emitted inline at each site so
## the "> 0" invariant is stated once. `Combat.MIN_DAMAGE` is 1 so a landed
## swing cannot be zero -- but a heal on a full-hp unit can be, and a future
## damage source might be, and a stream of "+0" over a healthy skeleton would
## be worse than no feedback at all.
##
## `unit` is the data object every caller already has in hand. The view reads
## its position when it draws.
func _show_hp_change(unit, amount: int, kind: String) -> void:
	if unit == null or amount <= 0:
		return
	EventBus.damage_shown.emit(unit, amount, kind)

# ---------------- Queries (HUD / smoke tests) ----------------

func active_wolf() -> Wolf:
	return wolves[0] if not wolves.is_empty() else null

func is_fighting() -> bool:
	return not _engagements.is_empty()
