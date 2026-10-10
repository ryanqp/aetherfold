@tool
extends McpTestSuite

## The Override menu's actions (TableOverrides): each one changes the table the way it says, and says what it did.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_overrides"


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add({name = "Test Bear", oracle_id = "bear", mana_cost = "{1}{G}", cmc = 2, type_line = "Creature — Bear", oracle_text = "", color_identity = [],
		colors = [], keywords = [], power = "2", toughness = "2", commander_legal = true})
	db = CardDatabase.new()
	db.setup(m)


func _apply(engine: RulesEngine, op: Dictionary, caller: int = 0) -> String:
	return TableOverrides.apply(engine, op, caller)


func test_mana_goes_to_the_chosen_player() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(_apply(engine, {op = "mana", who = "me", color = "R", n = 3}), "")
	assert_eq((engine.state.players[0].mana as ManaPool).r, 3)
	assert_eq(_apply(engine, {op = "mana", who = "rival", color = "C", n = 2}), "")
	assert_eq((engine.state.players[1].mana as ManaPool).colorless, 2)
	assert_ne(_apply(engine, {op = "mana", who = "me", color = "Z", n = 1}), "", "no such color")


func test_life_poison_and_commander_damage() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(_apply(engine, {op = "life", who = "me", delta = -5}), "")
	assert_eq(engine.state.players[0].life, 35)
	assert_eq(_apply(engine, {op = "life", who = "rival", delta = 10}), "")
	assert_eq(engine.state.players[1].life, 50)
	_apply(engine, {op = "poison", who = "rival", delta = 3})
	assert_eq(engine.state.players[1].poison, 3)
	_apply(engine, {op = "poison", who = "rival", delta = -9})
	assert_eq(engine.state.players[1].poison, 0, "never below zero")


func test_a_guest_asking_for_me_means_the_guest() -> void:
	var engine := Fixtures.empty_engine_1v1()
	_apply(engine, {op = "life", who = "me", delta = -7}, 1)
	assert_eq(engine.state.players[1].life, 33)
	assert_eq(engine.state.players[0].life, 40)
	_apply(engine, {op = "life", who = "rival", delta = -2}, 1)
	assert_eq(engine.state.players[0].life, 38)


func test_draw_discard_and_mill() -> void:
	var engine := Fixtures.empty_engine_1v1()
	for _i in 6:
		Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Bear")
	_apply(engine, {op = "draw", who = "me", n = 3})
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), 3)
	_apply(engine, {op = "discard", who = "me", n = 2})
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0) as Zone).size(), 1)
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0) as Zone).size(), 2)
	_apply(engine, {op = "mill", who = "me", n = 2})
	assert_eq((engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0) as Zone).size(), 4)


func _in_zone(engine: RulesEngine, zone_id: int, owner_id: int) -> GameObject:
	## A card that changes zones is a new object, so look in the zone for what is there now.
	var z: Zone = engine.state.zones.get_zone(zone_id, owner_id)
	if z == null or z.is_empty():
		return null
	return engine.state.objects.get(int(z.object_ids[0]))


func test_kill_exile_bounce_and_revive() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	assert_eq(_apply(engine, {op = "move", object_id = bear.object_id, to = "GRAVEYARD"}), "")
	var dead := _in_zone(engine, EngineEnums.ZoneId.GRAVEYARD, 1)
	assert_true(dead != null, "in the graveyard")
	assert_eq(_apply(engine, {op = "move", object_id = dead.object_id, to = "BATTLEFIELD"}), "")
	var back := _in_zone(engine, EngineEnums.ZoneId.BATTLEFIELD, -1)
	assert_true(back != null and back.controller_id == 1, "it comes back under its owner")
	_apply(engine, {op = "move", object_id = back.object_id, to = "EXILE"})
	var gone := _in_zone(engine, EngineEnums.ZoneId.EXILE, 1)
	assert_true(gone != null, "exiled")
	_apply(engine, {op = "move", object_id = gone.object_id, to = "HAND"})
	var held := _in_zone(engine, EngineEnums.ZoneId.HAND, 1)
	assert_true(held != null, "back in hand")
	assert_ne(_apply(engine, {op = "move", object_id = held.object_id, to = "HAND"}), "", "already there")


func test_size_counters_tap_and_control() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_apply(engine, {op = "pt", object_id = bear.object_id, delta = 5})
	assert_eq(engine.power_of(bear), 7)
	_apply(engine, {op = "pt", object_id = bear.object_id, delta = -1})
	assert_eq(engine.power_of(bear), 6)
	_apply(engine, {op = "counters", object_id = bear.object_id, name = "loyalty", delta = 3})
	assert_eq(int(bear.counters.get("loyalty", 0)), 3)
	_apply(engine, {op = "counters", object_id = bear.object_id, name = "loyalty", delta = -9})
	assert_false(bear.counters.has("loyalty"), "removed down to nothing")
	_apply(engine, {op = "tap", object_id = bear.object_id})
	assert_true(bear.tapped)
	_apply(engine, {op = "untap", object_id = bear.object_id})
	assert_false(bear.tapped)
	_apply(engine, {op = "control", object_id = bear.object_id}, 0)
	assert_eq(bear.controller_id, 0)


