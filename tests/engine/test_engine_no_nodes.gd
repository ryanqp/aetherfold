@tool
extends McpTestSuite

func suite_name() -> String:
	return "engine_no_nodes"


func test_kernel_types_are_not_nodes() -> void:
	var engine := RulesEngine.new()
	assert_eq(engine.get_class(), "RefCounted", "RulesEngine must not subclass Node")
	assert_eq(engine.state.get_class(), "RefCounted")
	assert_eq(engine.state.rng.get_class(), "RefCounted")
	assert_eq(engine.state.log.get_class(), "RefCounted")
	var rules := FormatRules.commander_4p()
	assert_eq(rules.get_class(), "Resource")
	engine.setup(rules, 1)
	assert_eq(engine.state.players[0].get_class(), "RefCounted")
	assert_eq(engine.state.zones.get_class(), "RefCounted")
	assert_eq(GameObject.new().get_class(), "RefCounted")
	assert_eq(engine.state.players[0].mana.get_class(), "RefCounted")
	assert_eq(CardDefinition.new().get_class(), "Resource")
	var result := engine.submit(GameAction.new())
	assert_eq(result.get_class(), "RefCounted")
	var v := engine.view()
	assert_eq(v.get_class(), "RefCounted")


func test_setup_without_autoload_or_data_dir() -> void:
	var engine := RulesEngine.new()
	engine.setup(FormatRules.commander_1v1_table(), 7)
	assert_eq(engine.state.players.size(), 2)
	assert_eq(engine.state.rng_seed, 7)
	assert_eq(engine.state.players[0].life, 40)
	assert_eq(engine.get_class(), "RefCounted")
