@tool
extends McpTestSuite

## The generic condition language ("if you control three or more artifacts", "it's your turn", "a creature died this
## turn" ...): read from Oracle text by OracleIr._condition and checked by LayerManager.condition_met.

const Fixtures := preload("res://tests/engine/fixtures.gd")


func suite_name() -> String:
	return "engine_conditions"


func test_reader_understands_counts_and_zones() -> void:
	var r := OracleIr.new()
	var c := r._condition("you control three or more artifacts")
	assert_eq(int(c.get("min", 0)), 3)
	assert_eq(str((c["controls"] as Dictionary).get("type")), "artifact")
	assert_eq(int(r._condition("there are seven or more cards in your graveyard").get("min", 0)), 7)
	assert_eq(int(r._condition("you have no cards in hand").get("hand_max", -1)), 0)
	assert_true(r._condition("four or more nonsense").is_empty(), "unknown phrases are not guessed")


func test_reader_gates_the_effect_it_belongs_to() -> void:
	var r := OracleIr.new()
	assert_true(r._read_effects("Draw a card if you control three or more artifacts"))
	var params: Dictionary = (r._effects[0] as Dictionary)["params"]
	assert_true(params.has("if_cond"), "the draw carries its condition")


func test_my_turn_and_hand_conditions() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var o := _any_object(engine)
	engine.state.active_player_id = 0
	assert_true(engine.layers.condition_met(engine.state, o, {"my_turn": true}))
	engine.state.active_player_id = 1
	assert_false(engine.layers.condition_met(engine.state, o, {"my_turn": true}))
	assert_true(engine.layers.condition_met(engine.state, o, {"hand_max": 0}), "an empty hand")


func test_creature_died_flag_gates_morbid() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var o := _any_object(engine)
	assert_false(engine.layers.condition_met(engine.state, o, {"creature_died": true}))
	engine.state.creatures_died_this_turn = 1
	assert_true(engine.layers.condition_met(engine.state, o, {"creature_died": true}))


func _any_object(engine: RulesEngine) -> GameObject:
	var o := GameObject.new()
	o.controller_id = 0
	o.owner_id = 0
	return o
