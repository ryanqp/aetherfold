@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_priority"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_apnap_pass_rotation() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 0)
	assert_true(engine.submit(Fixtures.pass_priority(0)).ok)
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 1)
	assert_eq(engine.state.step, EngineEnums.Step.PRECOMBAT_MAIN)
	assert_true(engine.submit(Fixtures.pass_priority(1)).ok)
	assert_eq(engine.state.step, EngineEnums.Step.BEGIN_COMBAT)
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 0)


func test_caster_keeps_priority() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var m1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var m2: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	m1.summoned_this_turn = false
	m2.summoned_this_turn = false
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	assert_true(engine.submit(Fixtures.activate_mana(0, m1.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, m2.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, piker.object_id)).ok)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.GIVING_PRIORITY)
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 0)
	assert_true(engine.submit(Fixtures.pass_priority(0)).ok)
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 1)
	assert_eq((engine.state.stack as MagicStack).size(), 1)
