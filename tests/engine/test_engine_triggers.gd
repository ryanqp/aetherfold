@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_triggers"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_talrand_makes_drake_on_instant() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var talrand: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Talrand, Sky Summoner")
	talrand.summoned_this_turn = false
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	var opt: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Opt")
	assert_true(engine.submit(Fixtures.activate_mana(0, isl.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, opt.object_id)).ok)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	assert_eq((engine.state.stack as MagicStack).size(), 2)
	Fixtures.both_pass(engine)
	var drakes := 0
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	for oid in bf.object_ids:
		var obj: GameObject = engine.state.objects[oid]
		if obj.is_token and obj.definition is CardDefinition and (obj.definition as CardDefinition).name == "Drake":
			drakes += 1
	assert_eq(drakes, 1)
	Fixtures.both_pass(engine)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 1)
