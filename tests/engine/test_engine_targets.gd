@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_targets"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_counterspell_counters() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var m1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var m2: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var i1: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	var i2: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	for obj in [m1, m2, i1, i2]:
		obj.summoned_this_turn = false
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Goblin Piker")
	var ctr: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Counterspell")
	assert_true(engine.submit(Fixtures.activate_mana(0, m1.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, m2.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, piker.object_id)).ok)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	var sid: int = (engine.state.stack as MagicStack).top().stack_id
	assert_true(engine.submit(Fixtures.activate_mana(0, i1.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, i2.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, ctr.object_id)).ok)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.CASTING)
	assert_true(engine.submit(Fixtures.choose_targets(0, [sid])).ok)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	Fixtures.both_pass(engine)
	assert_true((engine.state.stack as MagicStack).is_empty())
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_eq(bf.size(), 4)
	var gy: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.GRAVEYARD, 0)
	assert_eq(gy.size(), 2)


func test_unsummon_returns_creature() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	var piker: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Goblin Piker")
	piker.summoned_this_turn = false
	var uns: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.HAND, "Unsummon")
	var pid := piker.object_id
	assert_true(engine.submit(Fixtures.activate_mana(0, isl.object_id)).ok)
	assert_true(engine.submit(Fixtures.cast_spell(0, uns.object_id)).ok)
	assert_true(engine.submit(Fixtures.choose_targets(0, [pid])).ok)
	assert_true(engine.submit(Fixtures.pay_mana(0)).ok)
	assert_true(engine.submit(Fixtures.confirm_pay(0)).ok)
	Fixtures.both_pass(engine)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 1)
	var bounced: GameObject = engine.state.objects[hand.object_ids[0]]
	assert_eq(bounced.linked_from, pid)
	assert_eq((bounced.definition as CardDefinition).name, "Goblin Piker")
	var bf: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.BATTLEFIELD)
	assert_false(bf.has(pid))


func test_cancel_shares_counter_primitive() -> void:
	var db_cancel: CardDefinition = db.definition_for("Cancel")
	var ab: Ability = db_cancel.spell_ability()
	assert_true(ab != null)
	assert_eq(str((ab.effects[0] as AbilityEffect).kind), "COUNTER_SPELL")
