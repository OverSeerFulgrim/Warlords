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

	var might := _roll(RaceCatalog.stat(race_id, "might"))
	var guile := _roll(RaceCatalog.stat(race_id, "guile"))
	var influence := _roll(RaceCatalog.stat(race_id, "influence"))
	var loyalty := _roll(RaceCatalog.stat(race_id, "loyalty"))
	var woodcutting := _roll(RaceCatalog.labor(race_id, "woodcutting"))
	var mining := _roll(RaceCatalog.labor(race_id, "mining"))
	var foraging := _roll(RaceCatalog.labor(race_id, "foraging"))

	var f := Follower.new(_pick_name(race_id), RaceCatalog.get_race(race_id).get("display_name", race_id),
		_pick_traits(), might, guile, influence, loyalty)
	f.race_id = race_id
	f.category = cat
	f.rarity = RaceCatalog.rarity(race_id)
	# Labor skills and walk speed live on Laborer. Walk speed is a racial
	# constant with no per-recruit variance (FOUNDATION_SPEC section 3).
	f.woodcutting = woodcutting
	f.mining = mining
	f.foraging = foraging
	f.walk_speed = RaceCatalog.walk_speed(race_id)

	_maybe_make_exceptional(f, cat)
	# Re-top-up after the exceptional roll: a Warrior's bonus is +1 Might, which
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

## 5% chance of +1 to the race's category-defining stat, applied after the
## roll. "best_labor" resolves per individual to whichever labor skill they
## actually rolled highest -- an Economy race's defining trait is being good at
## *its* speciality, and that differs by race (a Gray Dwarf mines, a Minotaur
## chops and mines about equally).
func _maybe_make_exceptional(f: Follower, cat: String) -> void:
	if randf() * 100.0 > RaceCatalog.exceptional_chance_percent():
		return
	var stat: String = RaceCatalog.defining_stat_for_category(cat)
	match stat:
		"might":
			f.might = mini(10, f.might + 1)
		"guile":
			f.guile = mini(10, f.guile + 1)
		"foraging":
			f.foraging = mini(10, f.foraging + 1)
		"best_labor":
			_bump_best_labor(f)
		_:
			return  # "none" -- Versatile/Labor have no defining stat, no star
	f.is_exceptional = true

func _bump_best_labor(f: Follower) -> void:
	if f.mining >= f.woodcutting and f.mining >= f.foraging:
		f.mining = mini(10, f.mining + 1)
	elif f.woodcutting >= f.foraging:
		f.woodcutting = mini(10, f.woodcutting + 1)
	else:
		f.foraging = mini(10, f.foraging + 1)

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
