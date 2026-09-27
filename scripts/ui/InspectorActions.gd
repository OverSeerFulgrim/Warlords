class_name InspectorActions
extends Node

## The action buttons the inspection panel shows for the Keep, the Barracks,
## the Necromancer and the rally point.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). These are the *only* things
## about a clickable that don't come from its own get_inspect_data(): buttons,
## whose handlers live outside the inspectable. See InspectionPanel's header for
## why the split is drawn here.
##
## **This module builds buttons; it does not own modes or the inspect path.**
## Anything a button press implies beyond "poke UndeadCommand and refresh the
## panel" goes out as a signal, because Main.gd is the only thing that can see
## all of it:
##
## - Rally placement is one of four arbitrated input modes (placement >
##   demolish > rally > inspect) and entering it cancels the other two, so the
##   Command Undead / Move buttons request it rather than perform it.
## - Recruiting, funding a house and surrendering all write to the history log
##   or reload the scene, which are Main.gd's.
## - Follow toggling has to refresh the HUD strip too; routing it through
##   Main.gd keeps this module from reaching into another one.

## Raise Dead, paid in bones, at his feet (ruling C, 2026-09-26). Same handler
## the Economy tab's button and the R key use. The name is historical.
signal recruit_worker_pressed
## The Keep's Surrender button -- asks for confirmation (the pause menu's
## confirm), then ends the run (RunLifecycle.abandon) and brings up the run-end
## screen.
signal surrender_requested
## Command Undead / Move the rally point: asks Main.gd to enter rally placement
## mode, which first has to cancel any build or demolish mode in force.
signal rally_placement_requested
## Fund a house for this follower. Main.gd pays, logs and refreshes.
signal fund_house_requested(follower)
## The Necromancer's Follow button. Main.gd toggles, then refreshes both the
## HUD's follow readout and the panel.
signal follow_toggle_requested
## Close the panel *and* reset the bottom info strip, which is Main.gd's
## _close_inspector() -- inspector.close() alone would leave the strip stale.
signal close_requested
## A lootable site's action was pressed. **Requested, not performed**, for the
## same reason rally placement is: resolving one can open the choice sheet,
## which is `EventPanelUI`'s, and only Main.gd can see both.
signal site_action_requested(site, action_id)
## Open this site's choice sheet (the four-way grave model, LOOT_SITES_SPEC 4).
signal site_sheet_requested(site)
## Put part of the haul down. Requested rather than performed for the usual
## reason: where it lands depends on what he is standing at, and `SortieSystem`
## is the only thing that knows.
signal drop_requested(kind: String, amount: int)
signal drop_relic_requested(relic_id: String)
## Cast Command Undead in Escort mode, or re-anchor it to the ground. Requested
## rather than performed: only Main.gd knows where "the ground" is.
signal escort_toggle_requested
## Whole-escort policy (ESCORT_SPEC amendment 2026-08-29). Not a unit order.
signal escort_stance_requested(stance: int)
## Hidden <-> Hunting (LIVING_WORLD ruling 15).
signal villain_stance_toggle_requested
## Flee the region, from the lair (ROGUELITE_REWORK 17.7).
signal flee_requested
## A button on the guild's board: "take", "deliver" or "collect" bounty `id`.
signal guild_action_requested(guild, action: String, id: int)
## The Items window (2026-09-26).
signal items_requested
## **Downed and prisoners** (L3): "bind", "finish", "bind_all", "finish_all" on
## a `Downed`; "search", "ghoul" on a `Prisoner`. Requested, not performed: Main
## acts, logs and refreshes.
signal captive_action_requested(action: String, target)
## Asked each time his panel is built: can he flee from where he stands?
var flee_available: Callable = Callable()

# ---------------- References handed in by Main.gd ----------------
var _undead_command: UndeadCommand
var _inspector: InspectionPanel
var _villain_controller: VillainController
## The villain the buttons act for. A **reference handed in**, never looked up
## -- sites answer to whoever walked up (LOOT_SITES_SPEC section 3), and a
## second villain's panel would simply be handed a different one.
var _villain: Necromancer
## The return leg, for the Drop rows and the party-carry line.
var _sortie_system: SortieSystem
var _world_sites: WorldSites
## "Level 3 — 120 / 200 XP" for the top of his panel. A Callable handed in by
## Main, because the profile is the run's and this module only builds buttons.
var progress_line_provider: Callable = Callable()