func test_a_very_small_creature_dies_to_a_big_shrink() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_apply(engine, {op = "pt", object_id = bear.object_id, delta = -5})
	assert_true(_in_zone(engine, EngineEnums.ZoneId.GRAVEYARD, 1) != null, "state-based actions run after an override")


func test_tokens_and_copies() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(_apply(engine, {op = "token", who = "me", preset = "zombie", label = "2/2 Zombie"}), "")
	assert_eq(_apply(engine, {op = "token", who = "me", preset = "treasure", label = "Treasure"}), "")
	assert_eq(_apply(engine, {op = "token", who = "rival", p = 7, t = 7, name = "Hydra", colors = ["G"], subtypes = ["Hydra"]}), "")
	var mine := 0
	var theirs := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o: GameObject = engine.state.objects[oid]
		if o.controller_id == 0:
			mine += 1
		else:
			theirs += 1
			assert_eq(engine.power_of(o), 7)
	assert_eq(mine, 2)
	assert_eq(theirs, 1)
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	_apply(engine, {op = "copy", object_id = bear.object_id}, 0)
	var copies := 0
	for oid in engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD).object_ids:
		var o2: GameObject = engine.state.objects[oid]
		if o2.is_token and o2.controller_id == 0 and (o2.definition as CardDefinition).name == "Test Bear":
			copies += 1
	assert_eq(copies, 1)


func test_untap_all_extra_turn_and_a_gone_card() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	bear.tapped = true
	_apply(engine, {op = "untap_all", who = "me"})
	assert_false(bear.tapped)
	_apply(engine, {op = "extra_turn", who = "me"})
	assert_eq(engine.state.extra_turns.size(), 1)
	assert_ne(_apply(engine, {op = "tap", object_id = 99999}), "", "a card that is gone")


func test_every_action_can_describe_itself() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	for op in [
			{op = "mana", who = "me", color = "G", n = 2}, {op = "life", who = "rival", delta = -5}, {op = "poison", who = "me", delta = 1},
			{op = "draw", who = "me", n = 2}, {op = "move", object_id = bear.object_id, to = "GRAVEYARD"},
			{op = "pt", object_id = bear.object_id, delta = 5}, {op = "counters", object_id = bear.object_id, name = "charge", delta = 1},
			{op = "token", who = "me", preset = "beast", label = "3/3 Beast"}, {op = "control", object_id = bear.object_id}]:
		var text := TableOverrides.describe(engine, op, 0)
		assert_true(text != "" and text != "an override", "%s: %s" % [str(op.op), text])
	assert_true(TableOverrides.describe(engine, {op = "life", who = "rival", delta = -5}, 0).contains("loses 5"))


# --- The panel itself ----------------------------------------------------------------------------------------

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for ch in node.get_children():
		var hit := _find_button(ch, text)
		if hit != null:
			return hit
	return null


func test_the_panel_builds_the_actions_you_press() -> void:
	var panel := OverridePanel.new()
	panel.setup("Talrand", false, true)
	var got: Array = []
	panel.act.connect(func(op: Dictionary) -> void: got.append(op))
	var armed: Array = []
	panel.arm.connect(func(op: Dictionary, hint: String) -> void: armed.append([op, hint]))
	var zones: Array = []
	panel.pick_card.connect(func(zone: String, to: String, _hint: String) -> void: zones.append([zone, to]))
	## Pick the action first; the number comes after.
	_find_button(panel, "Talrand").pressed.emit()
	_find_button(panel, "Lose life").pressed.emit()
	assert_eq(got.size(), 0, "nothing happens until a number is picked")
	_find_button(panel, "5").pressed.emit()
	assert_eq(got.size(), 1)
	assert_eq(str(got[0].who), "rival")
	assert_eq(int(got[0].delta), -5)
	_find_button(panel, "R").pressed.emit()
	_find_button(panel, "10").pressed.emit()
	assert_eq(str(got[1].color), "R")
	assert_eq(int(got[1].n), 10)
	_find_button(panel, "−1/−1 counters").pressed.emit()
	assert_eq(armed.size(), 0, "asks how many first")
	_find_button(panel, "5").pressed.emit()
	assert_eq(armed.size(), 1)
	assert_eq(int(armed[0][0].delta), -5)
	_find_button(panel, "Kill").pressed.emit()
	assert_eq(str(armed[1][0].to), "GRAVEYARD")
	_find_button(panel, "Revive").pressed.emit()
	assert_eq(zones[0], ["GRAVEYARD", "BATTLEFIELD"])
	_find_button(panel, "Treasure").pressed.emit()
	assert_eq(str(got[2].preset), "treasure")
	_find_button(panel, "Draw").pressed.emit()
	_find_button(panel, "Back").pressed.emit()
	assert_eq(got.size(), 3, "Back gives up on the number")
	panel.free()


func test_a_guest_cannot_tutor_from_a_library_it_cannot_see() -> void:
	var panel := OverridePanel.new()
	panel.setup("Talrand", true, false)
	assert_true(_find_button(panel, "Tutor").disabled)
	panel.free()
