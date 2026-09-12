@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

func suite_name() -> String:
	return "engine_state"


func test_1v1_seats_life_and_command_zone() -> void:
	var engine := Fixtures.empty_engine_1v1(1)
	assert_eq(engine.state.players.size(), 2, "1v1 has two seats")
	assert_eq(engine.state.players[0].life, 40)
	assert_eq(engine.state.players[1].life, 40)
	assert_true(engine.state.rules.commander_enabled)
	assert_true(engine.state.rules.first_player_skips_draw)
	assert_false(engine.state.rules.allow_demo_illegal_decks)
	assert_eq(engine.state.players[0].commander_ids.size(), 0, "empty CZ")
	assert_eq(engine.state.players[1].commander_ids.size(), 0, "empty CZ")
	assert_eq(engine.state.rng_seed, 1)
	assert_eq(engine.state.log.size(), 1)
	assert_eq(engine.state.log.last().type, EngineEnums.EventType.GAME_START)


func test_4p_seats_life_and_command_zone() -> void:
	var engine := Fixtures.empty_engine_4p(1)
	assert_eq(engine.state.players.size(), 4)
	assert_eq(engine.state.rules.starting_life, 40)
	assert_eq(engine.state.rules.player_count, 4)
	assert_false(engine.state.rules.first_player_skips_draw)
	for p in engine.state.players:
		assert_eq(p.life, 40)
		assert_eq(p.commander_ids.size(), 0)
		assert_false(p.lost)


func test_default_construction_is_4p_commander() -> void:
	var engine := RulesEngine.new()
	assert_eq(engine.state.rules.player_count, 4)
	assert_eq(engine.state.rules.starting_life, 40)
	assert_eq(engine.state.rules.commander_damage_to_lose, 21)
	assert_eq(engine.state.rules.commander_tax_step, 2)


func test_seeded_rng_is_deterministic() -> void:
	var a := Fixtures.empty_engine_1v1(1)
	var b := Fixtures.empty_engine_1v1(1)
	var seq_a: Array = [a.state.rng.randf(), a.state.rng.randf(), a.state.rng.randf()]
	var seq_b: Array = [b.state.rng.randf(), b.state.rng.randf(), b.state.rng.randf()]
	assert_eq(seq_a, seq_b)
	var c := Fixtures.empty_engine_1v1(99)
	var seq_c: Array = [c.state.rng.randf(), c.state.rng.randf(), c.state.rng.randf()]
	assert_ne(seq_a, seq_c)


func test_submit_does_not_block() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var action := GameAction.new()
	action.kind = GameAction.Kind.PASS_PRIORITY
	var result := engine.submit(action)
	assert_eq(result.get_class(), "RefCounted")
	assert_true(result.ok)
	assert_false(engine.is_over())