func setup(undead_command: UndeadCommand, inspector: InspectionPanel,
		villain_controller: VillainController, villain: Necromancer = null,
		sortie_system: SortieSystem = null, world_sites: WorldSites = null) -> void:
	_undead_command = undead_command
	_inspector = inspector
	_villain_controller = villain_controller
	_villain = villain
	_sortie_system = sortie_system
	_world_sites = world_sites

## A lootable site's action block. Bound to the site rather than reading one off
## a member, so two sites can never disagree about which one the panel is
## showing -- `Callable.bind()` appends, hence the argument order.
##
## The reach rule lives here in its honest form: a site out of reach still
## inspects (description, details, the danger row), it just offers nothing. That
## is section 3's "no remote looting" as a *visible* rule rather than a silent
## one -- the player can read the crypt from a distance and see exactly why the
## buttons are not there.
func site_actions(box: VBoxContainer, site: WorldSite) -> void:
	if site == null or not site.lootable:
		return
	if not site.in_reach(_villain):
		_note(box, "Too far. He has to stand at it.")
		return
	if site.is_channelling():
		_note(box, "Working — moving stops it, and refunds nothing.")
		return
	if site.is_guarded():
		_note(box, "Whatever is here is not finished with you yet.")
		return

	var actions: Array = site.actions_for(_villain)
	if actions.is_empty():
		_note(box, "Nothing left here. Spent for the run.")
		return
	for action in actions:
		var id: String = String(action["id"])
		var b := Button.new()
		b.text = String(action["label"])
		b.tooltip_text = String(action.get("blurb", ""))
		b.disabled = not bool(action.get("enabled", true))
		if id == "open_sheet":
			b.pressed.connect(func(): site_sheet_requested.emit(site))
		else:
			b.pressed.connect(func(): site_action_requested.emit(site, id))
		box.add_child(b)
		# **A greyed button must say why it is greyed** (GAME_IMPROVEMENT_REVIEW
		# §9: "clearer explanation of why an action is unavailable"). A tooltip
		# is not enough -- nobody hovers a control that looks dead -- so the
		# reason goes on the panel, under the row it belongs to.
		var reason: String = String(action.get("reason", ""))
		if b.disabled and reason != "":
			_note(box, reason)

## The stance toggle: **a policy on the spell, never an order to a unit.** Two
## buttons, whole-escort, no per-skeleton anything — which is what keeps it on
## the right side of the pillar even though it changes what the dead do.
##
## The current stance is on the panel and on the rally marker's own payload
## (§7's legibility rule), and toggling writes a log line, because "why did they
## start that fight" must always be answerable.
func _stance_rows(box: VBoxContainer) -> void:
	var current: int = _undead_command.rally_point.stance
	_note(box, "Stance: %s — %s" % [RallyPoint.stance_name(current),
		RallyPoint.STANCE_BLURB.get(current, "")])
	for stance in [RallyPoint.Stance.DEFENSIVE, RallyPoint.Stance.AGGRESSIVE]:
		var s: int = stance    # explicit re-bind for the closure
		var b := Button.new()
		b.text = RallyPoint.stance_name(s)
		b.tooltip_text = String(RallyPoint.STANCE_BLURB.get(s, ""))
		b.disabled = s == current
		b.pressed.connect(func(): escort_stance_requested.emit(s))
		box.add_child(b)

