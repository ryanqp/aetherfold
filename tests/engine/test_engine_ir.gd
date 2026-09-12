@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_ir"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_fodder_makes_two_goblins() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var m1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var m2: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	m1.summoned_this_turn = false
	m2.summoned_this_turn = false
	var fodder: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Dragon Fodder")
	assert_true(engine.submit(Fixtures.activate_mana(0, m1.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, m2.object_id)).ok)
	Fixtures.pay_and_resolve_spell(engine, 0, fodder.object_id)
	assert_true((engine.state.stack as MagicStack).is_empty())
	var tokens := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.is_token:
			tokens += 1
			assert_eq((obj.definition as CardDefinition).name, "Goblin")
	assert_eq(tokens, 2)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 1)


func test_opt_draws() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	var opt: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Opt")
	assert_true(engine.submit(Fixtures.activate_mana(0, isl.object_id)).ok)
	Fixtures.pay_and_resolve_spell(engine, 0, opt.object_id)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 1)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 1)
	var drawn: GameObject = engine.state.objects[hand.object_ids[0]]
	assert_eq((drawn.definition as CardDefinition).name, "Goblin Piker")
