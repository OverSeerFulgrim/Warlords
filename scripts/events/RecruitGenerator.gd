class_name RecruitGenerator
extends RefCounted
## Rolls the individual recruits that turn up at the Barracks.
##
## Replaces the old `data/followers.json` template lookup, which had a handful
## of hand-written archetypes ("orc_warband", "fallen_paladin") with flat
## min/max stat ranges. Recruits now come off the **race roster**
## (`data/races.json`) with per-individual variance, so the same race can turn
## up twice and be meaningfully different -- which is what makes looking at a
## recruit's numbers worth doing at all.
##
## Three rules, all from FOUNDATION_SPEC section 3 and RACES.md, all driven by
## `data/recruitment.json` rather than branches in here:
##   1. **Which race** -- weighted by rarity, and the weights shift toward
##      Uncommon/Rare as settlement Power grows ("power attracts power").
##   2. **What numbers** -- `clamp(baseline + d3 - d3, 1, 10)` per stat/skill,
##      a centre-weighted spread so most recruits sit near baseline.
##   3. **First-run guarantee** -- the first three offers span Warrior,
##      Economy and Research so a new player sees the full scope.
##
## Owned by EventSystem (one instance), because the first-run guarantee needs
## to remember how many offers have been made -- this is not a static utility.

## How many offers have been generated this run. Drives the first-run
## category guarantee; deliberately counts *offers*, not acceptances, so
## turning the first orc away still burns the warrior slot -- you were shown
## the category, which is what the guarantee promises.
var offers_made: int = 0

const NAME_POOLS := {
	"orc": ["Grosh", "Uzgar", "Thokk", "Mogrim", "Vraka", "Durgash"],
	"hobgoblin": ["Karruk", "Vess", "Dromm", "Skarn", "Ghelt"],
	"ogre": ["Bruk", "Gorm", "Hodd", "Mulch", "Tarn"],
	"troll": ["Grendl", "Vurm", "Skoll", "Hagr", "Bront"],
	"gray_dwarf": ["Durin", "Balgrim", "Thrain", "Norra", "Kazek"],
	"kobold": ["Yip", "Skit", "Nix", "Trundle", "Grib"],
	"minotaur": ["Asterion", "Kerath", "Bovar", "Talos", "Mirek"],
	"mountain_dwarf": ["Brenna", "Hodrin", "Sigrun", "Tovald", "Fenna"],
	"gnome": ["Fizwick", "Tobble", "Wimsy", "Pertwee", "Bramwell"],
	"dark_elf": ["Ilyndra", "Vexis", "Thalorin", "Nyssara", "Corvenn"],
	"high_elf": ["Aelrin", "Sylwen", "Faeloth", "Elowen", "Maerith"],
	"goblin": ["Snik", "Rattle", "Miri", "Dregg", "Wisp"],
	"gnoll": ["Rakka", "Hessk", "Yenna", "Vurgul", "Skarrow"],
	"halfling": ["Poppy", "Merric", "Rosie", "Bandon", "Tilly"],
	"human_outcast": ["Cass", "Roderic", "Wren", "Halden", "Mira"],
}

## Small shared pool -- traits are not race-specific yet (race passives are
## deferred until after Stage 4, per RACES.md "Settled decisions").
const TRAIT_POOL := ["Loyal", "Greedy", "Bloodthirsty", "Cowardly", "Fanatic"]

## Builds one recruit and returns it. Does NOT add it to GameState -- the
## caller decides whether the player accepted the offer.
func generate() -> Follower:
	var race_id := _pick_race_id()
	offers_made += 1
	if race_id == "":
		push_warning("RecruitGenerator: no recruitable race found -- check races.json.")
		return null
	return _build_follower(race_id)

## Which race turns up. First `first_run_categories.size()` offers are dealt
## from the guarantee list in order; everything after is weighted-random across
## the whole recruitable roster.
func _pick_race_id() -> String:
	var guarantee: Array = RaceCatalog.first_run_categories()
	if offers_made < guarantee.size():
		var cat: String = guarantee[offers_made]
		var pool: Array = RaceCatalog.ids_in_category(cat)
		if not pool.is_empty():
			# Still rarity-weighted *within* the guaranteed category, so the
			# guarantee shapes which category shows up, not which race.
			return _weighted_pick(pool)
		push_warning("RecruitGenerator: first-run category '%s' has no recruitable races." % cat)
	return _weighted_pick(_all_recruitable())

func _all_recruitable() -> Array:
	return RaceCatalog.recruitable_ids()

