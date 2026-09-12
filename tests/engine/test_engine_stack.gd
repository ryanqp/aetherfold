@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_stack"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_creature_not_in_play_while_stacked() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var m1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var m2: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	m1.summoned_this_turn = false
	m2.summoned_this_turn = false
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	var old_id := piker.object_id
	assert_true(engine.submit(Fixtures.activate_mana(0, m1.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, m2.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, old_id)).ok, "cast")
	assert_eq(engine.state.mode, EngineEnums.EngineMode.PAYING_COSTS)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok, "pay")
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok, "confirm")
	var stack: MagicStack = engine.state.stack
	assert_eq(stack.size(), 1)
	var spell: GameObject = engine.state.objects[stack.top().object_id]
	assert_eq(spell.zone, EngineEnums.ZoneId.STACK)
	assert_eq(spell.linked_from, old_id)
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(bf.has(spell.object_id))
	assert_eq(bf.size(), 2)


func test_two_passes_resolve_vanilla_creature() -> void:
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
	var stack_id: int = (engine.state.stack as MagicStack).top().object_id
	Fixtures.both_pass(engine)
	assert_true((engine.state.stack as MagicStack).is_empty())
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(bf.size(), 3)
	var resolved: GameObject = engine.state.objects[bf.object_ids[bf.size() - 1]]
	assert_eq(resolved.zone, EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(resolved.linked_from, stack_id)
	assert_true((resolved.definition as CardDefinition).is_creature())
