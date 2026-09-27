class_name ActionBar
extends HBoxContainer
## **His actions, bottom centre** (the HUD redo, 2026-09-26). Each button
## appears the first time its mechanic does:
##
## | Button | Key | Appears |
## | Raise Dead | R | always -- his first spell |
## | Items | I | always |
## | Escort | E | once he has any dead |
## | Rally point | C | once he has three dead to command |
## | Build | B | once he knows a blueprint |
##
## Polled (a quarter second) rather than signalled: every condition is a count
## that changes in several places. The bar never decides anything -- each press
## is a signal Main answers.

signal raise_pressed
signal items_pressed
signal escort_pressed
signal rally_pressed
signal build_pressed

const RALLY_AFTER := 3

var villain: Necromancer = null
var worker_system: WorkerSystem = null
var undead_command: UndeadCommand = null
## `func() -> bool`: does he know any blueprint?
var knows_blueprints: Callable = Callable()

var raise_btn: Button
var items_btn: Button
var escort_btn: Button
var rally_btn: Button
var build_btn: Button
var _tick: float = 0.0

func _init() -> void:
	add_theme_constant_override("separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER
	raise_btn = _make("Raise Dead", "raise_dead", true)
	raise_btn.pressed.connect(func(): raise_pressed.emit())
	escort_btn = _make("Escort", "escort", true)
	escort_btn.pressed.connect(func(): escort_pressed.emit())
	rally_btn = _make("Rally point", "rally", true)
	rally_btn.pressed.connect(func(): rally_pressed.emit())
	items_btn = _make("Items", "items", false)
	items_btn.pressed.connect(func(): items_pressed.emit())
	build_btn = _make("Build", "build", false)
	build_btn.pressed.connect(func(): build_pressed.emit())

func _make(title: String, action: String, accent: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(136, 60)
	HudStyle.style_button(b, accent, 15)
	b.set_meta("title", title)
	b.set_meta("action", action)
	b.text = "%s\n%s" % [title, Controls.label_for(action)]
	add_child(b)
	return b

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	refresh()

func dead_count() -> int:
	if worker_system == null:
		return 0
	var n: int = 0
	for w in worker_system.workers:
		if w.is_alive():
			n += 1
	return n

func refresh() -> void:
	var cost: int = int(WorkerSystem.RECRUIT_COST.get("bones", 0))
	var afford: bool = GameState.can_afford_cost(WorkerSystem.RECRUIT_COST)
	raise_btn.text = "Raise Dead\n%s · %d bones%s" % [Controls.label_for("raise_dead"), cost,
		"" if afford else " (you have %d)" % GameState.bones]
	raise_btn.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.6)
	raise_btn.tooltip_text = "A skeleton claws its way out of the ground at his feet. A grave's corpse is free — open a grave and choose Raise the corpse."
	var n: int = dead_count()
	escort_btn.visible = n > 0
	if escort_btn.visible and undead_command:
		var on: bool = undead_command.is_active() and undead_command.rally_point.is_escorting()
		escort_btn.text = "Escort\n%s · %s" % [Controls.label_for("escort"), "on" if on else "off"]
	rally_btn.visible = n >= RALLY_AFTER
	if villain:
		items_btn.text = "Items\n%s · %d / %d" % [Controls.label_for("items"), villain.carried_total(), villain.carry_capacity()]
	build_btn.visible = knows_blueprints.is_valid() and bool(knows_blueprints.call())
