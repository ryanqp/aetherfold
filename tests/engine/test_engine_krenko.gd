@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_krenko"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_sickness_blocks_tap() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	assert_true(krenko.summoned_this_turn)
	var result := engine.submit(Fixtures.activate_ability(0, krenko.object_id, &"krenko_tap"))
	assert_false(result.ok)


func test_tap_makes_goblins_from_query() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var krenko: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Krenko, Mob Boss")
	engine.turn.start_turn(0)
	var kid := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.definition is CardDefinition and (obj.definition as CardDefinition).name.begins_with("Krenko"):
			kid = obj.object_id
	assert_gt(kid, 0)
	assert_true(engine.submit(Fixtures.activate_ability(0, kid, &"krenko_tap")).ok)
	assert_eq((engine.state.stack as MagicStack).size(), 1)
	Fixtures.both_pass(engine)
	var tokens := 0
	bf = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.is_token:
			tokens += 1
	assert_eq(tokens, 1)
	assert_true(engine.state.objects[kid].tapped)
