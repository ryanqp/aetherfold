@tool
extends McpTestSuite

## Cards that did nothing in a real game, with their real Oracle text: Fate Unraveler (opponent draws), Theater of
## Horrors (exile at upkeep, play from among them, ping) and Grab the Prize (discard as a cost, conditional damage).

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_card_reports"


func _row(name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "") -> Dictionary:
	return {name = name, oracle_id = name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = [], colors = [], keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Fate Unraveler", "{3}{B}", 4, "Enchantment Creature — Hag", "Whenever an opponent draws a card, Fate Unraveler deals 1 damage to that player.", "3", "4"))
	m.add(_row("Theater of Horrors", "{1}{B}{R}", 3, "Enchantment", "At the beginning of your upkeep, exile the top card of your library.\nDuring your turn, if an opponent lost life this turn, you may play lands and cast spells from among cards exiled with Theater of Horrors.\n{3}{R}: Theater of Horrors deals 1 damage to target opponent or planeswalker."))
	m.add(_row("Grab the Prize", "{1}{R}", 2, "Sorcery", "As an additional cost to cast this spell, discard a card.\nDraw two cards. If the discarded card wasn't a land card, Grab the Prize deals 2 damage to each opponent."))
	m.add(_row("Test Filler", "{1}", 1, "Creature — Test", "", "1", "1"))
	db = CardDatabase.new()
	db.setup(m)


func test_fate_unraveler_pings_the_player_who_draws() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Fate Unraveler")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	var life := engine.state.players[1].life
	engine.draw_card(1)
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 1, "the trigger went on the stack")
	engine.resolve_top()
	assert_eq(engine.state.players[1].life, life - 1)


func test_fate_unraveler_ignores_its_own_controllers_draw() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Fate Unraveler")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.draw_card(0)
	engine.process_zone_events()
	assert_eq((engine.state.stack as MagicStack).size(), 0)


func test_theater_exiles_at_upkeep_and_the_card_is_linked() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var theater := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Theater of Horrors")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Test Filler")
	engine.state.active_player_id = 0
	engine.triggers.fire_player_event(engine, "BEGIN_STEP", 0)
	for ab in (theater.definition as CardDefinition).abilities:
		if (ab as Ability).kind == &"TRIGGERED":
			assert_eq(str((ab as Ability).effects[0].kind), "EXILE_TOP")


func test_theater_lets_you_play_exiled_cards_only_after_an_opponent_lost_life() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var theater := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Theater of Horrors")
	var card := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.EXILE, "Test Filler")
	card.marks["exiled_with"] = theater.object_id
	engine.state.active_player_id = 0
	assert_false(engine.can_play_from_exile(0, card), "no life lost yet")
	engine.state.players[1].life_lost_this_turn = 2
	assert_true(engine.can_play_from_exile(0, card), "an opponent lost life this turn")
	engine.state.active_player_id = 1
	assert_false(engine.can_play_from_exile(0, card), "only during your turn")


func test_grab_the_prize_reads_both_halves() -> void:
	var ab: Ability = null
	for a in db.definition_for("Grab the Prize").abilities:
		if (a as Ability).kind == &"SPELL":
			ab = a
	assert_true(ab != null, "the spell was read")
	assert_eq(ab.effects.size(), 2)
	assert_eq(str(ab.effects[0].kind), "DRAW")
	assert_true((ab.effects[1].params as Dictionary).has("if_cond"), "the damage is conditional on the discarded card")


func test_paid_card_condition() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var spell := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Grab the Prize")
	spell.marks["paid_types"] = ["Creature — Test"]
	assert_true(engine.layers.condition_met(engine.state, spell, {"paid_lacks": "Land"}))
	spell.marks["paid_types"] = ["Basic Land — Mountain"]
	assert_false(engine.layers.condition_met(engine.state, spell, {"paid_lacks": "Land"}))
	assert_true(engine.layers.condition_met(engine.state, spell, {"paid_has": "Land"}))