## **Full hands are a state you can be in, not a wall you hit** (SORTIE_SPEC §1).
## Arriving at a crypt with no room has to produce a choice, so every carried
## kind and every carried relic gets a row that puts it down.
##
## The panel says where it will land *before* the click, because the two
## outcomes are genuinely different: at a site the load goes back into that
## site's remainder; anywhere else it becomes a cache standing in open country,
## which is a walk back and, from R3, a scavenger's opportunity.
func _drop_rows(box: VBoxContainer) -> void:
	if _sortie_system == null or _villain == null:
		return
	# **Items, not loads** (designer ruling 2026-09-26): resources take no
	# space, so there is nothing to drop but items -- and wearing, dropping and
	# swapping all happen in the Items window.
	box.add_child(HSeparator.new())
	_note(box, "Bag: %d / %d item slots.  Resources: %s." % [_villain.carried_total(), _villain.carry_capacity(),
		LootCatalog.describe(_villain.carried) if not _villain.carried.is_empty() else "none"])
	var b := Button.new()
	b.text = "Items — wear, drop, swap  [%s]" % Controls.label_for("items")
	b.pressed.connect(func(): items_requested.emit())
	box.add_child(b)

func _note(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
	label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(label)

## Which action-button builder (if any) a building contributes. The Keep and
## the Barracks are the only two with menus; everything else is pure
## information, which is why this is a two-line check rather than a registry.
func actions_for_building(building: Building) -> Callable:
	if building.is_main_building:
		return keep_actions
	if building.building_id == "dark_altar":
		return altar_actions
	if building.building_id == "cell":
		return cell_actions
	if building.category == "housing_intake":
		return barracks_actions
	return Callable()

## **The Dark Altar** (ROGUELITE_REWORK 17.5): Summon Ghoul, level 2, for a
## living sacrifice (LIVING_WORLD L3, 2026-09-27). One button per prisoner he
## could put on it; with none, a disabled button and the reason.
var captives: Captives = null

func altar_actions(box: VBoxContainer) -> void:
	var why: String = captives.ghoul_blocker(_villain) if captives else "It needs a living sacrifice."
	var list: Array = captives.sacrificeable(_villain) if captives and why == "" else []
	if list.is_empty():
		var b := Button.new()
		b.text = "Summon Ghoul"
		b.disabled = true
		box.add_child(b)
		_note(box, why if why != "" else "It needs a living sacrifice — a prisoner.")
		return
	_note(box, "A living man goes onto the stone; a Ghoul gets up. Stronger than bone, and it answers to Command Undead like any of the dead.")
	for p in list:
		var who: Prisoner = p
		var b := Button.new()
		b.text = "Summon Ghoul — sacrifice %s" % who.display_name
		b.pressed.connect(func(): captive_action_requested.emit("ghoul", who))
		box.add_child(b)

## **The Cell** (LIVING_WORLD 10.4): who is in it, fed or not, and what can be
## done with each -- searched here, sacrificed at the Altar.
func cell_actions(box: VBoxContainer) -> void:
	if captives == null:
		return
	var held: Array = captives.held()
	_note(box, "Holding %d of %d. Each eats 1 food at dawn and at dusk; two missed meals and he dies in here." % [held.size(), captives.cell_capacity()])
	if held.is_empty():
		_note(box, "Empty. Put a man down out there, bind him, and walk him home.")
		return
	var home: bool = captives.is_home(_villain)
	for p in held:
		var who: Prisoner = p
		var row := Label.new()
		row.text = "%s — %s" % [who.display_name, who.status_line()]
		row.add_theme_font_size_override("font_size", 12)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
		box.add_child(row)
		_prisoner_buttons(box, who, home)
	if not home:
		_note(box, "He has to be home to deal with them.")

func _prisoner_buttons(box: VBoxContainer, who: Prisoner, reachable: bool) -> void:
	var s := Button.new()
	s.text = "Search him" if not who.searched else "Searched"
	s.tooltip_text = "Once. Whatever he carries goes in your pack — and the first one you search knows how a Cell is built."
	s.disabled = who.searched or not reachable
	s.pressed.connect(func(): captive_action_requested.emit("search", who))
	box.add_child(s)
	if captives and captives.ghoul_blocker(_villain) == "" and captives.sacrificeable(_villain).has(who):
		var g := Button.new()
		g.text = "Summon Ghoul — sacrifice him"
		g.pressed.connect(func(): captive_action_requested.emit("ghoul", who))
		box.add_child(g)

## **A prisoner** clicked on the map (on the rope, or at the Cell).
func prisoner_actions(box: VBoxContainer, p: Prisoner) -> void:
	if captives == null or p == null:
		return
	var reach: bool = captives.can_reach_prisoner(p, _villain)
	_prisoner_buttons(box, p, reach)
	if not reach:
		_note(box, "He has to be home to deal with the ones in the Cell.")
	var why: String = captives.ghoul_blocker(_villain)
	if why != "":
		_note(box, "Summon Ghoul: " + why)

## **A man down** (LIVING_WORLD 11.2): bind or finish, standing over him; the
## batch orders (11.3) when more than one lies near.
func downed_actions(box: VBoxContainer, d: Downed) -> void:
	if captives == null or d == null:
		return
	if not captives.downed.has(d):
		_note(box, "It is over, one way or the other.")
		return
	if not captives.in_reach(d, _villain):
		_note(box, "Stand over him to bind him or finish him.")
	else:
		var b := Button.new()
		b.text = "Bind him — a prisoner  [%s]" % Controls.label_for("bind")
		b.tooltip_text = "He walks behind you on a rope. At home he goes into a Cell. He eats; he can be searched; he can go on the Altar."
		b.pressed.connect(func(): captive_action_requested.emit("bind", d))
		box.add_child(b)
		var f := Button.new()
		f.text = "Finish him — a body  [%s]" % Controls.label_for("finish")
		f.tooltip_text = "A corpse where he lies. Raise it for free."
		f.pressed.connect(func(): captive_action_requested.emit("finish", d))
		box.add_child(f)
	var near: int = captives.downed_near(_villain).size()
	if near > 1:
		var ba := Button.new()
		ba.text = "Bind all %d near him" % near
		ba.pressed.connect(func(): captive_action_requested.emit("bind_all", d))
		box.add_child(ba)
		var fa := Button.new()
		fa.text = "Finish all %d near him" % near
		fa.pressed.connect(func(): captive_action_requested.emit("finish_all", d))
		box.add_child(fa)

## **The guild's board** (LIVING_WORLD section 4.2). Standing first, because it
## decides everything under it; then every bounty with the one thing he can do
## about it from here.
func guild_actions(box: VBoxContainer, guild) -> void:
	if guild == null or _villain == null:
		return
	var tier: int = _villain.standing_with(Guild.FACTION)
	var standing := Label.new()
	standing.text = "Standing: %s" % Necromancer.standing_name(tier)
	standing.add_theme_font_size_override("font_size", 13)
	standing.add_theme_color_override("font_color", [Color(0.75, 0.9, 0.75), Color(1.0, 0.8, 0.45), Color(1.0, 0.45, 0.4)][tier])
	box.add_child(standing)
	if tier == Necromancer.Standing.KNOWN:
		_note(box, "The doors are shut to him. The guild knows what he is.")
		return
	if tier == Necromancer.Standing.SUSPECTED:
		_note(box, "Strange sightings are pinned to the board. The clerk counts the coin twice and pays half.")
	if not guild.in_reach(_villain):
		_note(box, "Walk up to the door to use the board.")
	var shown: Array = guild.visible_bounties()
	if shown.is_empty():
		_note(box, "The board is bare. Nothing in the region is wrong enough to pay for.")
	for b in shown:
		var row := Label.new()
		row.text = "%s  —  %d gold" % [String(b["title"]), int(b["gold"])]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
		row.add_theme_font_size_override("font_size", 12)
		row.tooltip_text = String(b.get("blurb", ""))
		box.add_child(row)
		var state: String = String(b["state"])
		var mine: bool = b.get("taker") == _villain
		var btn := Button.new()
		var id: int = int(b["id"])
		if state == "open":
			btn.text = "Take the job"
			btn.disabled = not guild.in_reach(_villain)
			btn.pressed.connect(func(): guild_action_requested.emit(guild, "take", id))
		elif state == "taken" and mine and String(b["kind"]) == "deliver":
			btn.text = "Hand over %d %s  (you have %d)" % [int(b["amount"]), String(b["res"]), GameState.player_settlement.amount(String(b["res"]))]
			btn.disabled = not guild.in_reach(_villain) or not GameState.can_afford(String(b["res"]), int(b["amount"]))
			btn.pressed.connect(func(): guild_action_requested.emit(guild, "deliver", id))
		elif state == "taken" and mine:
			btn.text = "In hand — go and do it"
			btn.disabled = true
		elif state == "done" and mine:
			var owed: int = int(b.get("owed", 0))
			btn.text = "Collect your pay" if owed <= 0 else "Collect the %d gold still owed" % owed
			btn.disabled = not guild.in_reach(_villain)
			btn.pressed.connect(func(): guild_action_requested.emit(guild, "collect", id))
		else:
			btn.text = "Taken by someone else"
			btn.disabled = true
		box.add_child(btn)

## The old Keep menu, now the Throne's action block.
func keep_actions(box: VBoxContainer) -> void:
	# No recruit button here any more: the dead are raised by *him*, where he
	# stands (his panel, the Economy tab, or R) -- ruling C, 2026-09-26.
	# Not a real feature yet -- a visible placeholder so clicking the Keep
	# already shows where building upgrades will eventually live, per the
	# "possibly get upgrades down the road" design note, rather than that
	# needing a whole new menu discovered from scratch later.
	var upgrades_label := Label.new()
	upgrades_label.text = "Upgrades -- coming soon"
	upgrades_label.modulate = Color(1, 1, 1, 0.5)
	box.add_child(upgrades_label)

	box.add_child(HSeparator.new())
	var surrender := Button.new()
	surrender.text = "Surrender"
	surrender.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	surrender.tooltip_text = "Abandon this run. XP earned so far is kept; the run-end screen lets you start again."
	surrender.pressed.connect(func(): surrender_requested.emit())
	box.add_child(surrender)

## His spellbook. Command Undead is the first real entry -- everything else is
## still the "visible promise" treatment (a real disabled Button, so the shape
## of the future feature is legible).
func necromancer_actions(box: VBoxContainer) -> void:
	if progress_line_provider.is_valid():
		var line := Label.new()
		line.text = String(progress_line_provider.call())
		line.add_theme_font_size_override("font_size", 11)
		line.modulate = Color(0.85, 0.78, 1.0)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
		box.add_child(line)

	# **Raise Dead -- his first spell** (ruling C, 2026-09-26). A corpse in a
	# grave is raised for free from the grave's own sheet; this is the version
	# that needs no corpse and costs bones instead, cast wherever he stands.
	var raise := Button.new()
	raise.text = "Raise Dead (%d Bones)  [R]" % int(WorkerSystem.RECRUIT_COST.get("bones", 0))
	raise.tooltip_text = "A skeleton claws its way out of the ground at his feet. Graves give you one free -- open a grave and choose Raise the corpse."
	raise.disabled = not GameState.can_afford_cost(WorkerSystem.RECRUIT_COST)
	raise.pressed.connect(func(): recruit_worker_pressed.emit())
	box.add_child(raise)

	# **Hidden / Hunting** (LIVING_WORLD ruling 15) -- a stance, not an attack
	# button. Hunting makes walking up to the living the attack.
	if _villain:
		var stance := Button.new()
		stance.text = ("Stance: Hunting — go Hidden  [%s]" if _villain.is_hunting()
			else "Stance: Hidden — start Hunting  [%s]") % Controls.label_for("stance")
		stance.tooltip_text = "Hunting: anything living he walks up to is fair game, and the escort goes Aggressive. Anyone who sees it is a witness." \
			if not _villain.is_hunting() else "Hidden: he never starts a fight with the living. Only hostiles open a fight."
		stance.pressed.connect(func(): villain_stance_toggle_requested.emit())
		box.add_child(stance)

	var cast := Button.new()
	cast.text = "Command Undead" if not _undead_command.is_active() else "Command Undead — move rally point"
	cast.tooltip_text = "Plant a rally point. Every skeleton marches to it and stops gathering."
	cast.pressed.connect(func(): rally_placement_requested.emit())
	box.add_child(cast)

	# **Escort: the same spell, anchored to him.** No targeting mode and no
	# placement branch in Main's input arbitration, because the target is the man
	# casting it -- which is the whole reason this is one button rather than a
	# second mode.
	var escort := Button.new()
	var escorting: bool = _undead_command.is_active() and _undead_command.rally_point.is_escorting()
	escort.text = "Command Undead — dismiss the escort" if escorting \
		else "Command Undead: Escort"
	escort.tooltip_text = "The dead walk with you. They keep station, take what comes near you, and close ranks if you fall low." \
		if not escorting else "Plant the point where you stand and let them hold it instead."
	escort.pressed.connect(func(): escort_toggle_requested.emit())
	box.add_child(escort)

	if escorting:
		_stance_rows(box)

	if _undead_command.is_active():
		var dismiss := Button.new()
		dismiss.text = "Dismiss the rally point"
		dismiss.tooltip_text = "Release the dead back to the gathering priorities."
		dismiss.pressed.connect(func():
			_undead_command.dismiss()
			_inspector.refresh()
		)
		box.add_child(dismiss)

	_drop_rows(box)

	# **His rope** (L3): each prisoner he is walking home.
	if captives and not _villain.prisoners.is_empty():
		box.add_child(HSeparator.new())
		_note(box, "On the rope: %d. Walk them home — %s." % [_villain.prisoners.size(),
			"a Cell holds them there" if captives.cell_capacity() > 0 else "he has no Cell to put them in yet"])
		for p in _villain.prisoners:
			var who: Prisoner = p
			var row := Label.new()
			row.text = "%s — %s" % [who.display_name, who.status_line()]
			row.add_theme_font_size_override("font_size", 12)
			box.add_child(row)
			_prisoner_buttons(box, who, true)

	if flee_available.is_valid() and bool(flee_available.call()):
		var flee := Button.new()
		flee.text = "Flee the region — end the run alive"
		flee.tooltip_text = "He is at the lair. Leave the region alive and keep 3 things he found this run."
		flee.pressed.connect(func(): flee_requested.emit())
		box.add_child(flee)

	box.add_child(HSeparator.new())
	# The camera escape hatch, given a button as well as a key. The key (F) is
	# the fast path; this is the discoverable one, and it's how you find out the
	# key exists.
	var follow := Button.new()
	follow.text = "Stop following (F)" if _villain_controller.following else "Follow him (F)"
	follow.tooltip_text = "Keep the camera centred on the Necromancer. Any right-drag or arrow-key pan drops out of it."
	follow.pressed.connect(func(): follow_toggle_requested.emit())
	box.add_child(follow)

## Order buttons for the rally point itself. Lives here rather than on
## RallyPoint for the usual reason -- these call into UndeadCommand, and the
## inspectable object is deliberately data-only. See InspectionPanel's header.
func rally_actions(box: VBoxContainer) -> void:
	var current: int = _undead_command.rally_point.order if _undead_command.is_active() else -1
	# Escort is deliberately NOT here: it is cast on him, from his own panel, and
	# a point already anchored to a man has no ground to be re-ordered on.
	for order in [RallyPoint.Order.DEFEND, RallyPoint.Order.PATROL, RallyPoint.Order.ATTACK]:
		var o: int = order  # explicit re-bind for the closure
		var b := Button.new()
		b.text = RallyPoint.order_name(o)
		b.tooltip_text = RallyPoint.ORDER_BLURB.get(o, "")
		b.disabled = o == current
		b.pressed.connect(func():
			_undead_command.set_order(o)
			_inspector.refresh()
		)
		box.add_child(b)

	box.add_child(HSeparator.new())
	var move := Button.new()
	move.text = "Move the rally point"
	move.pressed.connect(func(): rally_placement_requested.emit())
	box.add_child(move)

	var dismiss := Button.new()
	dismiss.text = "Dismiss — back to work"
	dismiss.add_theme_color_override("font_color", Color(0.95, 0.75, 0.5))
	dismiss.pressed.connect(func():
		_undead_command.dismiss()
		close_requested.emit()
	)
	box.add_child(dismiss)

## The old Barracks panel, now the Barracks' action block. Lists who is living
## there with the labor skills that decide what they're actually good for --
## the player needs those side by side to answer "is this dwarf worth a house?".
## The occupancy count itself is a details row now (Building.get_inspect_data),
## not repeated here.
func barracks_actions(box: VBoxContainer) -> void:
	if GameState.followers.is_empty():
		var empty := Label.new()
		empty.text = "No residents yet. Recruits will arrive."
		empty.add_theme_font_size_override("font_size", 11)
		empty.modulate = Color(1, 1, 1, 0.6)
		box.add_child(empty)

	# Two sections: people still occupying a slot, and people who've moved out.
	# The settled list stays visible because morale keeps mattering after
	# they're housed -- a housed recruit still eats and can still desert.
	_add_roster_section(box, "In the Barracks", false, true)
	_add_roster_section(box, "Settled in town", true, false)

	# FOUNDATION_SPEC section 9: "Upgrade button: present, hard-locked --
	# greyed 'Locked' state, no tooltip cost. Unlock is a roadmap milestone,
	# not a hidden requirement." So this is a real, visible, disabled Button
	# with no handler attached -- not a Label dressed up as one, because the
	# promise being made is specifically "there will be a button here".
	box.add_child(HSeparator.new())
	var upgrade := Button.new()
	upgrade.text = "Upgrade — Locked"
	upgrade.disabled = true
	box.add_child(upgrade)

## One roster block. `housed` selects which half of the roster to list;
## `with_fund_button` adds the fund-a-house action, which only makes sense for
## people who haven't got one yet.
func _add_roster_section(box: VBoxContainer, heading: String, housed: bool, with_fund_button: bool) -> void:
	var members: Array = GameState.followers.filter(func(f): return f.is_housed == housed)
	if members.is_empty():
		return
	var head := Label.new()
	head.text = heading
	head.add_theme_font_size_override("font_size", 11)
	head.modulate = Color(1, 1, 1, 0.55)
	box.add_child(head)

	for f in members:
		# Stacked rather than one wide row: the inspection panel is ~330px, and
		# the old single-line layout assumed a panel that sized itself to
		# whatever it held. The full stat block survives -- it just wraps.
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 1)

		var info := Label.new()
		info.add_theme_font_size_override("font_size", 11)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(InspectionPanel.PANEL_WIDTH - 30.0, 0)
		# One roster line has room for the profile and the four physical
		# attributes, not for all nine plus twelve skills -- the panel is for
		# picking someone out of a list, and the inspection panel is where you
		# read them properly.
		info.text = "%s — %s (%s)  %s  Str%d Dex%d Spd%d End%d  morale %d/10  [%s]" % [
			f.label(), f.species, f.category,
			f.combat_profile()["profile"],
			f.strength, f.dexterity, f.speed, f.endurance,
			f.morale, f.status_label(),
		]
		# Morale colour beats the exceptional gold when someone is in trouble --
		# a starving star recruit is news, and the star is still in their name.
		if f.morale <= MoraleSystem.DEPARTURE_MORALE:
			info.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		elif f.morale <= MoraleSystem.MISCHIEF_MORALE:
			info.add_theme_color_override("font_color", Color(0.95, 0.70, 0.40))
		elif f.is_exceptional:
			info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		entry.add_child(info)

		if with_fund_button:
			var target: Follower = f  # explicit re-bind for the closure
			var fund := Button.new()
			var cost := SettlementGrid.HOUSE_COST
			fund.text = "Fund house (%d wood, %d stone)" % [cost["wood"], cost["stone"]]
			fund.tooltip_text = "They pick the spot themselves, by race. Frees a Barracks slot."
			fund.disabled = not GameState.can_afford_cost(cost)
			fund.pressed.connect(func(): fund_house_requested.emit(target))
			entry.add_child(fund)

		box.add_child(entry)