## Roulette-wheel pick over `race_ids`, weighted by each race's rarity band at
## the settlement's current Power. A race whose rarity string isn't in the
## weight table gets weight 0 rather than silently defaulting to something --
## that way a typo in races.json shows up as "this race never appears" instead
## of quietly skewing the whole distribution.
func _weighted_pick(race_ids: Array) -> String:
	if race_ids.is_empty():
		return ""
	var weights: Dictionary = RaceCatalog.rarity_weights_for_power(GameState.power)
	var total: float = 0.0
	var entries: Array = []
	for id in race_ids:
		var w: float = float(weights.get(RaceCatalog.rarity(id), 0))
		if w <= 0.0:
			continue
		total += w
		entries.append({"id": id, "cumulative": total})
	if entries.is_empty():
		return race_ids[randi() % race_ids.size()]
	var roll: float = randf() * total
	for e in entries:
		if roll <= e["cumulative"]:
			return e["id"]
	return entries[entries.size() - 1]["id"]

func _build_follower(race_id: String) -> Follower:
	var cat: String = RaceCatalog.category(race_id)

	# Nine attributes and twelve skills, each rolled independently off the race
	# baseline. Same d3-d3 spread as before -- what widened is the number of
	# things it rolls, not how any one of them rolls.
	var attributes: Dictionary = {}
	for key in RaceCatalog.attributes(race_id).keys():
		attributes[key] = _roll(RaceCatalog.attribute(race_id, key))

	var f := Follower.new(_pick_name(race_id), RaceCatalog.get_race(race_id).get("display_name", race_id),
		_pick_traits(), attributes)
	f.race_id = race_id
	f.category = cat
	f.rarity = RaceCatalog.rarity(race_id)
	# Skill baselines and walk speed live on Laborer. Walk speed is a racial
	# constant with no per-recruit variance (FOUNDATION_SPEC section 3) -- and
	# since the C2 rework it is derived from the Speed attribute, so rolling it
	# here would put a recruit's legs at odds with their own statline.
	var skills: Dictionary = {}
	for key in RaceCatalog.all_skill_names():
		skills[key] = _roll(RaceCatalog.skill_baseline(race_id, key))
	f.skills = skills
	f.walk_speed = RaceCatalog.walk_speed(race_id)

	_maybe_make_exceptional(f, cat)
	# Re-top-up after the exceptional roll: it can land on Endurance, which
	# raises max_hp by 2, and a recruit should not arrive already two points
	# short of full.
	f.heal_full()
	return f

## FOUNDATION_SPEC section 3: value = clamp(baseline + d3 - d3, 1, 10).
func _roll(baseline: int) -> int:
	var cfg: Dictionary = RaceCatalog.stat_roll_config()
	var sides: int = int(cfg.get("dice_sides", 3))
	var lo: int = int(cfg.get("min_value", 1))
	var hi: int = int(cfg.get("max_value", 10))
	return clampi(baseline + randi_range(1, sides) - randi_range(1, sides), lo, hi)

## 5% chance of +1 to the race's category-defining **attribute**, applied after
## the roll.
##
## The rework moved the target from a stat to the attribute that defines the
## category (COMBAT_SPEC section 2.1's consumer table): Warrior to Strength,
## Research to Intelligence, Foraging to Perception. `best_labor_attribute`
## resolves per individual -- an Economy race's defining trait is being good at
## *its* speciality, which differs by race (a Gray Dwarf mines, a Minotaur chops
## and mines about equally), so it finds that recruit's best labor skill and
## bumps whichever attribute governs it.
##
## Bumping the attribute rather than the skill is what makes the star mean
## something beyond one job: +1 Strength is a better miner *and* a harder hit,
## which is the whole reason attributes and skills are separate layers.
func _maybe_make_exceptional(f: Follower, cat: String) -> void:
	if randf() * 100.0 > RaceCatalog.exceptional_chance_percent():
		return
	var target: String = RaceCatalog.defining_stat_for_category(cat)
	if target == "best_labor_attribute":
		target = RaceCatalog.governing_attribute(_best_labor_skill(f))
	if target == "" or target == "none":
		return  # Versatile/Labor have no defining attribute, and no star
	f.apply_attributes({target: mini(10, f.attribute(target) + 1)})
	f.is_exceptional = true

## Whichever of the labor-ish skills this individual actually rolled highest.
## Effective rather than baseline, because that is the one they are visibly best
## at once they start work.
func _best_labor_skill(f: Follower) -> String:
	var best: String = "foraging"
	var best_value: int = -1
	for key in RaceCatalog.all_skill_names():
		var v: int = f.skill_for(key)
		if v > best_value:
			best_value = v
			best = key
	return best

func _pick_name(race_id: String) -> String:
	var pool: Array = NAME_POOLS.get(race_id, [])
	if pool.is_empty():
		return race_id.capitalize()
	return pool[randi() % pool.size()]

func _pick_traits() -> Array[String]:
	var pool := TRAIT_POOL.duplicate()
	pool.shuffle()
	var out: Array[String] = []
	out.append(pool[0])
	return out
