extends Node
class_name BountyBoard
## Majesty-style indirect control: the player posts bounties here instead of
## commanding followers directly. On a timer, idle followers each decide
## (Follower.evaluate_bounty) whether a posted bounty is worth answering.

var open_bounties: Array = []      # Array[Bounty] not yet accepted
var active_bounties: Array = []    # Array[Dictionary] {bounty, follower, time_left}

@export var evaluation_interval: float = 2.0
var _eval_timer: float = 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_eval_timer += delta
	if _eval_timer >= evaluation_interval:
		_eval_timer = 0.0
		_run_follower_evaluation()
	_tick_active_bounties(delta)

func post_bounty(bounty: Bounty) -> void:
	open_bounties.append(bounty)
	EventBus.bounty_posted.emit(bounty)

func _run_follower_evaluation() -> void:
	if open_bounties.is_empty():
		return
	for follower in GameState.followers:
		if follower.is_busy:
			continue
		for bounty in open_bounties.duplicate():
			if follower.evaluate_bounty(bounty):
				_accept_bounty(bounty, follower)
				break  # this follower is now busy; move to the next follower

func _accept_bounty(bounty: Bounty, follower: Follower) -> void:
	open_bounties.erase(bounty)
	follower.is_busy = true
	active_bounties.append({"bounty": bounty, "follower": follower, "time_left": bounty.duration})
	EventBus.bounty_accepted.emit(bounty, follower)

func _tick_active_bounties(delta: float) -> void:
	for entry in active_bounties.duplicate():
		entry["time_left"] -= delta
		if entry["time_left"] <= 0.0:
			_resolve_bounty(entry)

func _resolve_bounty(entry: Dictionary) -> void:
	var bounty: Bounty = entry["bounty"]
	var follower: Follower = entry["follower"]
	active_bounties.erase(entry)
	follower.is_busy = false

	# Simple success roll for the prototype: higher risk = lower success chance.
	var success_chance: float = clamp(1.0 - (float(bounty.risk) / 12.0), 0.15, 0.95)
	var success: bool = randf() <= success_chance

	if success:
		GameState.add_resource("dark_essence", bounty.reward)
		GameState.add_threat(bounty.threat_on_complete)
	else:
		# Failure still raises Threat (something went wrong out there) but pays nothing.
		GameState.add_threat(bounty.threat_on_complete * 2)

	EventBus.bounty_completed.emit(bounty, follower, success)
