@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_commander"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_commander_can_go_to_command_zone() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	krenko.is_commander = true
	var old_id := krenko.object_id
	var moved: GameObject = engine.state.zones.move(old_id, EngineEnums.ZoneId.GRAVEYARD)
	assert_eq(moved, null)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.CHOOSING_REPLACEMENT)
	var act := GameAction.new()
	act.kind = GameAction.Kind.CHOOSE_REPLACEMENT
	act.player_id = 0
	act.extra = {dest_zone = EngineEnums.ZoneId.COMMAND}
	assert_true(engine.submit(act).ok)
	var cz: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.COMMAND, 0)
	assert_eq(cz.size(), 1)
	var now: GameObject = engine.state.objects[cz.object_ids[0]]
	assert_true(now.is_commander)
	assert_eq(now.linked_from, old_id)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 0)


func test_commander_tax_increases() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var k1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.COMMAND, "Krenko, Mob Boss")
	k1.is_commander = true
	engine.state.players[0].commander_cast_count["krenko_mob_boss"] = 1
	assert_true(engine.submit(Fixtures.cast_spell(0, k1.object_id)).ok)
	assert_eq(engine._payment.generic, 4)
	assert_eq(engine._payment.r, 2)
