extends Node
class_name DayNightCycle
## The day/night clock: phase timing, the lighting tint, and the debug time
## scale.
##
## Started life as the bare minimum needed to make FOUNDATION_SPEC section 5's
## dawn-triggered berry regrowth and deer respawn real (something had to emit
## `dawn_started`). This pass finished the rest of FOUNDATION_SPEC section 7's
## foundation cycle: the lighting tint shift is now here, and the clock reads
## out in the HUD.
##
## **Still not here:** the dawn/dusk *meal ticks* that feed living recruits.
## Those need the food/morale system (GAME_OUTLINE gap #3) and there are no
## living recruits to feed yet. They hang off `EventBus.dawn_started` /
## `dusk_started` when built -- which is why this emits signals rather than
## calling ResourceField._on_dawn() directly.
##
## Timings are FOUNDATION_SPEC section 7: day 30 min, night 20 min, 50 min
## full cycle. Long on purpose -- "tune after feel-testing", which is exactly
## what the time-scale control below is for.

const DAY_SECONDS: float = 30.0 * 60.0
const NIGHT_SECONDS: float = 20.0 * 60.0

## How long the tint takes to cross-fade at the start of each phase, and how
## long the label reads "Dawn"/"Dusk" rather than "Daylight"/"Night". 90s of a
## 30-minute day -- long enough to see happening, short enough that most of a
## phase is spent at its settled colour. At 60x this is a 1.5s fade.
const TRANSITION_SECONDS: float = 90.0

## Deliberately subtle. Night is a blue-shifted dimming, not a blackout -- the
## settlement still has to be readable, and skeleton labour works through the
## night regardless (FOUNDATION_SPEC section 7), so making night unplayable
## would punish the player for a mechanic that's meant to be an undead perk.
const DAY_TINT := Color(1.0, 1.0, 1.0)
const NIGHT_TINT := Color(0.52, 0.58, 0.82)

## Sub-phase, for the HUD label and the tint. DAWN/DUSK are the transition
## windows at the start of the day/night phases respectively.
enum Phase { DAWN, DAYLIGHT, DUSK, NIGHT }

## Debug speeds for the 1x/10x/60x toggle. 10x makes a gathering trip legible
## in seconds; 60x clears a whole 50-minute cycle in under a minute.
const TIME_SCALES: Array[float] = [1.0, 10.0, 60.0]

var is_day: bool = true
var elapsed_in_phase: float = 0.0
var day_number: int = 1
var time_scale_index: int = 0

var _canvas_modulate: CanvasModulate
## The colour the current cross-fade started from. Captured as the *actual*
## current tint rather than the previous phase's constant, so flipping phases
## mid-fade eases from wherever it got to instead of snapping back.
var _tint_from: Color = DAY_TINT
var _last_phase: int = Phase.DAYLIGHT

func _ready() -> void:
	# A CanvasModulate tints every CanvasItem in its canvas. This node is
	# parented under Main (a Node2D in the default canvas), so the settlement,
	# tokens and resource nodes all darken -- while the HUD, which lives in its
	# own CanvasLayer, deliberately does not. Dimming the UI at night would
	# make the game harder to read for no thematic gain.
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "DayNightTint"
	_canvas_modulate.color = DAY_TINT
	add_child(_canvas_modulate)
	set_process(true)

func _process(delta: float) -> void:
	elapsed_in_phase += delta
	var phase_length := DAY_SECONDS if is_day else NIGHT_SECONDS
	if elapsed_in_phase >= phase_length:
		elapsed_in_phase -= phase_length
		_advance_phase()
	_update_tint()
	_check_phase_label_changed()

func _advance_phase() -> void:
	_tint_from = _canvas_modulate.color if _canvas_modulate else DAY_TINT
	is_day = not is_day
	if is_day:
		day_number += 1
		EventBus.dawn_started.emit(day_number)
	else:
		EventBus.dusk_started.emit(day_number)

## Cross-fades toward the current phase's settled colour over
## TRANSITION_SECONDS, then holds. Runs off `elapsed_in_phase`, so it is driven
## by the same clock as everything else and inherits the time scale for free.
func _update_tint() -> void:
	if not _canvas_modulate:
		return
	var target := DAY_TINT if is_day else NIGHT_TINT
	var t := clampf(elapsed_in_phase / TRANSITION_SECONDS, 0.0, 1.0)
	_canvas_modulate.color = _tint_from.lerp(target, t)

## The HUD only needs redrawing when the *word* changes, not every frame, so
## the label is signal-driven rather than polled.
func _check_phase_label_changed() -> void:
	var phase := current_phase()
	if phase != _last_phase:
		_last_phase = phase
		EventBus.day_phase_changed.emit(phase_label())

func current_phase() -> int:
	var in_transition := elapsed_in_phase < TRANSITION_SECONDS
	if is_day:
		return Phase.DAWN if in_transition else Phase.DAYLIGHT
	return Phase.DUSK if in_transition else Phase.NIGHT

func phase_name() -> String:
	match current_phase():
		Phase.DAWN:
			return "Dawn"
		Phase.DAYLIGHT:
			return "Daylight"
		Phase.DUSK:
			return "Dusk"
		_:
			return "Night"

## e.g. "Day 2 — Dusk". The day counter keeps climbing through the night --
## night 2 is still part of day 2, so the number only advances at dawn.
func phase_label() -> String:
	return "Day %d — %s" % [day_number, phase_name()]

## Fraction through the current phase, 0.0-1.0.
func phase_progress() -> float:
	var phase_length := DAY_SECONDS if is_day else NIGHT_SECONDS
	return clampf(elapsed_in_phase / phase_length, 0.0, 1.0)

func current_tint() -> Color:
	return _canvas_modulate.color if _canvas_modulate else DAY_TINT

# ---------------- Debug time scale ----------------

## Steps 1x -> 10x -> 60x -> 1x and returns the new scale.
##
## This sets `Engine.time_scale`, which multiplies the `delta` handed to every
## `_process`/`_physics_process` in the game. **Every timer in this project is
## a delta accumulator** -- this clock, `WorkerSystem`'s trip loop,
## `Building`'s resource tick, `EventSystem`'s event timer -- so they all
## inherit the scaling with no per-system plumbing, and stay in sync with each
## other by construction. Godot also scales `SceneTreeTimer` and `Tween` by it,
## so nothing in the codebase is left running at wall-clock speed.
##
## The one thing it does NOT scale is real input and rendering, which is what
## makes it usable as a debug control rather than a gameplay feature.
func cycle_time_scale() -> float:
	time_scale_index = (time_scale_index + 1) % TIME_SCALES.size()
	Engine.time_scale = TIME_SCALES[time_scale_index]
	return Engine.time_scale

func set_time_scale_index(index: int) -> void:
	time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)
	Engine.time_scale = TIME_SCALES[time_scale_index]

func time_scale_label() -> String:
	return "%dx" % int(TIME_SCALES[time_scale_index])
