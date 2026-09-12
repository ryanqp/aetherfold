@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_mana"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_mountain_taps_for_red() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	mtn.tapped = false
	var result := engine.submit(Fixtures.activate_mana(0, mtn.object_id, &"mountain_r"))
	assert_true(result.ok, result.error)
	var pool: ManaPool = engine.state.players[0].mana
	assert_eq(pool.r, 1)
	assert_eq(pool.total(), 1)
	var after: GameObject = engine.state.objects[mtn.object_id]
	assert_true(after.tapped)
	assert_eq(after.zone, EngineEnums.ZoneId.BATTLEFIELD)


func test_island_taps_for_blue() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var isl: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Island")
	isl.summoned_this_turn = false
	var result := engine.submit(Fixtures.activate_mana(0, isl.object_id))
	assert_true(result.ok, result.error)
	assert_eq((engine.state.players[0].mana as ManaPool).u, 1)


func test_pay_one_and_red_via_mana_abilities() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var a: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	var b: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	a.summoned_this_turn = false
	b.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, a.object_id)).ok)
	assert_true(engine.submit(Fixtures.activate_mana(0, b.object_id)).ok)
	var pool: ManaPool = engine.state.players[0].mana
	assert_eq(pool.r, 2)
	var cost := ManaCost.parse("{1}{R}")
	assert_eq(cost.generic, 1)
	assert_eq(cost.r, 1)
	assert_eq(cost.cmc(), 2)
	assert_true(pool.can_pay(cost))
	assert_true(pool.pay(cost))
	assert_true(pool.is_empty())


func test_pool_empty_at_step_end() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, mtn.object_id)).ok)
	assert_eq((engine.state.players[0].mana as ManaPool).total(), 1)
	engine.mana.on_step_end()
	assert_true((engine.state.players[0].mana as ManaPool).is_empty())


func test_forgotten_cave_mana_from_ir() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var cave: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Forgotten Cave")
	cave.summoned_this_turn = false
	cave.tapped = false
	var result := engine.submit(Fixtures.activate_mana(0, cave.object_id, &"cave_r"))
	assert_true(result.ok, result.error)
	assert_eq((engine.state.players[0].mana as ManaPool).r, 1)
	var cycle := engine.submit(Fixtures.activate_mana(0, cave.object_id, &"cave_cycle"))
	assert_false(cycle.ok)


func test_tapped_land_cannot_activate() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, mtn.object_id)).ok)
	var again := engine.submit(Fixtures.activate_mana(0, mtn.object_id))
	assert_false(again.ok)


func test_legal_actions_include_mana_abilities() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	var kinds: Array = []
	for act in engine.legal_actions(0):
		kinds.append((act as GameAction).kind)
	assert_true(kinds.has(GameAction.Kind.ACTIVATE_MANA_ABILITY))
	assert_true(kinds.has(GameAction.Kind.PASS_PRIORITY))
