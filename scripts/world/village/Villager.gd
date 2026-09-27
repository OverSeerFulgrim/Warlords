class_name Villager
extends Laborer
## One person of the village (LIVING_WORLD_SPEC section 5): a name, a job, a
## house, and the same trip loop the player's skeletons run.
##
## **The job, not the stats** (section 5.3, the Randy rule). Re-staffing moves a
## villager between jobs and changes nothing else: Randy the Woodcutter who takes
## up a spear is *Randy (Guard)* with a woodcutter's arms until the Guardhouse
## has trained him. `trained` is what training buys, and it is the only thing
## that changes the numbers.
##
## **A Combatant in the attacker slot.** Everything that fights the Necromancer
## sits in an `Engagement`'s attacker slot (wolves, guardians); a villager he
## hunts does too, so CombatSystem needs the four attacker members wolves and
## guardians already have -- `should_flee`, `depart`, `clear_target`,
## `leave_reason`.

const RACE_ID := "human_peasant"

## How much of his health a villager will trade before he breaks and runs --
## by role first, individual second (section 11.1). Farmers and woodcutters
## break at the first blow; a trained guard holds to the end of his nerve; an
## untrained one breaks like the woodcutter he was.
const BREAK_AT := {"farmer": 0.95, "woodcutter": 0.95, "": 0.95, "guard": 0.3}
const UNTRAINED_BREAK_AT: float = 0.95

## What the Guardhouse's training adds (the guard skill template): the warrior
## skills and a soldier's arm. Applied once, when training completes.
const GUARD_TRAINING := {"strength": 2, "endurance": 1}

var villager_name: String = ""
## "farmer", "woodcutter", "guard", or "" (no job -- forages at random).
var job: String = ""
## The VillageBuilding he works for, and the one he lives in.
var workplace = null
var house = null
## True once a guard has finished his training at the Guardhouse.
var trained: bool = false
## Seconds of training still owed, while he is a guard who is not yet trained.
var training_left: float = 0.0
## Running from a fight: he stops hitting back (see combat_profile) and heads
## for his house. Cleared when he gets there.
var panicked: bool = false
## Seconds of calm he needs, safe at home, before he stops being panicked. A
## man who broke does not walk back out the moment he reaches his door --
## and while he cowers there he is still in reach.
const CALM_SECONDS: float = 20.0
var calm_left: float = 0.0
## Set by CombatSystem when he leaves a fight -- "beaten off", "killed" ...
var leave_reason: String = ""
## Set when he dies, so a stale reference can never be counted twice.
var dead: bool = false

## **A witness with somewhere to be** (LIVING_WORLD section 8.1). While set, he
## is running for this point -- the Guardhouse or the Guild -- with `report`, and
## his "!" is up. Standing drops only when he gets there.
var runner_to: Vector2 = Vector2.ZERO
var report: Dictionary = {}

func start_run(dest: Vector2, p_report: Dictionary) -> void:
	abandon_trip()
	runner_to = dest
	report = p_report

func is_running_to_tell() -> bool:
	return runner_to != Vector2.ZERO

func _init(p_name: String = "Villager", p_job: String = "") -> void:
	villager_name = p_name
	job = p_job
	apply_race_baseline(RACE_ID)
	heal_full()

func display_name() -> String:
	return villager_name

## "Frank (Farmer)" -- the label the village reads its losses by (section 5.6).
func label() -> String:
	return "%s (%s)" % [villager_name, job_title()]

func job_title() -> String:
	match job:
		"farmer": return "Farmer"
		"woodcutter": return "Woodcutter"
		"guard": return "Guard" if trained or training_left <= 0.0 else "Guard, untrained"
		_: return "Villager"

## Changes the job and nothing else -- the Randy rule. A new guard owes his
## training; anyone leaving the guard loses the claim to it.
func assign(new_job: String, building, train_seconds: float) -> void:
	if new_job == job and building == workplace:
		return
	abandon_trip()
	job = new_job
	workplace = building
	if job == "guard" and not trained:
		training_left = train_seconds

func finish_training() -> void:
	if trained:
		return
	trained = true
	training_left = 0.0
	strength += int(GUARD_TRAINING["strength"])
	endurance += int(GUARD_TRAINING["endurance"])
	var warrior: Dictionary = RaceCatalog.skill_templates().get("warrior", {})
	if not warrior.is_empty():
		skills = warrior.duplicate()
	heal_full()

func is_guard() -> bool:
	return job == "guard"

func is_armed() -> bool:
	return job == "guard" and trained

# ---------------- The attacker-slot members CombatSystem reads -----------------

## Running people do not fight back. Their attack attribute goes to zero, so the
## shared formula still lands its minimum on the Necromancer (Combat.MIN_DAMAGE)
## -- a flailing arm, not a blow -- without Combat.gd learning anything new.
func combat_profile() -> Dictionary:
	var p: Dictionary = super.combat_profile()
	if panicked or is_running_to_tell():
		p["attack_attr"] = 0
	return p

func should_flee() -> bool:
	if panicked or is_running_to_tell():
		return false   # already running; the fight ends when he gets out of reach
	var at: float = float(BREAK_AT.get(job, 0.95))
	if job == "guard" and not trained:
		at = UNTRAINED_BREAK_AT
	return hp_fraction() < at

## Breaks off. He does not leave the map -- he runs home, which is where the
## village learns what happened.
func depart(reason: String) -> void:
	leave_reason = reason
	panicked = true
	calm_left = CALM_SECONDS
	begin_flee()

func clear_target() -> void:
	pass

func can_work_now() -> bool:
	return not panicked and not dead

# ---------------- Inspection ----------------

func inspect_race_id() -> String:
	return RACE_ID

func inspect_category() -> String:
	return job_title()

func inspect_subtitle() -> String:
	var where: String = ""
	if workplace:
		where = " — %s" % workplace.display_name
	return "%s%s" % [job_title(), where]

func inspect_description() -> String:
	match job:
		"farmer": return "Works the fields for the village's food. Walks out at dawn and back with what he cut."
		"woodcutter": return "Cuts at the treeline north of the village and carries it to the mill."
		"guard":
			if trained:
				return "Walks the village's rounds. He has been trained, and he will stand."
			return "A spear somebody handed him. He has not been trained yet, and he will break like anyone."
		_: return "Has no job. Goes out for berries now and then and is the first to see anything."

func inspect_extra_rows() -> Array:
	var rows: Array = [{"label": "Job", "value": job_title()}]
	if house:
		rows.append({"label": "Lives", "value": house.display_name})
	if job == "guard" and not trained:
		rows.append({"label": "Training", "value": "%d s left at the Guardhouse" % int(ceil(training_left))})
	if is_running_to_tell():
		rows.append({"label": "!", "value": "He saw %s — and he is running to tell." % String(report.get("act", "something")),
			"color": Color(1.0, 0.45, 0.35)})
	elif panicked:
		rows.append({"label": "", "value": "Running for home.", "color": Color(1.0, 0.7, 0.4)})
	return rows
