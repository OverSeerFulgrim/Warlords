extends Node
class_name TravelLog
## Times the Necromancer's journeys, so travel pacing is a **measurement rather
## than a feeling**.
##
## WORLD_MAP_PLAN §3 sets targets in seconds, not cells -- "lair to the human
## village: 2-4 minutes" -- and the only way to tell whether the map hits them
## is to time real walks. This watches the villain, notices when he leaves the
## lair band and when he first reaches each registered landmark, and logs the
## elapsed time against the target band.
##
## It measures **game seconds**, taken from `delta`, so it inherits the debug
## time scale like every other clock in the project: a 60x run reports the same
## numbers as a 1x run, which is what makes measuring a four-minute journey
## practical.
##
## R1's exit criterion is "walk from the lair to the village and back inside the
## travel-time targets". This is the thing that answers it.

## Landmark -> the §3 target band, in seconds. A landmark with no entry is still
## timed; it just reports without a verdict.
const TARGETS := {
	"lair_exit": Vector2(45.0, 75.0),          # lair -> edge of local territory
	"nearby_resource": Vector2(10.0, 20.0),
	"first_landmark": Vector2(20.0, 40.0),     # stands in for §3's "first worthwhile encounter"
	"village": Vector2(120.0, 240.0),
	"crossing": Vector2(180.0, 300.0),
}

## How close counts as arrived, in cells.
const ARRIVAL_CELLS: float = 2.5

var world: WorldMap = null
var villain: Necromancer = null
## name -> engine-space position. Filled from WorldSites' landmarks.
var landmarks: Dictionary = {}

## Seconds since he last left the lair band. Negative means he's home.
var _elapsed: float = -1.0
var _was_home: bool = true
var _reached: Dictionary = {}     # landmark name -> seconds on this trip
var _trip_count: int = 0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if world == null or villain == null:
		return
	var home: bool = world.lair_band.has_point(world.cell_at(villain.position))
	if home:
		if not _was_home and _elapsed > 0.0:
			_log("Home. Round trip %s." % _fmt(_elapsed))
			_report("round_trip", _elapsed)
		_was_home = true
		_elapsed = -1.0
		_reached.clear()
		return

	if _was_home:
		_was_home = false
		_trip_count += 1
		_elapsed = 0.0
		_log("Left the lair band.")
	_elapsed += delta

	var reach: float = ARRIVAL_CELLS * float(WorldMap.CELL_SIZE)
	for label in landmarks.keys():
		if _reached.has(label):
			continue
		if villain.position.distance_to(landmarks[label]) <= reach:
			_reached[label] = _elapsed
			_log("Reached %s in %s." % [label, _fmt(_elapsed)])

## Elapsed on the current outing, or -1 at home. Read by the HUD.
func elapsed() -> float:
	return _elapsed

func trips() -> int:
	return _trip_count

func _report(key: String, seconds: float) -> void:
	if not TARGETS.has(key):
		return
	var band: Vector2 = TARGETS[key]
	var verdict: String = "in band"
	if seconds < band.x:
		verdict = "FAST (under %s)" % _fmt(band.x)
	elif seconds > band.y:
		verdict = "SLOW (over %s)" % _fmt(band.y)
	print("[travel] %s: %s -- %s" % [key, _fmt(seconds), verdict])

func _log(text: String) -> void:
	EventBus.travel_noted.emit(text, maxf(0.0, _elapsed))

static func _fmt(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0fs" % seconds
	return "%dm %02ds" % [int(seconds) / 60, int(seconds) % 60]
