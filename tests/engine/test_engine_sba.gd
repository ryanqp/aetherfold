@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_sba"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_zero_life_loses() -> void:
	var engine := Fixtures.empty_engine_1v1()
	engine.state.players[0].life = 0
	assert_true(engine.sba.check(engine))
	assert_true(engine.state.players[0].lost)
	assert_true(engine.is_over())
	assert_eq(engine.state.mode, EngineEnums.EngineMode.GAME_OVER)


func test_legend_choice() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var a: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	var b: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	assert_true(engine.sba.check(engine))
	assert_eq(engine.state.mode, EngineEnums.EngineMode.CHOOSING_SBA)
	var keep := a.object_id
	var die := b.object_id
	var act := GameAction.new()
	act.kind = GameAction.Kind.CHOOSE_SBA
	act.player_id = 0
	act.object_id = keep
	assert_true(engine.submit(act).ok)
	assert_true(engine.state.objects.has(keep))
	assert_false(engine.state.objects.has(die) and engine.state.objects[die].zone == EngineEnums.ZoneId.BATTLEFIELD)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 1)
