@tool
extends McpTestSuite

const Fixtures := preload("res://tests/engine/fixtures.gd")

var db: CardDatabase

func suite_name() -> String:
	return "engine_turn"


func suite_setup(_ctx: Dictionary) -> void:
	db = Fixtures.memory_db()


func test_untap_and_upkeep_after_start_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.tapped = true
	mtn.summoned_this_turn = true
	engine.turn.start_turn(0)
	var after: GameObject = engine.state.objects[mtn.object_id]
	assert_false(after.tapped)
	assert_false(after.summoned_this_turn)
	assert_eq(engine.state.step, EngineEnums.Step.UPKEEP)
	assert_eq(engine.state.phase, EngineEnums.Phase.UPKEEP)
	assert_eq(engine.state.mode, EngineEnums.EngineMode.GIVING_PRIORITY)


func test_first_player_skips_draw_on_turn_one() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	assert_eq(engine.state.turn_number, 1)
	engine.turn.start_turn(0)
	assert_eq(engine.state.step, EngineEnums.Step.UPKEEP)
	Fixtures.both_pass(engine)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 0)
	assert_eq(engine.state.step, EngineEnums.Step.DRAW)


func test_draw_tba_on_later_turn() -> void:
	var engine := Fixtures.empty_engine_1v1()
	Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.LIBRARY, "Goblin Piker")
	engine.state.turn_number = 2
	engine.turn.start_turn(0)
	Fixtures.both_pass(engine)
	var hand: Zone = engine.state.zones.get_zone(EngineEnums.ZoneId.HAND, 0)
	assert_eq(hand.size(), 1)
	assert_eq(engine.state.step, EngineEnums.Step.DRAW)


func test_step_end_empties_pool() -> void:
	var engine := Fixtures.empty_engine_1v1()
	var mtn: GameObject = Fixtures.spawn_named(engine, db, 0, EngineEnums.ZoneId.BATTLEFIELD, "Mountain")
	mtn.summoned_this_turn = false
	assert_true(engine.submit(Fixtures.activate_mana(0, mtn.object_id)).ok)
	assert_eq((engine.state.players[0].mana as ManaPool).total(), 1)
	engine.turn.start_turn(0)
	assert_true((engine.state.players[0].mana as ManaPool).is_empty())


func test_two_passes_advance_main() -> void:
	var engine := Fixtures.empty_engine_1v1()
	assert_eq(engine.state.step, EngineEnums.Step.PRECOMBAT_MAIN)
	Fixtures.both_pass(engine)
	assert_eq(engine.state.step, EngineEnums.Step.BEGIN_COMBAT)
	assert_eq(int(engine.state.awaiting.get("player_id", -1)), 0)
