extends Node
class_name ThreatSystem
## Maps GameState's Threat tier to the "who's coming for you" response ladder
## from the design doc, and owns the High-Threat Crusade climax: a timed
## window the player must survive (defensive prep, not a certainty) to
## satisfy half of the "both" win condition.

# NOTE: matches GameState.ThreatTier enum order (LOW=0, MEDIUM=1, HIGH=2).
# Using plain ints here rather than referencing GameState.ThreatTier.* directly
# to avoid any cross-script const-resolution ordering issues at parse time.
const RESPONSES := {
	0: {  # LOW
		"name": "Quiet",
		"flavor": "A lone bounty hunter or witch hunter might sniff around. Easy to ignore or bribe away.",
	},
	1: {  # MEDIUM
		"name": "Noticed",
		"flavor": "A mercenary company or a Paladin Order chapter is taking an interest. Time to prepare defenses, or lay low.",
	},
	2: {  # HIGH
		"name": "Crusade",
		"flavor": "A full Holy Crusade marches on your settlement. This is the climax -- survive it.",
	},
}

@export var crusade_window_seconds: float = 60.0
var _crusade_timer: float = 0.0
var _crusade_active: bool = false

## Set by Main.gd after construction (same pattern as EventSystem.settlement).
## The Crusade now damages the player's actual main building instead of just
## checking an abstract Power number -- losing your home is the real fail
## state, per the "Crusade defense target" design call.
var settlement: SettlementGrid

func _ready() -> void:
	EventBus.threat_tier_escalated.connect(_on_tier_escalated)
	EventBus.crusade_incoming.connect(_on_crusade_incoming)
	set_process(false)

func _process(delta: float) -> void:
	if not _crusade_active:
		return
	_crusade_timer -= delta
	if _crusade_timer <= 0.0:
		_resolve_crusade()

func _on_tier_escalated(new_tier: int) -> void:
	var info: Dictionary = RESPONSES[new_tier]
	print("[Threat] Tier -> %s: %s" % [info["name"], info["flavor"]])

func _on_crusade_incoming() -> void:
	print("[Threat] CRUSADE INCOMING. %d seconds to prepare/survive." % crusade_window_seconds)
	_crusade_active = true
	_crusade_timer = crusade_window_seconds
	set_process(true)

const CRUSADE_POWER_BAR: int = 30

func _resolve_crusade() -> void:
	_crusade_active = false
	set_process(false)

	# Power shortfall translates into damage against the main building rather
	# than a flat pass/fail -- a settlement that's under-prepared takes a
	# beating but might still hold if the main building has enough hp banked.
	var shortfall: int = max(0, CRUSADE_POWER_BAR - GameState.power)
	var main_building: Building = settlement.get_main_building() if settlement else null

	if main_building == null:
		# Shouldn't happen post-seeding, but fail safe to the old power-only
		# check rather than crashing if something placed it wrong.
		push_warning("[Threat] No main building found -- falling back to Power-only check.")
		if shortfall == 0:
			GameState.mark_crusade_survived()
			EventBus.crusade_survived.emit()
		else:
			GameState.lose_game("Crusade overwhelmed the settlement (Power %d < %d)." % [GameState.power, CRUSADE_POWER_BAR])
		return

	var damage: int = shortfall * 2
	main_building.hp = max(0, main_building.hp - damage)
	# hp is mutated directly here rather than through a GameState setter (no
	# such thing exists for building hp), so nothing else knows it changed
	# unless we say so -- the stats bar's "Home: x/y hp" readout would
	# otherwise sit stale until an unrelated stat happened to redraw it.
	EventBus.main_building_damaged.emit(main_building)
	print("[Threat] Crusade strikes the %s for %d damage (hp %d/%d)." % [main_building.display_name, damage, main_building.hp, main_building.max_hp])

	if main_building.hp <= 0:
		print("[Threat] The settlement falls.")
		GameState.lose_game("The %s was overrun by the Crusade." % main_building.display_name)
	else:
		print("[Threat] The settlement holds. Crusade repelled.")
		GameState.mark_crusade_survived()
		EventBus.crusade_survived.emit()
