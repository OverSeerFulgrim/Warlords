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

## The Keep's Recruit Worker button. Same handler the Economy tab's button uses.
signal recruit_worker_pressed
## The Keep's Surrender button -- closes the inspector and reloads the run.
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

# ---------------- References handed in by Main.gd ----------------
var _undead_command: UndeadCommand
var _inspector: InspectionPanel
var _villain_controller: VillainController
## The villain the buttons act for. A **reference handed in**, never looked up
## -- sites answer to whoever walked up (LOOT_SITES_SPEC section 3), and a
## second villain's panel would simply be handed a different one.
var _villain: Necromancer

func setup(undead_command: UndeadCommand, inspector: InspectionPanel,
		villain_controller: VillainController, villain: Necromancer = null) -> void:
	_undead_command = undead_command
	_inspector = inspector
	_villain_controller = villain_controller
	_villain = villain

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
	if building.category == "housing_intake":
		return barracks_actions
	return Callable()

## The old Keep menu, now the Throne's action block.
func keep_actions(box: VBoxContainer) -> void:
	var recruit := Button.new()
	recruit.text = "Recruit Worker (5 Bones)"
	recruit.pressed.connect(func(): recruit_worker_pressed.emit())
	box.add_child(recruit)

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
	surrender.tooltip_text = "Abandon this run and start over."
	surrender.pressed.connect(func(): surrender_requested.emit())
	box.add_child(surrender)

## His spellbook. Command Undead is the first real entry -- everything else is
## still the "visible promise" treatment (a real disabled Button, so the shape
## of the future feature is legible).
func necromancer_actions(box: VBoxContainer) -> void:
	var cast := Button.new()
	cast.text = "Command Undead" if not _undead_command.is_active() else "Command Undead — move rally point"
	cast.tooltip_text = "Plant a rally point. Every skeleton marches to it and stops gathering."
	cast.pressed.connect(func(): rally_placement_requested.emit())
	box.add_child(cast)

	if _undead_command.is_active():
		var dismiss := Button.new()
		dismiss.text = "Dismiss the rally point"
		dismiss.tooltip_text = "Release the dead back to the gathering priorities."
		dismiss.pressed.connect(func():
			_undead_command.dismiss()
			_inspector.refresh()
		)
		box.add_child(dismiss)

	var more := Button.new()
	more.text = "Further spells — coming soon"
	more.disabled = true
	box.add_child(more)

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
