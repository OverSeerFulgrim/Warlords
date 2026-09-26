extends Node
class_name Raven
## The bird that never lies (`RAVEN_SPEC.md`, R2e).
##
## A passive ping system and nothing else: at dawn the Raven may name one minor,
## undiscovered, reachable, unguarded site that still has something in it. No
## token, no directives, **no fog interaction at all** -- a ping is a marker drawn
## above the fog, never a reveal.
##
## ## Per villain, holding everything as fields
##
## `villain`, `world_sites` and `fog` are handed in (ROGUELITE_REWORK section
## 11). A second villain gets a second familiar with its own pings.
##
## ## The honesty invariant is the whole design
##
## Section 4: at the moment of pinging, the site is reachable, Band 1-2,
## unguarded and unoccupied, undiscovered, and has a charge. If nothing
## qualifies the Raven says nothing -- and, per the 2026-08-29 amendment, says
## that it said nothing: the chip flickers and the log reads "the near country
## is picked clean". Silence is information. No condition is ever relaxed to
## make content.

const RAVEN_PING_CHANCE_PERCENT: int = 70
const MAX_OUTSTANDING_PINGS: int = 3

var villain: Necromancer = null
var world_sites: WorldSites = null
var fog: FogOfWar = null
## Where the markers live -- the settlement's coordinate space, above the fog.
var marker_parent: Node = null

## `{site, day_found, seen, claimed, marker}`, oldest first. Claimed pings are
## dropped from the list; the count that matters is `outstanding()`.
var pings: Array = []

## Own RNG, so a harness can seed the Raven without seeding the world.
var rng := RandomNumberGenerator.new()

## Which ping the HUD chip showed last, for cycling.
var _cycle: int = -1

func _ready() -> void:
	rng.randomize()
	EventBus.dawn_started.connect(_on_dawn)
	EventBus.site_looted.connect(_on_site_looted)

func outstanding() -> int:
	return pings.size()

func unseen() -> int:
	var n: int = 0
	for p in pings:
		if not bool(p["seen"]):
			n += 1
	return n

# ---------------- Dawn --------------------------------------------------------

func _on_dawn(day: int) -> void:
	dawn(day)

## One dawn. Returns the pinged site, or null. Public so the harness can run a
## thousand of them without a day passing.
func dawn(day: int):
	_clear_spent()
	# At the cap the bird stops finding things (section 3). No roll, no silence
	# line: the chip already says there is news waiting.
	if outstanding() >= MAX_OUTSTANDING_PINGS:
		return null
	if rng.randi_range(1, 100) > RAVEN_PING_CHANCE_PERCENT:
		return null   # a day without news, which is allowed to exist
	var candidates: Array = world_sites.undiscovered_eligible() if world_sites else []
	# Never name a site already pinged.
	candidates = candidates.filter(func(s): return not _is_pinged(s))
	if candidates.is_empty():
		EventBus.raven_silent.emit(villain, day)
		return null
	var site = candidates[rng.randi_range(0, candidates.size() - 1)]
	var marker := RavenMarker.new()
	marker.name = "RavenMark_%s" % site.site_id
	marker.setup(self, site, day)
	if marker_parent:
		marker_parent.add_child(marker)
	pings.append({"site": site, "day_found": day, "seen": false, "claimed": false, "marker": marker})
	EventBus.raven_pinged.emit(villain, site)
	return site

func _is_pinged(site) -> bool:
	for p in pings:
		if p["site"] == site:
			return true
	return false

# ---------------- Seen, claimed -----------------------------------------------

## The HUD chip's click: newest unseen first, then walk the rest. Returns the
## site to centre on, or null when there is nothing outstanding.
func next_for_chip():
	if pings.is_empty():
		return null
	var pick: int = -1
	for i in range(pings.size() - 1, -1, -1):
		if not bool(pings[i]["seen"]):
			pick = i
			break
	if pick < 0:
		_cycle = (_cycle + 1) % pings.size()
		pick = _cycle
	else:
		_cycle = pick
	var p: Dictionary = pings[pick]
	if not bool(p["seen"]):
		p["seen"] = true
		EventBus.raven_ping_seen.emit(villain, p["site"])
	return p["site"]

func marker_for(site) -> Node2D:
	for p in pings:
		if p["site"] == site:
			return p["marker"]
	return null

## Looting a pinged site claims it: the marker clears (section 3).
func _on_site_looted(who, site, _loot: Dictionary) -> void:
	if who != villain:
		return
	_claim(site)
	_clear_spent()

func _claim(site) -> void:
	for p in pings.duplicate():
		if p["site"] == site:
			p["claimed"] = true
			if is_instance_valid(p["marker"]):
				p["marker"].queue_free()
			pings.erase(p)
			EventBus.raven_ping_claimed.emit(villain, site)

## A pinged grave raised rather than robbed still spends its charge without a
## `site_looted`; anything with nothing left in it is claimed, not left standing.
func _clear_spent() -> void:
	for p in pings.duplicate():
		var s = p["site"]
		if not is_instance_valid(s) or s.charges_left <= 0:
			_claim(s)

## Engine-space points for the minimap.
func minimap_points() -> Array:
	var out: Array = []
	for p in pings:
		if is_instance_valid(p["site"]):
			out.append(p["site"].position)
	return out

## A click on the world that lands on a marker. Markers are above the fog, so
## this is asked before the fog check.
func pick_at(world_pos: Vector2) -> Node2D:
	for p in pings:
		var m = p["marker"]
		if is_instance_valid(m) and world_pos.distance_to(m.position) <= RavenMarker.HIT_RADIUS:
			return m
	return null
