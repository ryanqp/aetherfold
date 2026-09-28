@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")
const RivalAI := preload("res://scripts/rival_ai.gd")
const MatchStateScript := preload("res://scripts/match_state.gd")

var db: CardDatabase


func suite_name() -> String:
	return "engine_ai"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_skip_cast_reads_effects_not_names() -> void:
	var counter := db.definition_for("Counterspell")
	counter.name = "Not A Counter"
	assert_true(counter.has_effect(&"COUNTER_SPELL"))
	assert_true(GameSession.ai_should_skip_cast(counter, true, false))
	assert_false(GameSession.ai_should_skip_cast(counter, false, true))
	var cancel := db.definition_for("Cancel")
	assert_true(cancel.has_effect(&"COUNTER_SPELL"))
	var opt := db.definition_for("Opt")
	assert_true(opt.has_effect(&"DRAW"))
	assert_eq(int(opt.spell_effect_param(&"DRAW", "n", 0)), 1)
	assert_false(GameSession.ai_should_skip_cast(opt, true, false))
	var unsummon := db.definition_for("Unsummon")
	assert_true(unsummon.spell_requires_creature_target())
	assert_true(unsummon.spell_moves_target_to_hand())
	assert_true(GameSession.ai_should_skip_cast(unsummon, true, false))
	assert_false(GameSession.ai_should_skip_cast(unsummon, true, true))
	var shock := db.definition_for("Shock")
	assert_false(shock.spell_requires_creature_target())
	assert_false(GameSession.ai_should_skip_cast(shock, true, false))
	var boomerang := db.definition_for("Boomerang")
	assert_false(boomerang.spell_requires_creature_target())
	assert_true(boomerang.spell_moves_target_to_hand())


func test_ai_casts_opt_and_holds_counterspell() -> void:
	var session := _bot_ready()
	var engine := session.engine
	var island: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	island.summoned_this_turn = false
	var island2: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	island2.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Opt")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Counterspell")
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.LIBRARY, "Island")
	session.ai_take_turn(1)
	var hand := _names_in(engine, EngineEnums.ZoneId.HAND, 1)
	var gy := _names_in(engine, EngineEnums.ZoneId.GRAVEYARD, 1)
	assert_true(hand.has("Counterspell"), "counter stays in hand on an empty stack")
	assert_false(hand.has("Opt"))
	assert_true(gy.has("Opt"), "Opt resolved via its DRAW effect")


func test_ai_unsummon_bounces_a_creature() -> void:
	var session := _bot_ready()
	var engine := session.engine
	var island: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	island.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Unsummon")
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	session.ai_take_turn(1)
	var bf := _names_in(engine, EngineEnums.ZoneId.BATTLEFIELD, 0)
	var you_hand := _names_in(engine, EngineEnums.ZoneId.HAND, 0)
	assert_false(bf.has("Goblin Piker"))
	assert_true(you_hand.has("Goblin Piker"))
	assert_true(_names_in(engine, EngineEnums.ZoneId.GRAVEYARD, 1).has("Unsummon"))


func test_ai_holds_unsummon_with_no_creature() -> void:
	var session := _bot_ready()
	var engine := session.engine
	var island: GameObject = Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	island.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 1, EngineEnums.ZoneId.HAND, "Unsummon")
	session.ai_take_turn(1)
	assert_true(_names_in(engine, EngineEnums.ZoneId.HAND, 1).has("Unsummon"))
	assert_false(_names_in(engine, EngineEnums.ZoneId.GRAVEYARD, 1).has("Unsummon"))


func test_legacy_rival_reads_ir_effects() -> void:
	assert_true(RivalAI._is_counterspell({"name": "Counterspell"}))
	assert_true(RivalAI._is_counterspell({"name": "Cancel"}))
	assert_false(RivalAI._is_counterspell({"name": "Swan Song"}))
	assert_false(RivalAI._is_counterspell({"name": "Opt"}))
	var state = MatchStateScript.new()
	state.difficulty = 3
	state.rival["hand"] = []
	state.rival["library_cards"] = [
		{"name": "Island", "type": "Basic Land — Island"},
		{"name": "Island", "type": "Basic Land — Island"},
	]
	state.rival["library"] = 2
	state.you["creatures"] = [{"name": "Goblin Piker", "type": "Creature — Goblin", "power": "2"}]
	state.you["hand"] = []
	var log := PackedStringArray()
	RivalAI._on_spell(state, {"name": "Opt", "type": "Instant", "cmc": 1}, 3, log)
	assert_eq(state.rival["hand"].size(), 1)
	RivalAI._on_spell(state, {"name": "Unsummon", "type": "Instant", "cmc": 1}, 0, log)
	assert_eq(state.you["creatures"].size(), 1)
	RivalAI._on_spell(state, {"name": "Unsummon", "type": "Instant", "cmc": 1}, 2, log)
	assert_eq(state.you["creatures"].size(), 0)
	assert_eq(state.you["hand"].size(), 1)


func _bot_ready() -> GameSession:
	var session := GameSession.new()
	session.match_start = GameSession.MatchStart.MAIN_GAME
	session.engine = Fixtures.empty_engine_1v1()
	session.db = db
	session.you_seat = 0
	session.engine.state.active_player_id = 1
	session.engine.priority.give(session.engine.state, 1)
	return session


func _names_in(engine: RulesEngine, zone_id: int, player_id: int) -> Array:
	var zone: Zone = engine.state.zones.get_zone(zone_id, player_id)
	var names: Array = []
	if zone == null:
		return names
	for oid in zone.object_ids:
		var obj: GameObject = engine.state.objects.get(oid)
		if obj != null and obj.definition is CardDefinition:
			names.append((obj.definition as CardDefinition).name)
	return names
