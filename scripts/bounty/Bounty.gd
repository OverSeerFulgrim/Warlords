class_name Bounty
extends RefCounted
## A single posted bounty on the Bounty Board. Data-only -- BountyBoard owns
## the lifecycle (posted -> accepted -> resolved).

var bounty_name: String
var bounty_type: String  # "Harvest" or "Reanimation" for the Undead Empire prototype
## What it pays, in **bones**.
##
## Was Dark Essence, and it is not any more (LOOT_SITES_SPEC section 5,
## ROGUELITE_REWORK section 8): Dark Essence is field loot only -- exclusively
## found out in the world by the villain himself -- and a board at home that
## printed it was the largest of the three sources that made that a design goal
## rather than a fact. **Re-pointed rather than retired**, because "Harvest
## Corpses" paying bones is what the fiction said all along; the bounty layer
## keeps working and the exclusivity rule (section 1.1) becomes true.
var reward: int
var risk: int             # 0-10, rough danger/complication scale
var duration: float       # seconds to resolve, once accepted
var threat_on_complete: int = 0

func _init(p_name: String, p_type: String, p_reward: int, p_risk: int,
		p_duration: float, p_threat: int = 0) -> void:
	bounty_name = p_name
	bounty_type = p_type
	reward = p_reward
	risk = p_risk
	duration = p_duration
	threat_on_complete = p_threat

static func harvest_bounty(reward: int = 5, risk: int = 2) -> Bounty:
	return Bounty.new("Harvest Corpses", "Harvest", reward, risk, 8.0, 1)

static func reanimation_bounty(reward: int = 10, risk: int = 5) -> Bounty:
	return Bounty.new("Reanimate the Fallen", "Reanimation", reward, risk, 14.0, 3)
