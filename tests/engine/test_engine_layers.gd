@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_layers"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_printed_pt_unchanged_by_pump() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	var before: Dictionary = engine.layers.snapshot(engine.state, piker)
	assert_eq(before.printed_power, 2)
	assert_eq(before.power, 2)
	var fx := ContinuousEffect.new()
	fx.power = 1
	fx.toughness = 1
	fx.until_eot = true
	engine.state.effects.append(fx)
	var after: Dictionary = engine.layers.snapshot(engine.state, piker)
	assert_eq(after.power, 3)
	assert_eq(after.printed_power, 2)
	engine.layers.clear_until_eot(engine.state)
	var cleared: Dictionary = engine.layers.snapshot(engine.state, piker)
	assert_eq(cleared.power, 2)
