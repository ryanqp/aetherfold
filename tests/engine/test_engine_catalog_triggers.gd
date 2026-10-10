@tool
extends McpTestSuite

## Trigger events added for catalog coverage: becomes tapped / untapped, deals damage, turned face up, put into a graveyard
## from anywhere, "attacks or blocks" on one ability, and casting headers with colours.

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_catalog_triggers"


func _row(card_name: String, cost: String, cmc: int, type_line: String, text: String, p: String = "", t: String = "", colors: Array = []) -> Dictionary:
	return {name = card_name, oracle_id = card_name.to_lower(), mana_cost = cost, cmc = cmc, type_line = type_line,
		oracle_text = text, color_identity = colors, colors = colors, keywords = [], power = p, toughness = t, commander_legal = true}


func suite_setup(_ctx: Dictionary) -> void:
	var m := Fixtures.memory_catalog() as CatalogSource.Memory
	m.add(_row("Test Bear", "{1}{G}", 2, "Creature — Bear", "", "2", "2"))
	m.add(_row("Test Tapper", "{2}", 2, "Creature — Golem", "Whenever this creature becomes tapped, you gain 1 life.", "1", "1"))
	m.add(_row("Test Link", "{W}", 1, "Creature — Spirit", "Whenever this creature deals damage, you gain that much life.", "3", "3"))
	m.add(_row("Test Cobra", "{2}{G}", 3, "Creature — Snake", "Whenever this creature deals damage to a player, that player gets a poison counter.", "2", "2"))
	m.add(_row("Test Talisman", "{2}", 2, "Artifact", "Whenever a player casts a blue spell, you gain 1 life."))
	m.add(_row("Test Blue", "{U}", 1, "Instant", "Draw a card.", "", "", ["U"]))
	m.add(_row("Test Red", "{R}", 1, "Instant", "Test Red deals 1 damage to any target.", "", "", ["R"]))
	m.add(_row("Test Giant", "{3}{B}", 4, "Creature — Giant", "Whenever this creature attacks or blocks, you gain 2 life.", "4", "4"))
	m.add(_row("Test Wurm", "{8}", 8, "Creature — Wurm", "When this creature is put into a graveyard from anywhere, you gain 5 life.", "8", "8"))
	m.add(_row("Test Siege", "{2}{R}", 3, "Enchantment — Siege", "When this Siege enters, you gain 3 life."))
	db = CardDatabase.new()
	db.setup(m)


func _unread(n: String) -> Array:
	return db.unread_lines(db.definition_for(n))


func test_the_new_headers_are_read() -> void:
	for n in ["Test Tapper", "Test Link", "Test Cobra", "Test Talisman", "Test Giant", "Test Wurm", "Test Siege"]:
		assert_eq(_unread(n).size(), 0, "%s: %s" % [n, str(_unread(n))])


func _stack(engine: RulesEngine) -> MagicStack:
	return engine.state.stack as MagicStack


func test_becoming_tapped_triggers() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var t := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Tapper")
	engine.process_zone_events()
	t.tapped = true
	engine.process_zone_events()
	assert_eq(_stack(engine).size(), 1, "tapping it set the trigger off")
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, 41)
	engine.process_zone_events()
	assert_eq(_stack(engine).size(), 0, "no new trigger while it stays tapped")


func test_dealing_damage_triggers_with_the_amount() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var link := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Link")
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	engine.damage_object(link, bear, 3)
	engine.process_zone_events()
	assert_eq(_stack(engine).size(), 1)
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, 43, "gained as much as it dealt")


func test_damage_to_a_player_only_counts_players() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var cobra := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Cobra")
	var bear := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Test Bear")
	engine.damage_object(cobra, bear, 1)
	engine.process_zone_events()
	assert_eq(_stack(engine).size(), 0, "a creature isn't a player")


func test_a_cast_trigger_can_watch_for_a_colour() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Talisman")
	var red := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.STACK, "Test Red")
	engine.triggers.on_spell_cast(engine, red, 1)
	assert_eq(_stack(engine).size(), 0, "a red spell doesn't count")
	var blue := Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.STACK, "Test Blue")
	engine.triggers.on_spell_cast(engine, blue, 1)
	assert_eq(_stack(engine).size(), 1, "a blue spell does, whoever casts it")


func test_one_ability_listens_to_attacks_and_blocks() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var giant := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Test Giant")
	engine.triggers._fire(engine, "BLOCKS", giant, giant, {})
	assert_eq(_stack(engine).size(), 1, "blocking sets it off")
	engine.resolve_top()
	engine.triggers._fire(engine, "ATTACKS", giant, giant, {})
	assert_eq(_stack(engine).size(), 1, "so does attacking")


func test_put_into_a_graveyard_from_anywhere() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var wurm := Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Test Wurm")
	engine.discard_card(0, wurm.object_id)
	engine.process_zone_events()
	assert_eq(_stack(engine).size(), 1, "discarded into the graveyard: it triggers")
	engine.resolve_top()
	assert_eq(engine.state.players[0].life, 45)
